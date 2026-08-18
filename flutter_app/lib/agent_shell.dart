import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import 'agent_tabs.dart';
import 'app_lifecycle_coordinator.dart';
import 'connect_screen.dart';
import 'connection_store.dart';
import 'design/press.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'haptics.dart';
import 'main.dart' show settingsRequest, shortcutRequest;
import 'settings_page.dart';
import 'startup_presets.dart';
import 'workspace.dart';
import 'workspace_screen.dart';

/// The app, once more than one agent can be open at a time.
///
/// Every tab's `WorkspaceScreen` is kept alive in an [IndexedStack] rather than
/// rebuilt on switch. That is not an optimisation: a workspace holds the live
/// socket, the streaming transcript and the scroll position, and rebuilding it
/// would drop the turn in flight every time the user glanced at another agent.
///
/// On a phone the strip is horizontally scrollable and each tab is a chip; on a
/// Mac it is the same strip, which is what a browser does and what makes the
/// two feel like one app rather than two designs.
class AgentShell extends StatefulWidget {
  const AgentShell({super.key});

  @override
  State<AgentShell> createState() => _AgentShellState();
}

class _AgentShellState extends State<AgentShell> {
  final _tabs = AgentTabs();
  late final _lifecycle = AppLifecycleCoordinator(_tabs);

  /// True until the saved tabs have been reopened, so the connect screen does
  /// not flash up in front of agents that are about to appear.
  bool _restoring = true;

  /// Servers that were open last time and could not be reached now.
  Map<String, String> _failedToRestore = const {};

  @override
  void initState() {
    super.initState();
    _lifecycle.attach();
    _tabs.addListener(_persist);
    // The menu bar's Settings… and the tray item's 设置… both land here.
    settingsRequest.addListener(_openSettingsFromTray);
    // The macOS menu bar's shortcuts (⌘N / ⌘R / ⌘⇧R) arrive here and act on
    // the active agent.
    shortcutRequest.addListener(_onShortcut);
    _restore();
    // Carry the desktop's pre-seeded OpenClaw into this install before the
    // saved-tab restore finishes, so the connect list already has it whether
    // or not the connect screen is ever opened.
    unawaited(seedStartupPresets(ConnectionStore()));
  }

  Future<void> _restore() async {
    final failures = await _tabs.restore();
    if (!mounted) return;
    setState(() {
      _restoring = false;
      _failedToRestore = failures;
    });
  }

  /// After every change rather than on exit — a desktop app is force-quit
  /// often enough that an on-exit write is a write that does not happen.
  void _persist() => _tabs.persist();

  @override
  void dispose() {
    _lifecycle.dispose();
    _tabs.removeListener(_persist);
    settingsRequest.removeListener(_openSettingsFromTray);
    shortcutRequest.removeListener(_onShortcut);
    _tabs.dispose();
    super.dispose();
  }

  /// Opens Settings for the active tab — the menu bar's Settings… (⌘,)
  /// and the tray item's 设置… both arrive through [settingsRequest], and
  /// the shell is the only place that knows which tab is active.
  void _openSettingsFromTray() {
    if (!mounted) return;
    final tab = _tabs.active;
    if (tab == null) return;
    showSettingsOverlay(context, tab.workspace);
  }

  /// ⌘N / ⌘R / ⌘⇧R from the macOS menu bar, routed to the active agent.
  void _onShortcut() {
    final name = shortcutRequest.value;
    final tab = _tabs.active;
    if (!mounted || name == null || tab == null) return;
    switch (name) {
      case 'newSession':
        unawaited(tab.workspace.createSession());
      case 'reconnect':
        unawaited(tab.workspace.reconnect());
      case 'refreshSessions':
        unawaited(tab.workspace.refreshSessions());
    }
  }

