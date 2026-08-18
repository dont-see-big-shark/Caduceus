import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agent_core/agent_core.dart';

import 'console_view.dart';
import 'design/components.dart';
import 'design/glass.dart';
import 'design/press.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'agents_panel.dart';
import 'capabilities_hub.dart';
import 'fleet_panel.dart';
import 'memory_panel.dart';
import 'panel_rail.dart';
import 'panels_overlay.dart';
import 'processes_panel.dart';
import 'shared_memory_panel.dart';
import 'skills_panel.dart';
import 'settings_page.dart';
import 'widgets/panel_frame.dart';
import 'widgets/session_drawer.dart';
import 'widgets/session_row.dart';
import 'startup_presets.dart';
import 'jobs_panel.dart';
import 'connect_screen.dart';
import 'projects_panel.dart';
import 'l10n/app_localizations.dart';
import 'workspace.dart';

/// Desktop shell: session sidebar beside the live console.
///
/// Deliberately not phone-style push navigation. On a desktop the whole point
/// is seeing the session list and the transcript at once, and switching without
/// a screen transition — [Workspace] caches consoles so a switch is a rebuild,
/// not a round trip.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    required this.workspace,
    this.peers = MemoryPeers.none,
    this.onReconnectWithAdmin,
    this.onSwitchHermesProfile,
    this.hermesProfile = 'default',
    this.onAddAgent,
    this.mobileAgentChips,
    super.key,
  });
  final Workspace workspace;

  /// Opens the connect flow to add another backend — the profile row's
  /// 「＋ 连接新后端」. Provided by the agent shell; null when this screen
  /// is not hosted inside one.
  final VoidCallback? onAddAgent;

  /// Already-open tabs the memory bridge can ask without a handshake.
  final MemoryPeers peers;

  /// Reopens this tab asking the gateway for operator.admin. Provided by the
  /// shell for OpenClaw tabs; null elsewhere.
  final Future<bool> Function()? onReconnectWithAdmin;

  /// Opens the profile switcher for an already-connected Hermes backend.
  final Future<void> Function()? onSwitchHermesProfile;

  /// The profile currently used by this Hermes connection.
  final String hermesProfile;

  /// The agent-chip strip, passed down to the compact shell on a phone so it
  /// renders *below* the session top bar (the design's order). Null on
  /// desktop, where the strip lives in the agent shell above the workbench.
  final Widget? mobileAgentChips;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

