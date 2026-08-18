/// Several agents, connected at once, switchable like tabs.
///
/// The app pushed one `WorkspaceScreen` onto the navigator and disposed its
/// workspace on the way back, so connecting to a second agent meant
/// disconnecting from the first. `BackendPool` already proved several backends
/// can be held; this is the part that gives them somewhere to live and a way
/// to be looked at.
///
/// **Owning the lifecycle is the whole job.** A tab that is not on screen must
/// stay connected — that is what makes it a tab rather than a bookmark — and
/// closing one must dispose exactly its own workspace and backend, not the
/// active one and not all of them.
library;

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

import 'backend_factory.dart';
import 'connection_store.dart';
import 'workspace.dart';

/// A live agent the connect screen has finished with.
///
/// Lives here rather than beside the shell so the connect screen can hand one
/// back without importing the shell that pushed it — which would be a cycle.
class ConnectedAgent {
  const ConnectedAgent({
    required this.connection,
    required this.workspace,
    required this.backend,
  });

  final SavedConnection connection;
  final Workspace workspace;
  final AgentBackend backend;
}

/// One connected agent, and everything that belongs to it.
class AgentTab {
  AgentTab({
    required this.connection,
    required this.workspace,
    required this.backend,
  });

  final SavedConnection connection;
  final Workspace workspace;
  final AgentBackend backend;

  /// What the tab is called. The server's own name, because that is what the
  /// user typed and what distinguishes two agents of the same kind.
  String get label => connection.displayLabel;

  /// Which agent is behind it — shown beside the label, since one person can
  /// reasonably run two OpenClaw gateways.
  String get backendLabel => connection.backendLabel;

  AgentStatus get status => backend.connectionState.status;

  Future<void> dispose() async {
    workspace.dispose();
    await backend.dispose();
  }
}

/// The open tabs, and which one is in front.
///
/// A [ChangeNotifier] rather than a widget so the shell, the tab strip and any
/// panel can all read the same list without one of them owning the others.
class AgentTabs extends ChangeNotifier {
  AgentTabs({ConnectionStore? store, this.buildFor = buildBackend})
    : _store = store ?? ConnectionStore();

  final ConnectionStore _store;

  /// Seam for tests, which have no sockets and no Keychain.
  final Future<BuiltBackend> Function(SavedConnection, String) buildFor;

  final List<AgentTab> _tabs = [];
  int _activeIndex = 0;

  List<AgentTab> get tabs => List.unmodifiable(_tabs);
  bool get isEmpty => _tabs.isEmpty;
  int get length => _tabs.length;

  /// The tab in front, or null when none are open.
  AgentTab? get active =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  int get activeIndex =>
      _tabs.isEmpty ? 0 : _activeIndex.clamp(0, _tabs.length - 1);

  /// Whether [connection] is already open. Opening it again would be a second
  /// socket to the same server — and on OpenClaw a second device pairing.
  bool isOpen(String connectionId) =>
      _tabs.any((t) => t.connection.id == connectionId);

  /// Brings an already-open connection forward, or reports that it is not.
  bool focus(String connectionId) {
    final index = _tabs.indexWhere((t) => t.connection.id == connectionId);
    if (index < 0) return false;
    _activeIndex = index;
    notifyListeners();
    return true;
  }

  /// Adopts a workspace someone else built — the connect screen's, which is
  /// already connected by the time it hands over.
  ///
  /// Focuses the existing tab instead if this connection is already open,
  /// rather than stacking a duplicate.
  /// Returns false when [connection] was already open, having disposed the
  /// duplicate rather than leaving it to the caller.
  ///
  /// Silently returning used to leak the whole agent: a live socket, its
  /// timers, and on OpenClaw a second device pairing — once per press of the
  /// + button. Disposing here rather than returning a flag the caller must
  /// remember to act on, because forgetting is exactly what happened.
  Future<bool> adopt({
    required SavedConnection connection,
    required Workspace workspace,
    required AgentBackend backend,
  }) async {
    if (focus(connection.id)) {
      workspace.dispose();
      await backend.dispose();
      return false;
    }
    _tabs.add(
      AgentTab(
        connection: connection,
        workspace: workspace..connectionId = connection.id,
        backend: backend,
      ),
    );
    _activeIndex = _tabs.length - 1;
    notifyListeners();
    return true;
  }

