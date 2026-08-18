/// More than one agent, connected at once.
///
/// The app held exactly one `AgentBackend`, which is why the memory bridge
/// could not ask both servers anything: "what does Hermes know that OpenClaw
/// does not" had no way to reach two servers in one breath. This holds as many
/// as there are saved, connects them on demand, and disposes them together.
///
/// **It does not replace the ledger, and the ledger does not replace it.** A
/// live read is better whenever a server answers; a snapshot is the only thing
/// there is when one is switched off, unreachable, or waiting for a device to
/// be approved. Phase 2's cache covers exactly the cases this cannot, which is
/// why both exist.
library;

import 'dart:async';

import 'package:agent_core/agent_core.dart';

import 'backend_factory.dart';
import 'connection_store.dart';

/// What became of one attempt to reach a saved server.
class PooledBackend {
  PooledBackend._({required this.connection, this.backend, this.failure});

  final SavedConnection connection;

  /// Null when it could not be reached — see [failure].
  final AgentBackend? backend;

  /// Why it is not usable, in words. Null when it is.
  final String? failure;

  bool get isUsable => backend != null;

  /// True when the server is fine and the *device* is the thing waiting.
  ///
  /// Distinguished from a failure because nothing is wrong and retrying will
  /// not help — an operator has to approve the device somewhere else, and
  /// telling the user their connection failed would send them hunting for a
  /// problem that is not there.
  bool get awaitingApproval =>
      backend?.connectionState.status == AgentStatus.awaitingApproval;

  @override
  String toString() =>
      'PooledBackend(${connection.displayLabel}, '
      '${isUsable ? backend!.id : 'failed: $failure'})';
}

/// Connects the saved servers, keeps them, and lets them go together.
///
/// Deliberately not eager. Opening every saved connection at launch would pay
/// a full handshake — and on OpenClaw a pairing check — for servers the user
/// may not touch this session. Callers ask when they need them.
class BackendPool {
  BackendPool({ConnectionStore? store, this.buildFor = buildBackend})
    : _store = store ?? ConnectionStore();

  final ConnectionStore _store;

  /// Seam for tests, which have no sockets and no Keychain.
  final Future<BuiltBackend> Function(SavedConnection, String) buildFor;

  final Map<String, PooledBackend> _pooled = {};

  /// Backends this pool opened, so it can close exactly those.
  final Map<String, AgentBackend> _owned = {};

  /// A backend the pool did not open and must not close.
  ///
  /// The workspace's own connection is already live and already owned by
  /// somebody else. Adopting it rather than opening a second socket to the
  /// same server is the difference between one connection and two.
  void adopt(String connectionId, AgentBackend backend) {
    _pooled[connectionId] = PooledBackend._(
      connection: SavedConnection(
        id: connectionId,
        label: backend.displayName,
        url: '',
        backendId: backend.id,
      ),
      backend: backend,
    );
  }

  /// Every saved server, connected where possible.
  ///
  /// [except] is the connection the caller already holds — normally the
  /// workspace's own, passed to [adopt] first. Failures are returned rather
  /// than thrown: one unreachable server must not cost the answer the others
  /// can give, which is the whole reason a pool is worth having.
  Future<List<PooledBackend>> connectAll({
    Set<String> except = const {},
  }) async {
    final saved = await _store.list();
    await Future.wait([
      for (final connection in saved)
        if (!except.contains(connection.id) &&
            !_pooled.containsKey(connection.id))
          _connect(connection),
    ]);
    return _pooled.values.toList();
  }

  Future<void> _connect(SavedConnection connection) async {
    final lookup = await _store.readToken(connection.id);
    final token = lookup.token;
    if (token == null) {
      _pooled[connection.id] = PooledBackend._(
        connection: connection,
        failure: lookup.reason ?? 'No saved token.',
      );
      return;
    }
    try {
      final built = await buildFor(connection, token);
      await built.backend.connect();
      _owned[connection.id] = built.backend;
      _pooled[connection.id] = PooledBackend._(
        connection: connection,
        backend: built.backend,
      );
    } catch (e) {
      _pooled[connection.id] = PooledBackend._(
        connection: connection,
        failure: e is AgentException && e.detail.isNotEmpty ? e.detail : '$e',
      );
    }
  }

  /// The pooled entries that can actually answer a question.
  List<PooledBackend> get usable => [
    for (final p in _pooled.values)
      if (p.isUsable) p,
  ];

  /// Why each unreachable server is unreachable, for showing rather than
  /// swallowing. A bridge that quietly omits a server is a bridge that lies
  /// about what it compared.
  Map<String, String> get failures => {
    for (final p in _pooled.values)
      if (!p.isUsable) p.connection.displayLabel: p.failure ?? 'unknown',
  };

  /// Closes only what this pool opened. An adopted backend belongs to its
  /// owner and closing it here would take the workspace's connection down.
  Future<void> dispose() async {
    for (final backend in _owned.values) {
      try {
        await backend.dispose();
      } on Object {
        // Closing is cleanup; a socket that is already gone is the outcome.
      }
    }
    _owned.clear();
    _pooled.clear();
  }
}