/// Below this width the master-detail split stops being usable and the shell
/// switches to one pane at a time. Roughly an iPad in portrait: every iPhone
/// is under it in both orientations, every Mac window worth using is over it.
const double _compactWidth = 720;

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _filter = '';

  Workspace get _ws => widget.workspace;

  /// Mirrors `_ws.activeId`, so the transcript pane rebuilds only when the
  /// selected session actually changes — not on every unread flag flip from a
  /// background session.
  String? _activeId;
  bool _arrived = false;

  /// Whether the session rail is folded away.
  ///
  /// Desktop only — a phone has no rail to fold, it has a drawer.
  bool _railCollapsed = false;

  /// The user has explicitly folded or unfolded the rail.
  ///
  /// Until they touch it, the rail follows the design's tablet behaviour:
  /// below [railCollapseWidth] the session rail starts folded to an icon
  /// strip, so a narrow window does not leave the transcript 110 px wide
  /// (which is exactly the width the console header overflowed at).
  bool _railTouched = false;

  /// The design's tablet breakpoint: ≤1100 侧栏收纳为图标 rail.
  static const railCollapseWidth = 1100.0;

  /// Which left-nav section is active. Sessions is the default — the list is
  /// the app's home; the others float the right panel rail or an overlay.
  _NavSection _nav = _NavSection.sessions;

  /// Whether the right panel rail is open, and which panel it shows.
  bool _panelOpen = false;
  RailPanel? _panel;

  /// The `…` menu / profile row targets: the backend this workspace is on,
  /// plus the saved-server list it came from, for the profile switcher.
  bool get _showRail => _panelOpen;

  void _selectNav(_NavSection section) {
    setState(() {
      _nav = section;
      // Panels floats the rail open; sessions folds it away. The other
      // sections keep the rail as it was.
      if (section == _NavSection.panels) {
        _panelOpen = true;
        _panel ??= RailPanel.agents;
      } else if (section == _NavSection.sessions) {
        _panelOpen = false;
      }
    });
  }

  void _selectPanel(RailPanel panel) {
    setState(() {
      _panel = panel;
      _panelOpen = true;
    });
  }

  /// Folds / unfolds the session rail, from whichever state it is actually in.
  ///
  /// The first tap also opts out of the auto-fold below the tablet
  /// breakpoint: once the user has chosen, their choice is the state.
  void _toggleRail(bool currentlyCollapsed) {
    setState(() {
      _railTouched = true;
      _railCollapsed = !currentlyCollapsed;
    });
  }

  @override
  void initState() {
    super.initState();
    _activeId = _ws.activeId;
    _arrived = _ws.arrived;
    _ws.addListener(_onWorkspaceChanged);
    if (startupPresets.openSessionId.isNotEmpty) {
      _ws.refreshSessions();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openSession(
          startupPresets.openSessionId,
        ).then((_) => _sayPreset()),
      );
    } else {
      // Refreshes the list *and* opens the top of it.
      _ws.openMostRecent();
    }
  }

  /// Whether to advertise keyboard shortcuts. A phone has no ⌘ key, and
  /// printing one in a hint is instructions for a device the user is not
  /// holding.
  bool get _hasKeyboard =>
      Theme.of(context).platform == TargetPlatform.macOS ||
      MediaQuery.sizeOf(context).width >= _compactWidth;

  /// Opens settings as the design's `settings-overlay` — the shared shell
  /// both the sidebar and the macOS tray use.
  Future<void> _openSettings() => showSettingsOverlay(context, _ws);

  /// Creates a session. The shell shows it: on a phone the conversation is
  /// the screen, so there is nothing to navigate to.
  Future<void> _newSession() => _ws.createSession();

  Future<void> _openSession(String id) => _ws.open(id);

  /// ⌘E — focus the session search (desktop rail). On a phone there is no
  /// rail search field, so the shortcut just lands on the session list.
  void _focusSessionSearch() {
    _selectNav(_NavSection.sessions);
    if (mounted) _searchFocus.requestFocus();
  }

  /// ⌘↑ / ⌘↓ — step to the previous / next session in the list, wrapping.
  void _stepSession(int delta) {
    final list = _ws.sessions;
    if (list.isEmpty) return;
    final current = _ws.activeId;
    final i = current == null ? 0 : list.indexWhere((s) => s.id == current);
    final index = (i + delta) % list.length;
    final target = index < 0 ? list.length - 1 : index;
    unawaited(_ws.open(list[target].id));
  }

  /// Sends the preset message, if there is one.
  ///
  /// Through the same [Workspace.send] the composer calls, because the point
  /// is to exercise the app's own path rather than a shortcut around it.
  Future<void> _sayPreset() async {
    final id = _ws.activeId;
    if (startupPresets.automaticPrompt.isEmpty || id == null) return;
    await _ws.send(id, startupPresets.automaticPrompt);
  }

  void _onWorkspaceChanged() {
    // `arrived` matters as much as the id: on a server with no sessions at all
    // it flips without the id ever changing, and the detail pane would sit on
    // the arriving placeholder for good.
    if (_ws.activeId == _activeId && _ws.arrived == _arrived) return;
    setState(() {
      _activeId = _ws.activeId;
      _arrived = _ws.arrived;
    });
  }

  @override
  void dispose() {
    _ws.removeListener(_onWorkspaceChanged);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        // ⌘N new session · ⌘R gentle reconnect · ⌘⇧R refresh the list ·
        // ⌘J jobs · ⌘P projects · ⌘E focus session search ·
        // ⌘↑ / ⌘↓ previous / next session · ⌘1–⌘5 nav ·
        // ⌘⇧T toolsets · ⌘⇧P panels · ⌘⇧S settings · ⌘K palette (in console).
        SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            _NewSessionIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, meta: true):
            _ReconnectIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, meta: true, shift: true):
            _RefreshIntent(),
        SingleActivator(LogicalKeyboardKey.keyE, meta: true):
            _FocusSearchIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
            _PreviousSessionIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
            _NextSessionIntent(),
        SingleActivator(LogicalKeyboardKey.digit1, meta: true): _NavIntent(
          _NavSection.capabilities,
        ),
        SingleActivator(LogicalKeyboardKey.digit2, meta: true): _NavIntent(
          _NavSection.messaging,
        ),
        SingleActivator(LogicalKeyboardKey.digit3, meta: true): _NavIntent(
          _NavSection.artifacts,
        ),
        SingleActivator(LogicalKeyboardKey.digit4, meta: true): _NavIntent(
          _NavSection.panels,
        ),
        SingleActivator(LogicalKeyboardKey.digit5, meta: true): _NavIntent(
          _NavSection.settings,
        ),
        SingleActivator(LogicalKeyboardKey.keyT, meta: true, shift: true):
            _OpenToolsetsIntent(),
        SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true):
            _OpenPanelsIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
            _OpenSettingsIntent(),
        SingleActivator(LogicalKeyboardKey.keyJ, meta: true): _JobsIntent(),
        SingleActivator(LogicalKeyboardKey.keyP, meta: true): _ProjectsIntent(),
      },
      child: Actions(
        actions: {
          _NewSessionIntent: CallbackAction<_NewSessionIntent>(
            onInvoke: (_) => _newSession(),
          ),
          _ReconnectIntent: CallbackAction<_ReconnectIntent>(
            onInvoke: (_) => _ws.reconnect(),
          ),
          _RefreshIntent: CallbackAction<_RefreshIntent>(
            onInvoke: (_) => _ws.refreshSessions(),
          ),
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) => _focusSessionSearch(),
          ),
          _PreviousSessionIntent: CallbackAction<_PreviousSessionIntent>(
            onInvoke: (_) => _stepSession(-1),
          ),
          _NextSessionIntent: CallbackAction<_NextSessionIntent>(
            onInvoke: (_) => _stepSession(1),
          ),
          _NavIntent: CallbackAction<_NavIntent>(
            onInvoke: (intent) => _onNavTap(intent.section),
          ),
          _OpenToolsetsIntent: CallbackAction<_OpenToolsetsIntent>(
            onInvoke: (_) => _openCapabilities(),
          ),
          _OpenPanelsIntent: CallbackAction<_OpenPanelsIntent>(
            onInvoke: (_) => _openPanels(),
          ),
          _OpenSettingsIntent: CallbackAction<_OpenSettingsIntent>(
            onInvoke: (_) => _openSettings(),
          ),
          // The shortcut is gated too. A key that opens a panel the backend
          // cannot fill is the same broken promise as a button that does.
          _JobsIntent: CallbackAction<_JobsIntent>(
            onInvoke: (_) => _ws.supports(Capability.cron) ? _showJobs() : null,
          ),
          _ProjectsIntent: CallbackAction<_ProjectsIntent>(
            onInvoke: (_) =>
                _ws.supports(Capability.projects) ? _showProjects() : null,
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            // Scoped rebuilds. A blanket setState on every workspace notify
            // rebuilt the sidebar *and* the transcript pane on each unread
            // flag flip during streaming; the transcript in particular has no
            // reason to rebuild because another session got a token.
            // The status bar and the home indicator are not ours to draw
            // under. Without this the iOS clock sits on top of the filter
            // field and the toolbar icons overlap the battery indicator —
            // which is exactly how it looked on the first simulator run.
            body: LayoutBuilder(
              builder: (context, constraints) {
                // A phone cannot show a session list and a transcript at
                // once — 300 px of sidebar leaves 90 px of conversation on
                // an iPhone. Below this width the list becomes the screen
                // and a session pushes over it; above it, both at once,
                // which is the whole point on a desktop or an iPad.
                if (constraints.maxWidth < _compactWidth) {
                  // The conversation is the screen; sessions live
                  // behind the app bar. Making the list the screen and
                  // pushing each conversation on top of it put the
                  // thing people came for one tap away and the thing
                  // they rarely need permanently in front.
                  return _CompactShell(
                    workspace: _ws,
                    onNewSession: _newSession,
                    onOpenSettings: _openSettings,
                    peers: widget.peers,
                    onReconnectWithAdmin: widget.onReconnectWithAdmin,
                    agentChips: widget.mobileAgentChips,
                  );
                }
                final railCollapsed =
                    _railCollapsed ||
                    (!_railTouched &&
                        constraints.maxWidth <= railCollapseWidth);
                return SafeArea(
                  child: Column(
                    children: [
                      // The connection notice floats over the workbench instead
                      // of taking a row: a reconnect that will resolve in two
                      // seconds should not shove the transcript down.
                      Expanded(
                        child: Stack(
                          children: [
                            // Below the tablet breakpoint the session rail
                            // starts folded, like the design's icon rail — a
                            // 1100-point window does not have 300 points to spare
                            // for a list the drawer can carry.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // The rail is glass and the transcript beside it
                                // is opaque — the shape of the whole design in one
                                // line: chrome floats, content does not.
                                //
                                // 折叠是宽度动画而非位移，内容同时淡出. Sliding it
                                // out would leave the transcript's left edge
                                // stationary while a panel passes over it; taking
                                // the width away hands that space to the
                                // conversation as it goes, which is the point of
                                // collapsing at all.
                                //
                                // The folded state is the design's icon rail —
                                // 48 pt of navigation icons, not nothing: the
                                // person who folded the list still needs
                                // Capabilities, Panels and Settings one tap away.
                                AnimatedContainer(
                                  duration: Motion.emphasized,
                                  curve: Motion.emphasizedCurve,
                                  width: railCollapsed ? 48 : 300,
                                  child: SizedBox.expand(
                                    child: GlassPanel(
                                      level: Glass.regular,
                                      // The design's `.sidebar` is its own rounded
                                      // sheet (r-lg = 16 pt), separated from the
                                      // console by the shell's gap rather than a
                                      // divider.
                                      radius: Radii.mediumAll,
                                      child: railCollapsed
                                          ? _IconRail(
                                              selected: _nav,
                                              onTap: _onNavTap,
                                              onExpand: () => _toggleRail(true),
                                            )
                                          : AnimatedOpacity(
                                              duration: Motion.emphasized,
                                              curve: Motion.emphasizedCurve,
                                              opacity: railCollapsed ? 0 : 1,
                                              // Clipped: mid-collapse the rail is
                                              // narrower than its contents, and
                                              // without this the rows spill across
                                              // the transcript.
                                              child: ClipRect(
                                                child: SizedBox(
                                                  width: 300,
                                                  height: double.infinity,
                                                  child: ListenableBuilder(
                                                    listenable: _ws,
                                                    builder: (context, _) =>
                                                        _sidebar(),
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                // The design's `shell-body` gap: sidebar and
                                // console are separate rounded sheets, not one
                                // surface with a hairline between them.
                                const SizedBox(width: 14),
                                // Deliberately NOT wrapped in a ListenableBuilder on the
                                // workspace: ConsoleView subscribes to its own console,
                                // so the only thing this level cares about is which
                                // console is selected. _onWorkspaceChanged rebuilds on
                                // that alone.
                                // The detail pane clears the title bar too — the
                                // window has none, so its first row would
                                // otherwise start at the very top of the screen.
                                // The right panel rail — the design's floating
                                // right column, default collapsed. Open it shows
                                // a glass column hosting the same panels that
                                // otherwise open as dialogs; collapsed it takes no
                                // width at all, so a two-pane desktop stays two
                                // panes until the person asks for the third.
                                if (_showRail) ...[
                                  const SizedBox(width: 14),
                                  SizedBox(
                                    width: 320,
                                    child: PanelRail(
                                      workspace: _ws,
                                      peers: widget.peers,
                                      open: true,
                                      panel: _panel,
                                      onClose: () => setState(() {
                                        _panelOpen = false;
                                        _nav = _NavSection.sessions;
                                      }),
                                      onSelect: _selectPanel,
                                    ),
                                  ),
                                ],
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      top: _titleBarInset,
                                    ),
                                    // The design's `.center` console sheet: its
                                    // own rounded card (r-lg) with a hairline
                                    // border, separate from the sidebar.
                                    child: Container(
                                      decoration: BoxDecoration(
                                        // The design's `.center` card radius is
                                        // r-lg = 16 pt.
                                        borderRadius: Radii.mediumAll,
                                        border: Border.all(
                                          color: context.ink.hairline,
                                        ),
                                        color:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Palette.voidBlack.withValues(
                                                alpha: .45,
                                              )
                                            : Colors.white.withValues(
                                                alpha: .55,
                                              ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Stack(
                                        children: [
                                          Positioned.fill(child: _detail()),
                                          // The only way back when the rail is
                                          // folded lives *inside* the icon rail;
                                          // when expanded, the fold control
                                          // floats over the console instead.
                                          if (!railCollapsed)
                                            Positioned(
                                              left: 4,
                                              top: 4,
                                              child: _RailToggle(
                                                collapsed: false,
                                                onTap: () => _toggleRail(false),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // 断链提示：悬浮在中间，不占布局空间。
                            Positioned(
                              top: 12,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: _ConnectionBanner(
                                  workspace: _ws,
                                  onBackToConnect: () =>
                                      Navigator.of(context).maybePop(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Room for the traffic lights.
  ///
  /// The traffic lights sit in the tab strip, not over the workbench: the
  /// shell keeps the strip full-width above both panes, so nothing here needs
  /// to make room for them. (The sidebar's brand and the console header both
  /// start at the top of their cards, which is what keeps them aligned.)
  double get _titleBarInset => 0;

  Widget _sidebar() {
    // The session list fills the space above the profile, and the profile is
    // pinned to the very bottom of the rail — it never floats mid-air.
    return Stack(
      fit: StackFit.expand,
      children: [
        // Forces the stack to occupy the full rail, so the pinned profile
        // really sits at the very bottom.
        const SizedBox.expand(),
        Column(
          children: [
            // The fixed chrome (nav, search, buttons) scrolls when the
            // sidebar is short — a phone in landscape — so it never
            // overflows; the session list below keeps the remaining space.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: _titleBarInset),
                    _sideNav(),
                  ],
                ),
              ),
            ),
            // Sessions live in the sidebar directly — no click needed.
            _sessionHead(),
            _sessionSearch(),
            Expanded(child: _sessionList()),
          ],
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _profileSwitcher()),
      ],
    );
  }

  List<AgentSession> get _visible {
    if (_filter.isEmpty) return _ws.sessions;
    final q = _filter.toLowerCase();
    return _ws.sessions
        .where(
          (s) =>
              s.label.toLowerCase().contains(q) ||
              s.id.toLowerCase().contains(q) ||
              s.source.toLowerCase().contains(q),
        )
        .toList();
  }

  /// The design's `side-head`: 会话, with the ＋ new-session control on the
  /// right — not a brass button spending the screen's one primary accent.
  Widget _sessionHead() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 4),
      child: Row(
        children: [
          Text(
            (l10n?.sessions ?? 'Sessions').toUpperCase(),
            style: mono(context, size: 10, opacity: InkLevel.faint),
          ),
          const Spacer(),
          Tooltip(
            message: l10n?.newSession ?? 'New session',
            child: Pressable(
              onTap: _newSession,
              semanticLabel: l10n?.newSession ?? 'New session',
              child: SizedBox(
                width: 30,
                height: 30,
                child: Icon(
                  Icons.add_rounded,
                  size: 17,
                  color: context.ink.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The design's `.session-search`: a small bordered field, not a glass
  /// sheet.
  Widget _sessionSearch() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: Radii.mediumAll,
          border: Border.all(color: context.ink.hairline),
          color: context.ink.base.withValues(alpha: .06),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 14, color: context.ink.faint),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: l10n?.searchSessions ?? 'Search sessions',
                  hintStyle: TextStyle(color: context.ink.tertiary),
                  isDense: true,
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _filter = v.trim()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionList() {
    final l10n = AppLocalizations.of(context);
    final sessions = _visible;
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          _ws.loadingSessions ? '' : (l10n?.noSessions ?? 'No sessions'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, i) {
        final s = sessions[i];
        return SessionRow(
          session: s,
          selected: s.id == _ws.activeId,
          unread: _ws.unread.contains(s.id),
          live: _ws.consoleFor(s.id)?.streaming ?? false,
          model: _ws.consoleFor(s.id)?.model ?? '',
          onTap: () => _openSession(s.id),
        );
      },
    );
  }

  /// The left-nav group — the design's `side-nav`. Sessions is the home;
  /// Capabilities, Messaging, Artifacts and Kanban are destinations for the
  /// right rail or an overlay; Panels floats the rail; Settings opens the
  /// settings overlay.
  Widget _sideNav() {
    final l10n = AppLocalizations.of(context);
    final items = <(_NavSection, IconData, String)>[
      (
        _NavSection.capabilities,
        Icons.widgets_outlined,
        l10n?.toolsetsSkillsPlugins ?? 'Capabilities',
      ),
      (
        _NavSection.messaging,
        Icons.forum_outlined,
        l10n?.messaging ?? 'Messaging',
      ),
      (
        _NavSection.artifacts,
        Icons.inventory_2_outlined,
        l10n?.artifacts ?? 'Artifacts',
      ),
      (_NavSection.panels, Icons.grid_view_rounded, l10n?.panels ?? 'Panels'),
      (
        _NavSection.settings,
        Icons.settings_outlined,
        l10n?.settings ?? 'Settings',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (section, icon, label) in items) ...[
            _SideNavItem(
              icon: icon,
              label: label,
              onTap: () => _onNavTap(section),
              selected: _nav == section,
            ),
            // The design's divider: Panels and Settings sit below it, a
            // second tier of chrome.
            if (section == _NavSection.artifacts)
              Divider(height: 13, color: context.ink.hairline),
          ],
        ],
      ),
    );
  }

  /// What tapping a left-nav entry does, from either the full sidebar or the
  /// folded icon rail.
  void _onNavTap(_NavSection section) {
    // Highlight the tapped item, then open its destination. All remaining
    // items are popups, so the selection is the last-opened one.
    setState(() => _nav = section);
    switch (section) {
      case _NavSection.capabilities:
        _openCapabilities();
      case _NavSection.settings:
        _openSettings();
      case _NavSection.messaging:
      case _NavSection.artifacts:
        _openExampleWork(section);
      case _NavSection.panels:
        _openPanels();
      default:
        _selectNav(section);
    }
  }

  /// The profile switcher — the bottom row of the sidebar.
  ///
  /// Shows the backend this workspace is connected to, with a live status
  /// dot, and leads to Settings where profiles are managed. The design's
  /// Home/Work/VPS examples are represented by the actual saved servers this
  /// client holds; there is no invented profile data.
  Widget _profileSwitcher() {
    final theme = Theme.of(context);
    final state = _ws.connection;
    final live = state.isConnected;
    final l10n = AppLocalizations.of(context);
    final name = _ws.backend.displayName;
    // The design's badge is the initial; the address under the name is the
    // server this backend is on, machine text.
    final badge = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    // Null on a backend with no Hermes gateway (OpenClaw): the row then just
    // carries the backend name and the live status, and the sidebar renders
    // instead of throwing on `gateway`.
    final address = _ws.gatewayAddress;
    final canSwitchProfile =
        _ws.backend.id == 'hermes' && widget.onSwitchHermesProfile != null;
    final status = state.isSettling
        ? 'Reconnecting…'
        : live
        ? (l10n?.connected ?? 'Connected')
        : (l10n?.disconnected ?? 'Offline');
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The design's profile row: badge · name + address · status chip.
          // Tapping it opens the sessions list directly.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openSettings,
              borderRadius: Radii.mediumAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: Radii.smallAll,
                        color: context.ink.base.withValues(alpha: .10),
                        border: Border.all(color: context.ink.hairline),
                      ),
                      child: Text(badge, style: mono(context, size: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 2),
                          if (address != null)
                            Text(
                              _ws.backend.id == 'hermes'
                                  ? '$address · ${widget.hermesProfile}'
                                  : address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: mono(
                                context,
                                size: 10,
                                opacity: InkLevel.faint,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (canSwitchProfile)
                      IconButton(
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        tooltip: 'Switch Hermes profile',
                        onPressed: widget.onSwitchHermesProfile,
                        visualDensity: VisualDensity.compact,
                      ),
                    const SizedBox(width: 8),
                    // Status chip — 已连接 / 未连接, not a bare dot.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: Radii.pillAll,
                        border: Border.all(color: context.ink.hairline),
                        color: (live ? Palette.jade : Palette.coral).withValues(
                          alpha: .14,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusDot(
                            color: live ? Palette.jade : Palette.coral,
                            size: 6,
                          ),
                          const SizedBox(width: 4),
                          Text(status, style: mono(context, size: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The design's 「＋ 连接新后端」— only where a shell can host the
          // result (the tab strip's Connect another agent already exists).
          if (widget.onAddAgent != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Pressable(
                onTap: widget.onAddAgent!,
                semanticLabel: l10n?.addAnotherServer ?? 'Add another server',
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: Radii.mediumAll,
                    border: Border.all(color: context.ink.hairline),
                  ),
                  child: Text(
                    '＋ ${l10n?.addAnotherServer ?? 'Connect another backend'}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.ink.secondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Messaging / Artifacts — the design's Hermes work views.
  ///
  /// These have no real data source on either gateway, so they open an
  /// explicitly labelled 示例 (example) surface rather than a dead control
  /// or an invented one.
  Future<void> _openExampleWork(_NavSection section) => showDialog<void>(
    context: context,
    builder: (context) => Panel(
      title: Text(switch (section) {
        _NavSection.messaging => 'Messaging',
        _NavSection.artifacts => 'Artifacts',
        _NavSection.sessions ||
        _NavSection.capabilities ||
        _NavSection.panels ||
        _NavSection.settings => 'Example',
      }),
      content: SizedBox(
        width: 420,
        child: Text(
          '${switch (section) {
            _NavSection.messaging => 'Bridged channels (OpenClaw WhatsApp/Telegram) will appear '
                'here once a channel is connected.',
            _NavSection.artifacts => 'Files the agent produced will appear here once artifacts are '
                'surfaced by the gateway.',
            _NavSection.sessions || _NavSection.capabilities || _NavSection.panels || _NavSection.settings => 'Example view.',
          }}\n\n示例 — this view is a design placeholder; there is no data '
          'source for it yet.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.ink.secondary),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  /// The Capabilities destination — the design's Capabilities Hub overlay.
  Future<void> _openCapabilities() => showDialog<void>(
    context: context,
    builder: (_) => CapabilitiesHub(
      workspace: _ws,
      sessionId: _ws.active?.persistedId ?? '',
    ),
  );

  /// The eight panels as Settings' master–detail card: a left-hand nav of the
  /// panels, the open one beside it, switching in place — no picker hop.
  /// On a phone the same [PanelsOverlay] is a bottom sheet, and a tap opens
  /// that panel as its own sheet.
  Future<void> _openPanels() => showPanel<void>(
    context,
    (_) => PanelsOverlay(
      workspace: _ws,
      peers: widget.peers,
      onOpenPanel: _openPanel,
    ),
  );

  /// Opens one of the eight panels as an overlay.
  Future<void> _openPanel(RailPanel panel) {
    // A backend that cannot serve the panel must never build it — the same
    // gate the rail and drawer apply to the list they offer.
    final need = panelCapability(panel);
    if (need != null && !_ws.supports(need)) return Future<void>.value();
    return showPanel<void>(
      context,
      (_) => switch (panel) {
        RailPanel.agents => AgentsPanel(
          gateway: _ws.gateway,
          liveSessionId: _ws.active?.liveId ?? '',
        ),
        RailPanel.fleet => FleetPanel(workspace: _ws, peers: widget.peers),
        RailPanel.memory => MemoryPanel(workspace: _ws, peers: widget.peers),
        RailPanel.shared => SharedMemoryPanel(
          workspace: _ws,
          peers: widget.peers,
        ),
        RailPanel.skills => SkillsPanel(workspace: _ws, peers: widget.peers),
        RailPanel.jobs => JobsPanel(workspace: _ws),
        RailPanel.processes => ProcessesPanel(
          workspace: _ws,
          sessionId: _ws.active?.persistedId ?? '',
        ),
        RailPanel.projects => ProjectsPanel(
          gateway: _ws.gateway,
          onOpenSession: _ws.open,
        ),
      },
    );
  }

  Widget _detail() {
    final console = _ws.active;
    if (console == null && !_ws.arrived) return const _Arriving();
    if (console == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select a session',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _hasKeyboard ? '⌘N for a new one' : 'Tap + to start one',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    // Keyed so switching sessions rebuilds against the right console rather
    // than reusing the previous one's element state, and faded in so the
    // switch is not a hard cut.
    //
    // Deliberately *not* an AnimatedSwitcher. That keeps the outgoing
    // transcript mounted for the length of the transition, and switching away
    // and back inside that window puts two views of the same session on screen
    // at once — which throws "Duplicate keys found" immediately, and would
    // otherwise have both of them attaching the console's one scroll
    // controller. A softer switch is not worth a crash class; this fades the
    // arriving transcript in and drops the old one at once.
    return SessionFade(
      key: ValueKey(console.persistedId),
      child: ConsoleView(
        key: ValueKey('view-${console.persistedId}'),
        workspace: _ws,
        console: console,
        peers: widget.peers,
        onReconnectWithAdmin: widget.onReconnectWithAdmin,
      ),
    );
  }
}

/// A navigation row that stays valid while the drawer animates from zero.
///
/// ListTile has an intrinsic minimum width; during the first frames of a
/// drawer animation that produces layout exceptions instead of a simple
/// clipped row.
class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected ? Palette.brass : context.ink.tertiary;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 48) {
          return const SizedBox(height: 34);
        }
        return Material(
          borderRadius: Radii.smallAll,
          clipBehavior: Clip.antiAlias,
          color: selected
              ? context.ink.base.withValues(alpha: .10)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: foreground),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

extension on _WorkspaceScreenState {
  Future<void> _showProjects() => showDialog<void>(
    context: context,
    builder: (_) =>
        ProjectsPanel(gateway: _ws.gateway, onOpenSession: _ws.open),
  );

  Future<void> _showJobs() => showDialog<void>(
    context: context,
    builder: (_) => JobsPanel(workspace: _ws),
  );
}

class _RailToggle extends StatelessWidget {
  const _RailToggle({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final msg = collapsed
        ? (l10n?.showSessions ?? 'Show sessions')
        : (l10n?.hideSessions ?? 'Hide sessions');
    return Tooltip(
      message: msg,
      child: Pressable(
        onTap: onTap,
        semanticLabel: msg,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: AnimatedRotation(
              turns: collapsed ? .5 : 0,
              duration: Motion.emphasized,
              curve: Motion.emphasizedCurve,
              child: Icon(
                Icons.keyboard_double_arrow_left_rounded,
                size: 17,
                color: context.ink.faint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The folded session rail — the design's icon rail at ≤1100.
///
/// 48 pt of navigation icons with no list: Capabilities, Messaging,
/// Artifacts, Kanban, Panels and Settings stay one tap away, and the
/// expand control at the bottom brings the session list back.
class _IconRail extends StatelessWidget {
  const _IconRail({
    required this.selected,
    required this.onTap,
    required this.onExpand,
  });

  final _NavSection selected;
  final ValueChanged<_NavSection> onTap;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = <(_NavSection, IconData, String)>[
      (
        _NavSection.capabilities,
        Icons.widgets_outlined,
        l10n?.toolsetsSkillsPlugins ?? 'Capabilities',
      ),
      (
        _NavSection.messaging,
        Icons.forum_outlined,
        l10n?.messaging ?? 'Messaging',
      ),
      (
        _NavSection.artifacts,
        Icons.inventory_2_outlined,
        l10n?.artifacts ?? 'Artifacts',
      ),
      (_NavSection.panels, Icons.grid_view_rounded, l10n?.panels ?? 'Panels'),
      (
        _NavSection.settings,
        Icons.settings_outlined,
        l10n?.settings ?? 'Settings',
      ),
    ];
    return Column(
      children: [
        for (final (section, icon, label) in items)
          Tooltip(
            message: label,
            child: Pressable(
              onTap: () => onTap(section),
              semanticLabel: label,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Icon(
                    icon,
                    size: 18,
                    color: selected == section
                        ? Palette.brass
                        : context.ink.tertiary,
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Tooltip(
          message: l10n?.showSessions ?? 'Show sessions',
          child: Pressable(
            onTap: onExpand,
            semanticLabel: l10n?.showSessions ?? 'Show sessions',
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: RotatedBox(
                  // 展开：箭头指向右侧 — the same gesture as the floating
                  // fold control, mirrored.
                  quarterTurns: 2,
                  child: Icon(
                    Icons.keyboard_double_arrow_left_rounded,
                    size: 17,
                    color: context.ink.faint,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReconnectIntent extends Intent {
  const _ReconnectIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _PreviousSessionIntent extends Intent {
  const _PreviousSessionIntent();
}

class _NextSessionIntent extends Intent {
  const _NextSessionIntent();
}

class _NavIntent extends Intent {
  const _NavIntent(this.section);
  final _NavSection section;
}

class _OpenToolsetsIntent extends Intent {
  const _OpenToolsetsIntent();
}

class _OpenPanelsIntent extends Intent {
  const _OpenPanelsIntent();
}

class _OpenSettingsIntent extends Intent {
  const _OpenSettingsIntent();
}

class _JobsIntent extends Intent {
  const _JobsIntent();
}

class _ProjectsIntent extends Intent {
  const _ProjectsIntent();
}

class _NewSessionIntent extends Intent {
  const _NewSessionIntent();
}

class _RefreshIntent extends Intent {
  const _RefreshIntent();
}

/// Shown between connecting and the last conversation appearing.
///
/// Deliberately says nothing and offers nothing. Two round trips is not long
/// enough to be worth explaining, and anything actionable here — a button, a
/// suggestion — would be aimed at a user whose session is half a second away.
class _Arriving extends StatelessWidget {
  const _Arriving();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

/// The phone shell: conversation in front, sessions behind the app bar.
class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.workspace,
    required this.onNewSession,
    required this.onOpenSettings,
    this.peers = MemoryPeers.none,
    this.onReconnectWithAdmin,
    this.agentChips,
  });

  final Workspace workspace;
  final VoidCallback onNewSession;
  final VoidCallback onOpenSettings;

  /// Already-open tabs the memory bridge can ask without a handshake.
  final MemoryPeers peers;

  /// Reopens the tab asking for operator.admin. OpenClaw only.
  final Future<bool> Function()? onReconnectWithAdmin;

  /// The design's chipstrip, rendered at the top of the screen on a phone.
  final Widget? agentChips;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) {
        final console = workspace.active;
        return Scaffold(
          // 遮罩透明度随位移线性变化 — and it has to be weighted per mode.
          // Material's default is black at 54%, which over a dark transcript
          // is barely noticeable and over a light one turns the conversation
          // to mud. The drawer is glass: you are supposed to still read what
          // is behind it.
          drawerScrimColor: Colors.black.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? .5 : .26,
          ),
          // No AppBar: ConsoleView draws the top row itself, so the drawer
          // button, the title and the session menu share one strip instead of
          // a navigation bar with a second band under it.
          drawer: SessionDrawer(
            workspace: workspace,
            peers: peers,
            onOpenSession: (id) {
              Navigator.of(context).pop();
              workspace.open(id);
            },
            onNewSession: () {
              Navigator.of(context).pop();
              onNewSession();
            },
            onOpenSettings: () {
              Navigator.of(context).pop();
              onOpenSettings();
            },
            onOpenSettingsGroup: (groupId) {
              Navigator.of(context).pop();
              showSettingsOverlay(context, workspace, initialGroup: groupId);
            },
            onOpenConnect: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ConnectScreen(autoReconnect: false),
                ),
              );
            },
            onOpenPanel: (panel) {
              Navigator.of(context).pop();
              _openRailPanel(context, panel);
            },
          ),
          // The design's `.bottomnav` is Android-only: on iOS the top bar
          // and drawer carry the same destinations, and the shell stays a
          // single edge-to-edge conversation surface.
          bottomNavigationBar: defaultTargetPlatform == TargetPlatform.android
              ? _BottomNav(
                  // 面板 opens the design's capabilities sheet: Skills / Tools /
                  // MCP / Browse Hub in one place.
                  onPanels: () => showPanel<void>(
                    context,
                    (_) => CapabilitiesHub(
                      workspace: workspace,
                      sessionId: workspace.active?.persistedId ?? '',
                    ),
                  ),
                  onConnect: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ConnectScreen(autoReconnect: false),
                    ),
                  ),
                  onSettings: onOpenSettings,
                )
              : null,
          body: Stack(
            children: [
              Positioned.fill(
                child: console == null && !workspace.arrived
                    ? const _Arriving()
                    : console == null
                    ? SafeArea(
                        child: Column(
                          children: [
                            ?agentChips,
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Builder(
                                builder: (context) => IconButton(
                                  tooltip: 'Sessions',
                                  icon: const Icon(Icons.menu_rounded),
                                  onPressed: Scaffold.of(context).openDrawer,
                                ),
                              ),
                            ),
                            const Spacer(),
                            _emptyState(context, onNewSession),
                            const Spacer(),
                          ],
                        ),
                      )
                    // Same fade as the desktop pane: picking a session from the
                    // drawer replaces the whole screen, and a hard cut there
                    // reads as the app restarting.
                    : SessionFade(
                        key: ValueKey(console.persistedId),
                        child: ConsoleView(
                          key: ValueKey('view-${console.persistedId}'),
                          workspace: workspace,
                          console: console,
                          compactChrome: true,
                          peers: peers,
                          onReconnectWithAdmin: onReconnectWithAdmin,
                          topBar: agentChips,
                          onOpenPanels: () => showPanel<void>(
                            context,
                            (_) => CapabilitiesHub(
                              workspace: workspace,
                              sessionId: workspace.active?.persistedId ?? '',
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: _ConnectionBanner(
                    workspace: workspace,
                    onBackToConnect: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _emptyState(BuildContext context, VoidCallback onNewSession) =>
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No session open',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onNewSession,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New session'),
            ),
          ],
        ),
      );
}

/// Connection trouble, floating over either shell width.
///
/// A reconnect that resolves in two seconds is not worth a full-width band,
/// and a phone loses neither the message nor the escape route by sharing the
/// desktop's pill.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.workspace,
    required this.onBackToConnect,
  });

  final Workspace workspace;
  final VoidCallback onBackToConnect;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) {
        final state = workspace.connection;
        if (state.isConnected) return const SizedBox.shrink();

        final reconnecting = state.isSettling;
        final color = switch (state.status) {
          AgentStatus.awaitingApproval => Palette.brass,
          _ when reconnecting => Palette.brass,
          _ => Palette.coral,
        };
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: Radii.pillAll,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .28),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusPill(
                label: switch (state.status) {
                  AgentStatus.reconnecting =>
                    'Reconnecting — attempt ${state.attempt}',
                  AgentStatus.awaitingApproval =>
                    state.detail.isEmpty
                        ? 'Waiting to be approved on the server'
                        : state.detail,
                  AgentStatus.fatal =>
                    'Disconnected — ${state.error ?? "connection lost"}',
                  _ => 'Not connected',
                },
                color: color,
                pulsing: reconnecting || state.needsApproval,
              ),
              if (state.status == AgentStatus.fatal) ...[
                const SizedBox(width: 8),
                GlassButton(
                  label: 'Back to connect',
                  onPressed: onBackToConnect,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

extension on _CompactShell {
  /// Opens one of the eight panels from the mobile drawer as a bottom sheet.
  Future<void> _openRailPanel(BuildContext context, RailPanel panel) {
    // Same gate as the drawer's own list: a panel a backend cannot serve is
    // not offered, and if it is somehow requested it is not built either.
    final need = panelCapability(panel);
    if (need != null && !workspace.supports(need)) {
      return Future<void>.value();
    }
    return showPanel<void>(
      context,
      (_) => switch (panel) {
        RailPanel.agents => AgentsPanel(
          gateway: workspace.gateway,
          liveSessionId: workspace.active?.liveId ?? '',
        ),
        RailPanel.fleet => FleetPanel(workspace: workspace, peers: peers),
        RailPanel.memory => MemoryPanel(workspace: workspace, peers: peers),
        RailPanel.shared => SharedMemoryPanel(
          workspace: workspace,
          peers: peers,
        ),
        RailPanel.skills => SkillsPanel(workspace: workspace, peers: peers),
        RailPanel.jobs => JobsPanel(workspace: workspace),
        RailPanel.processes => ProcessesPanel(
          workspace: workspace,
          sessionId: workspace.active?.persistedId ?? '',
        ),
        RailPanel.projects => ProjectsPanel(
          gateway: workspace.gateway,
          onOpenSession: workspace.open,
        ),
      },
    );
  }
}

/// The mobile bottom navigation — the design's `bottom-nav`: 会话 /
/// 面板 / 连接 / 设置 (Chat / Panels / Connect / Settings). Chat is the
/// conversation itself; Panels opens the Capabilities Hub as a sheet;
/// Connect and Settings open their full-screen destinations.
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.onPanels,
    required this.onConnect,
    required this.onSettings,
  });

  final VoidCallback onPanels;
  final VoidCallback onConnect;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassPanel(
      level: Glass.regular,
      radius: BorderRadius.zero,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: l10n?.chat ?? 'Chat',
                selected: true,
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.grid_view_rounded,
                label: l10n?.panels ?? 'Panels',
                onTap: onPanels,
              ),
              _NavItem(
                icon: Icons.wifi_tethering_rounded,
                label: l10n?.connect ?? 'Connect',
                onTap: onConnect,
              ),
              _NavItem(
                icon: Icons.settings_outlined,
                label: l10n?.settings ?? 'Settings',
                onTap: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? Palette.brass : context.ink.tertiary,
            ),
            const SizedBox(height: 2),
            // Scales down under a large text scale so the row never
            // overflows the nav height.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected ? context.ink.primary : context.ink.faint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Left-nav sections in the desktop sidebar.
enum _NavSection {
  sessions,
  capabilities,
  messaging,
  artifacts,
  panels,
  settings,
}