  /// Connects [connection] and opens it in a new tab.
  ///
  /// Throws on failure rather than opening a dead tab: a tab strip full of
  /// entries that cannot answer is worse than a visible error, and the caller
  /// has somewhere to show one.
  Future<AgentTab> open(SavedConnection connection) async {
    if (focus(connection.id)) return _tabs[_activeIndex];

    final lookup = await _store.readToken(connection.id);
    final token = lookup.token;
    if (token == null) {
      throw AgentException(
        AgentFailure.unauthorized,
        detail: lookup.reason ?? 'No token is saved for ${connection.label}.',
      );
    }

    final built = await buildFor(connection, token);
    try {
      await built.backend.connect();
    } catch (e) {
      // Nothing half-open is kept. A backend that failed to connect still
      // holds a socket and a timer, and leaking one per failed attempt is how
      // an app ends up with forty of them.
      await built.backend.dispose();
      rethrow;
    }

    final workspace =
        built.gateway == null
              ? Workspace.forBackend(built.backend)
              : Workspace.forBackend(built.backend, gateway: built.gateway)
          ..connectionId = connection.id;

    final tab = AgentTab(
      connection: connection,
      workspace: workspace,
      backend: built.backend,
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    notifyListeners();
    return tab;
  }

  /// Reopens the tabs that were open when the app last closed.
  ///
  /// Returns the servers it could not reach, so the caller can say so — a
  /// launch that silently drops a tab looks like the app forgot it, which is
  /// the opposite of what persistence is for.
  ///
  /// Failures are per tab. One server being switched off must not cost the
  /// others, and must not leave the user at a form when three of their four
  /// agents are perfectly reachable.
  ///
  /// Falls back to [ConnectionStore.lastUsedId] when nothing was recorded,
  /// which is the honest reading for someone upgrading from a build that had
  /// no tabs: land where they left off, not at a form.
  Future<Map<String, String>> restore() async {
    final saved = {for (final c in await _store.list()) c.id: c};
    var (:ids, :active) = await _store.openTabs();
    if (ids.isEmpty) {
      final last = await _store.lastUsedId();
      if (last != null && saved.containsKey(last)) ids = [last];
    }

    final failures = <String, String>{};
    for (final id in ids) {
      final connection = saved[id];
      // A server forgotten since the tabs were written is not a failure to
      // report; it is simply gone, and saying so would be noise.
      if (connection == null) continue;
      try {
        await open(connection);
      } catch (e) {
        failures[connection.displayLabel] =
            e is AgentException && e.detail.isNotEmpty ? e.detail : '$e';
      }
    }
    if (active >= 0 && active < _tabs.length) {
      _activeIndex = active;
      notifyListeners();
    }
    return failures;
  }

  /// Records which tabs are open, so the next launch can reopen them.
  ///
  /// Called by the shell after every change rather than on exit: a desktop app
  /// is quit by force often enough that an on-exit write is a write that does
  /// not happen.
  Future<void> persist() =>
      _store.setOpenTabs([for (final t in _tabs) t.connection.id], activeIndex);

  void setActive(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Closes one tab, disposing exactly its own workspace and backend.
  ///
  /// The index moves to the neighbour rather than to zero: closing the third
  /// of five tabs should land on the fourth, the way every tabbed thing
  /// behaves, not throw the user back to the first.
  Future<void> close(String connectionId) async {
    final index = _tabs.indexWhere((t) => t.connection.id == connectionId);
    if (index < 0) return;
    final tab = _tabs.removeAt(index);
    if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
    if (_activeIndex < 0) _activeIndex = 0;
    notifyListeners();
    await tab.dispose();
  }

  /// Reconnects a Hermes tab with a different server-side profile.
  Future<AgentTab> switchProfile(AgentTab tab, String profile) async {
    final token = (await _store.readToken(tab.connection.id)).token;
    if (token == null) {
      throw AgentException(
        AgentFailure.unauthorized,
        detail: 'The saved connection token could not be read.',
      );
    }
    final updated = await _store.save(
      id: tab.connection.id,
      label: tab.connection.label,
      url: tab.connection.url,
      token: token,
      backendId: tab.connection.backendId,
      requestAdmin: tab.connection.requestAdmin,
      profile: profile,
    );
    await close(tab.connection.id);
    return open(updated);
  }

  /// Every open agent's live backend, for the memory bridge.
  ///
  /// This is what the tabs buy the bridge: no pool to build, no handshake to
  /// pay, no pairing check — the connections are already open because the user
  /// opened them.
  Map<String, AgentBackend> get connectedBackends => {
    for (final tab in _tabs) tab.backend.id: tab.backend,
  };

  @override
  Future<void> dispose() async {
    final closing = List<AgentTab>.from(_tabs);
    _tabs.clear();
    super.dispose();
    for (final tab in closing) {
      await tab.dispose();
    }
  }
}