  /// Opens the connect screen, and adopts whatever it connected.
  ///
  /// The connect screen builds and connects the backend itself — it has to,
  /// because the OpenClaw pairing gate is part of connecting and it is the
  /// screen that shows it. So it hands the result over rather than being asked
  /// for credentials.
  Future<void> _addAgent() async {
    final opened = await Navigator.of(context).push<ConnectedAgent>(
      MaterialPageRoute(
        builder: (_) => ConnectScreen(
          asTab: true,
          // Without this the screen reconnects the last-used server the
          // instant it opens — which is the tab you already have — pops with
          // it, and the shell focuses the tab you were already on. Pressing +
          // did nothing but rebuild the connection you had.
          autoReconnect: false,
          alreadyOpen: {for (final t in _tabs.tabs) t.connection.id},
          onFocusExisting: (id) {
            _tabs.focus(id);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
    if (opened == null || !mounted) return;
    await _tabs.adopt(
      connection: opened.connection,
      workspace: opened.workspace,
      backend: opened.backend,
    );
  }

  Future<void> _close(AgentTab tab) async {
    Haptics.tap();
    await _tabs.close(tab.connection.id);
    if (mounted && _tabs.isEmpty) await _addAgent();
  }

  /// Reopens [tab] asking the gateway for `operator.admin`.
  ///
  /// OpenClaw gates switching a running session's model behind
  /// `sessions.patch` → `operator.admin` (verified in the gateway source), so
  /// the model chip's *Request administrator* action lands here: persist the
  /// choice on the saved connection, close the tab, and reopen it with the
  /// elevated scopes. The session itself lives on the server, so reopening is
  /// a new socket, not lost work.
  Future<bool> _reconnectWithAdmin(AgentTab tab) async {
    final store = ConnectionStore();
    final lookup = await store.readToken(tab.connection.id);
    final token = lookup.token;
    if (token == null) return false;
    final updated = await store.save(
      id: tab.connection.id,
      label: tab.connection.label,
      url: tab.connection.url,
      token: token,
      backendId: tab.connection.backendId,
      requestAdmin: true,
      profile: tab.connection.profile,
    );
    if (!mounted) return false;
    await _tabs.close(tab.connection.id);
    try {
      await _tabs.open(updated);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reconnect failed: $e')));
      }
      return false;
    }
  }

  Future<void> _switchHermesProfile(AgentTab tab) async {
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => _ProfileDialog(initial: tab.connection.profile),
    );
    if (!mounted || entered == null) return;
    final profile = entered.replaceAll(RegExp(r'\s'), '');
    if (profile.isEmpty) return;
    if (profile == tab.connection.profile) return;
    try {
      await _tabs.switchProfile(tab, profile);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Profile switch failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _tabs,
    builder: (context, _) {
      if (_restoring) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (_tabs.isEmpty) {
        // Nothing open yet: the connect screen *is* the app, exactly as it was
        // before tabs existed. No empty strip, no placeholder.
        return ConnectScreen(
          // The shell already decided what to reopen. Letting the connect
          // screen also reconnect the last-used server would open the same
          // one twice — and on OpenClaw that is a second device pairing.
          autoReconnect: false,
          onConnected: (agent) => unawaited(
            _tabs.adopt(
              connection: agent.connection,
              workspace: agent.workspace,
              backend: agent.backend,
            ),
          ),
        );
      }
      // On a Mac the strip floats in the same row as the traffic lights
      // (the design's desktop top edge). On a phone the agent chips sit at the
      // very top of the screen (highest hierarchy: agent > session > transcript),
      // rendered above the session top bar.
      final isPhone = defaultTargetPlatform != TargetPlatform.macOS;
      final strip = _TabStrip(tabs: _tabs, onAdd: _addAgent, onClose: _close);
      return Scaffold(
        body: isPhone
            ? Column(
                children: [
                  if (_failedToRestore.isNotEmpty)
                    _RestoreFailures(
                      failures: _failedToRestore,
                      onDismiss: () =>
                          setState(() => _failedToRestore = const {}),
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: _tabs.activeIndex,
                      children: [
                        for (final tab in _tabs.tabs)
                          WorkspaceScreen(
                            key: ValueKey(tab.connection.id),
                            workspace: tab.workspace,
                            onReconnectWithAdmin: tab.connection.isOpenClaw
                                ? () => _reconnectWithAdmin(tab)
                                : null,
                            onSwitchHermesProfile:
                                tab.connection.backendId ==
                                    SavedConnection.hermes
                                ? () => _switchHermesProfile(tab)
                                : null,
                            hermesProfile: tab.connection.profile,
                            onAddAgent: _addAgent,
                            mobileAgentChips: _tabs.length > 1 ? strip : null,
                            peers: MemoryPeers(
                              backends: _tabs.connectedBackends,
                              openConnectionIds: {
                                for (final t in _tabs.tabs) t.connection.id,
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            : SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // The tabs sit in the same row as the traffic lights. The lights are
                    // nudged down 6 pt from the system position (MainFlutterWindow), so
                    // the tab row carries the same 6 pt top offset to stay aligned.
                    // The shell's left padding matches the lights' left edge (~9 pt).
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 14, 0),
                      child: strip,
                    ),
                    // A tab that was open last time and is not now. Saying so beats
                    // silently dropping it, which looks like the app forgot.
                    if (_failedToRestore.isNotEmpty)
                      _RestoreFailures(
                        failures: _failedToRestore,
                        onDismiss: () =>
                            setState(() => _failedToRestore = const {}),
                      ),
                    Expanded(
                      // Every tab stays built, so switching does not restart a turn.
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 14, 14),
                        child: IndexedStack(
                          index: _tabs.activeIndex,
                          children: [
                            for (final tab in _tabs.tabs)
                              WorkspaceScreen(
                                // Keyed by connection so Flutter keeps each tab's state
                                // with its tab when one before it is closed. Without
                                // this the list shifts and tab 3's transcript appears
                                // under tab 2's name.
                                key: ValueKey(tab.connection.id),
                                workspace: tab.workspace,
                                onReconnectWithAdmin: tab.connection.isOpenClaw
                                    ? () => _reconnectWithAdmin(tab)
                                    : null,
                                onSwitchHermesProfile:
                                    tab.connection.backendId ==
                                        SavedConnection.hermes
                                    ? () => _switchHermesProfile(tab)
                                    : null,
                                hermesProfile: tab.connection.profile,
                                // The profile row's 「＋ 连接新后端」opens the same
                                // connect flow the tab strip's + button does.
                                onAddAgent: _addAgent,
                                mobileAgentChips: null,
                                // The memory bridge reuses tabs that are already open:
                                // no handshake, and on OpenClaw no second device
                                // pairing. The ids stop the pool from reopening them.
                                peers: MemoryPeers(
                                  backends: _tabs.connectedBackends,
                                  openConnectionIds: {
                                    for (final t in _tabs.tabs) t.connection.id,
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      );
    },
  );
}

/// The row of open agents.
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.onAdd,
    required this.onClose,
  });

  final AgentTabs tabs;
  final VoidCallback onAdd;
  final Future<void> Function(AgentTab) onClose;

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    final compact = MediaQuery.sizeOf(context).width < 720;
    // No strip box: the tabs and the ➕ float directly on the window, one row
    // tall so they sit at the same height as the traffic lights. The ➕ rides
    // as the last item of the horizontal list, so it always sits right after
    // the newest tab instead of being pinned to the far right.
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: compact ? 42 : 36,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          // On macOS the window's traffic lights float over the top-left. Tabs
          // start after that zone (≈70 pt from the window edge), so the green
          // light never sits on top of a tab. Phones have no traffic lights,
          // so they keep the tight 12 pt inset.
          padding: EdgeInsets.fromLTRB(
            isDesktop && defaultTargetPlatform == TargetPlatform.macOS
                ? 70
                : 12,
            compact ? 3 : 2,
            12,
            compact ? 3 : 2,
          ),
          itemCount: tabs.length + 1,
          itemBuilder: (context, i) {
            if (i == tabs.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Tooltip(
                  message: 'Connect another agent',
                  child: Pressable(
                    onTap: onAdd,
                    semanticLabel: 'Connect another agent',
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 8,
                        vertical: compact ? 4 : 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(compact ? 16 : 10),
                        border: Border.all(
                          color: context.ink.base.withValues(alpha: .18),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.add_rounded,
                          size: 15,
                          color: context.ink.secondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            return _Tab(
              tab: tabs.tabs[i],
              selected: i == tabs.activeIndex,
              canClose: tabs.length > 1,
              compact: compact,
              // Closing is offered even for the last tab: the shell reopens
              // the connect screen, which is where someone who closed their
              // only agent wants to be anyway.
              onTap: () {
                Haptics.tap();
                tabs.setActive(i);
              },
              onClose: () => onClose(tabs.tabs[i]),
            );
          },
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.selected,
    required this.canClose,
    required this.compact,
    required this.onTap,
    required this.onClose,
  });

  final AgentTab tab;
  final bool selected;
  final bool canClose;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onClose;

  /// A dot rather than a word. The strip is the one place where several
  /// connections are visible at once, so their health has to fit in the space
  /// a label does not need.
  static Color _colourFor(AgentStatus status) => switch (status) {
    AgentStatus.connected => Palette.jade,
    AgentStatus.connecting || AgentStatus.reconnecting => Palette.azure,
    // Nothing is wrong and retrying will not help — an operator has to
    // approve the device elsewhere. Amber, not red.
    AgentStatus.awaitingApproval => Palette.brass,
    _ => Palette.coral,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = compact ? 16.0 : 10.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: Pressable(
        onTap: onTap,
        haptic: false,
        semanticLabel: '${tab.label}, ${tab.backendLabel}',
        child: AnimatedContainer(
          duration: Motion.standard,
          curve: Motion.standardCurve,
          padding: EdgeInsets.only(
            left: compact ? 10 : 8,
            right: canClose ? 2 : (compact ? 10 : 8),
            top: 2,
            bottom: 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: selected ? null : context.ink.base.withValues(alpha: .06),
            border: Border.all(
              color: selected
                  ? context.ink.base.withValues(alpha: .26)
                  : context.ink.base.withValues(alpha: .11),
            ),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      context.ink.base.withValues(alpha: .16),
                      context.ink.base.withValues(alpha: .05),
                    ],
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Subscribed, not sampled. Reading connectionState once means
              // the dot only changes when something else happens to rebuild
              // the strip — so a tab that drops stays green until the user
              // touches an unrelated tab.
              StreamBuilder<AgentConnection>(
                stream: tab.backend.connection,
                initialData: tab.backend.connectionState,
                builder: (context, snapshot) {
                  final status =
                      snapshot.data?.status ?? AgentStatus.disconnected;
                  return _StatusDot(
                    colour: _colourFor(status),
                    // A reconnecting tab pulses, because "trying" and "gave
                    // up" are the same amber otherwise and only one of them
                    // is worth interrupting for.
                    busy:
                        status == AgentStatus.connecting ||
                        status == AgentStatus.reconnecting,
                  );
                },
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 160 : 130),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        tab.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: compact ? 12.5 : 12,
                          color: selected
                              ? context.ink.primary
                              : context.ink.secondary,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (compact && tab.backendLabel.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        tab.backendLabel.split(' · ')[0],
                        style: mono(context, size: 10, opacity: InkLevel.faint),
                      ),
                    ],
                  ],
                ),
              ),
              if (canClose)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Pressable(
                    onTap: onClose,
                    haptic: false,
                    semanticLabel: 'Close ${tab.label}',
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: Center(
                        child: Icon(
                          Icons.close_rounded,
                          size: 11,
                          color: context.ink.faint,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The health of one connection, in seven points of width.
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.colour, required this.busy});

  final Color colour;
  final bool busy;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.busy && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (context, _) => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: widget.colour.withValues(
          alpha: widget.busy ? 0.35 + 0.65 * _pulse.value : 1,
        ),
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// Tabs that were open last launch and could not be reopened.
class _RestoreFailures extends StatelessWidget {
  const _RestoreFailures({required this.failures, required this.onDismiss});

  final Map<String, String> failures;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    color: Palette.coral.withValues(alpha: .12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 15, color: Palette.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              failures.length == 1
                  ? 'Could not reopen ${failures.keys.single} — '
                        '${failures.values.single}'
                  : 'Could not reopen ${failures.keys.join(", ")}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Pressable(
            onTap: onDismiss,
            semanticLabel: 'Dismiss',
            child: const SizedBox(
              width: 32,
              height: 32,
              child: Icon(Icons.close_rounded, size: 14),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Asks which Hermes profile a connected tab should switch to.
///
/// Owns its text controller so the field outlives the dialog's exit
/// animation; disposing it as soon as `showDialog` returned tripped a
/// TextEditingController-used-after-dispose assertion on the way out.
class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.initial});

  final String initial;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Switch Hermes profile'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Profile',
        hintText: 'default',
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Switch')),
    ],
  );
}
