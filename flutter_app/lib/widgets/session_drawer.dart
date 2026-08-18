import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:agent_core/agent_core.dart';

import '../agents_panel.dart';
import '../capabilities_hub.dart';
import '../connect_screen.dart';
import '../design/components.dart';
import '../design/glass.dart';
import '../design/press.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../fleet_panel.dart';
import '../haptics.dart';
import '../jobs_panel.dart';
import '../l10n/app_localizations.dart';
import '../memory_panel.dart';
import '../panel_rail.dart';
import '../processes_panel.dart';
import '../projects_panel.dart';
import '../settings/settings_pages.dart';
import '../settings_page.dart';
import '../shared_memory_panel.dart';
import '../skills_panel.dart';
import '../workspace.dart';
import 'session_row.dart';

/// Sessions, search and settings, behind the app bar.
class SessionDrawer extends StatefulWidget {
  const SessionDrawer({
    required this.workspace,
    required this.onOpenSession,
    required this.onNewSession,
    required this.onOpenSettings,
    required this.onOpenPanel,
    this.onOpenSettingsGroup,
    this.onOpenConnect,
    this.peers = MemoryPeers.none,
    super.key,
  });

  final Workspace workspace;
  final MemoryPeers peers;
  final void Function(String sessionId) onOpenSession;
  final VoidCallback onNewSession;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenConnect;

  /// Opens one of the eight panels as a bottom sheet.
  final ValueChanged<RailPanel> onOpenPanel;

  /// Opens a specific settings group.
  final ValueChanged<SettingsGroupId>? onOpenSettingsGroup;

  @override
  State<SessionDrawer> createState() => _SessionDrawerState();
}

/// The drawer's four segments: 会话 / 工具 / 共享 / 设置.
enum _DrawerTab { sessions, tools, shared, settings }

class _SessionDrawerState extends State<SessionDrawer> {
  final _search = TextEditingController();

  /// The drawer's four segments: 会话 / 工具 / 共享 / 设置.
  _DrawerTab _tab = _DrawerTab.sessions;
  RailPanel? _activePanel;
  SettingsGroupId? _activeSettingsGroup;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AgentSession> get _visible {
    final query = _search.text.trim().toLowerCase();
    final sessions = widget.workspace.sessions;
    if (query.isEmpty) return sessions;
    return sessions
        .where(
          (s) =>
              s.label.toLowerCase().contains(query) ||
              s.id.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final workspace = widget.workspace;

    final width = MediaQuery.sizeOf(context).width;
    final hasSubpage = _activePanel != null || _activeSettingsGroup != null;
    final subpageTitle = _activePanel != null
        ? panelItems.firstWhere((p) => p.$1 == _activePanel).$3
        : (_activeSettingsGroup?.localizedLabel(context) ?? '');

    return PopScope(
      canPop: !hasSubpage,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          _activePanel = null;
          _activeSettingsGroup = null;
        });
      },
      child: Drawer(
        width: width,
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
        child: GlassPanel(
          level: Glass.regular,
          radius: BorderRadius.zero,
          child: SafeArea(
            bottom: false,
            child: ListenableBuilder(
              listenable: workspace,
              builder: (context, _) {
                final bottomPadding = math.max(
                  16.0,
                  MediaQuery.paddingOf(context).bottom - 10,
                );
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                      child: SizedBox(
                        height: 36,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: hasSubpage
                              ? Row(
                                  key: const ValueKey('subpage_header'),
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        size: 19,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      alignment: Alignment.centerLeft,
                                      tooltip: l10n?.back ?? 'Back',
                                      onPressed: () {
                                        Haptics.tap();
                                        setState(() {
                                          _activePanel = null;
                                          _activeSettingsGroup = null;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        subpageTitle,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 22,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      alignment: Alignment.centerRight,
                                      tooltip: l10n?.close ?? 'Close',
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                  ],
                                )
                              : Row(
                                  key: const ValueKey('root_header'),
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 22,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      alignment: Alignment.centerLeft,
                                      tooltip: l10n?.close ?? 'Close',
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                    const Spacer(),
                                    Container(
                                      width: 28,
                                      height: 28,
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: .92,
                                        ),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color: context.ink.hairline,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Image.asset(
                                        'assets/images/logo.png',
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.medium,
                                        errorBuilder: (_, _, _) =>
                                            const SizedBox(
                                              width: 28,
                                              height: 28,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Caduceus',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'v0.1.0',
                                      style: mono(
                                        context,
                                        size: 10,
                                        opacity: InkLevel.faint,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin:
                                    child.key == const ValueKey('root_content')
                                    ? const Offset(-0.06, 0)
                                    : const Offset(0.06, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: hasSubpage
                            ? KeyedSubtree(
                                key: ValueKey(
                                  _activePanel?.name ??
                                      _activeSettingsGroup?.name ??
                                      'subpage',
                                ),
                                child: _activePanel != null
                                    ? _buildActivePanel(_activePanel!)
                                    : _buildActiveSettings(
                                        _activeSettingsGroup!,
                                      ),
                              )
                            : KeyedSubtree(
                                key: const ValueKey('root_content'),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        0,
                                        14,
                                        6,
                                      ),
                                      child: Segmented(
                                        labels: [
                                          l10n?.sessions ?? 'Sessions',
                                          Localizations.localeOf(
                                                    context,
                                                  ).languageCode ==
                                                  'zh'
                                              ? '工具'
                                              : 'Tools',
                                          Localizations.localeOf(
                                                    context,
                                                  ).languageCode ==
                                                  'zh'
                                              ? '共享'
                                              : 'Shared',
                                          l10n?.settings ?? 'Settings',
                                        ],
                                        index: _tab.index,
                                        onChanged: (i) => setState(
                                          () => _tab = _DrawerTab.values[i],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: switch (_tab) {
                                        _DrawerTab.sessions => _list(theme),
                                        _DrawerTab.tools => _tools(theme),
                                        _DrawerTab.shared => _shared(theme),
                                        _DrawerTab.settings => _settings(theme),
                                      },
                                    ),
                                    Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        14,
                                        6,
                                        14,
                                        bottomPadding,
                                      ),
                                      child: Pressable(
                                        onTap: () {
                                          Haptics.tap();
                                          if (widget.onOpenConnect != null) {
                                            widget.onOpenConnect!();
                                          } else {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const ConnectScreen(
                                                      autoReconnect: false,
                                                    ),
                                              ),
                                            );
                                          }
                                        },
                                        semanticLabel: 'Connect · Hermes',
                                        child: GlassPanel(
                                          level: Glass.thin,
                                          radius: Radii.mediumAll,
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              10,
                                              14,
                                              10,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 34,
                                                  height: 34,
                                                  decoration: BoxDecoration(
                                                    color: context.ink.base
                                                        .withValues(alpha: .08),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border.all(
                                                      color:
                                                          context.ink.hairline,
                                                    ),
                                                  ),
                                                  child: Center(
                                                    child: Icon(
                                                      Icons.dns_outlined,
                                                      size: 17,
                                                      color:
                                                          context.ink.primary,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        widget
                                                                .workspace
                                                                .backend
                                                                .displayName
                                                                .isNotEmpty
                                                            ? widget
                                                                  .workspace
                                                                  .backend
                                                                  .displayName
                                                            : 'Hermes Agent',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 13.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        widget
                                                                .workspace
                                                                .connection
                                                                .isConnected
                                                            ? (widget
                                                                      .workspace
                                                                      .connection
                                                                      .detail
                                                                      .isNotEmpty
                                                                  ? widget
                                                                        .workspace
                                                                        .connection
                                                                        .detail
                                                                  : (l10n?.connected ??
                                                                        'Connected'))
                                                            : (Localizations.localeOf(
                                                                        context,
                                                                      ).languageCode ==
                                                                      'zh'
                                                                  ? '未连接'
                                                                  : 'Offline'),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: mono(
                                                          context,
                                                          size: 11,
                                                          opacity:
                                                              InkLevel.faint,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                StatusDot(
                                                  color:
                                                      widget
                                                          .workspace
                                                          .connection
                                                          .isConnected
                                                      ? Palette.jade
                                                      : Palette.coral,
                                                  size: 7,
                                                ),
                                                const SizedBox(width: 6),
                                                Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 16,
                                                  color: context.ink.faint,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final sessions = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: GlassPanel(
            level: Glass.thin,
            radius: Radii.mediumAll,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 1, 8, 1),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: context.ink.faint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l10n?.searchSessions ?? 'Search sessions',
                        hintStyle: TextStyle(color: context.ink.faint),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_search.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      tooltip: 'Clear',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => setState(_search.clear),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Pressable(
            onTap: () {
              Haptics.tap();
              widget.onNewSession();
            },
            semanticLabel: l10n?.newSession ?? 'New session',
            child: GlassPanel(
              level: Glass.thin,
              radius: Radii.mediumAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: context.ink.secondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n?.newSession ?? 'New session',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: sessions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      widget.workspace.loadingSessions
                          ? ''
                          : _search.text.trim().isEmpty
                          ? (l10n?.noSessions ?? 'No sessions')
                          : 'No sessions match "${_search.text.trim()}"',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                )
              : StaggerScope(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    itemCount: sessions.length,
                    itemBuilder: (context, i) {
                      final session = sessions[i];
                      return Staggered(
                        index: i,
                        child: SessionRow(
                          session: session,
                          selected: session.id == widget.workspace.activeId,
                          unread: widget.workspace.unread.contains(session.id),
                          live:
                              widget.workspace
                                  .consoleFor(session.id)
                                  ?.streaming ??
                              false,
                          model:
                              widget.workspace.consoleFor(session.id)?.model ??
                              '',
                          onTap: () {
                            Haptics.select();
                            widget.onOpenSession(session.id);
                          },
                          onLongPress: () {
                            Haptics.tap();
                            _showSessionOptions(session);
                          },
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  void _showSessionOptions(AgentSession session) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GlassPanel(
            level: Glass.thick,
            radius: Radii.largeAll,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: sheetContext.ink.hairline),
                ListTile(
                  leading: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 20,
                  ),
                  title: const Text('Open session'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    widget.onOpenSession(session.id);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_rounded, size: 20),
                  title: const Text('Copy session ID'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Clipboard.setData(ClipboardData(text: session.id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Session ID copied to clipboard'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivePanel(RailPanel panel) {
    final ws = widget.workspace;
    return switch (panel) {
      RailPanel.agents => AgentsPanel(
        gateway: ws.gateway,
        liveSessionId: ws.active?.liveId ?? '',
        embedded: true,
      ),
      RailPanel.fleet => FleetPanel(
        workspace: ws,
        peers: widget.peers,
        embedded: true,
      ),
      RailPanel.memory => MemoryPanel(
        workspace: ws,
        peers: widget.peers,
        embedded: true,
      ),
      RailPanel.shared => SharedMemoryPanel(
        workspace: ws,
        peers: widget.peers,
        embedded: true,
      ),
      RailPanel.skills => SkillsPanel(
        workspace: ws,
        peers: widget.peers,
        embedded: true,
      ),
      RailPanel.jobs => JobsPanel(workspace: ws, embedded: true),
      RailPanel.processes => ProcessesPanel(
        workspace: ws,
        sessionId: ws.active?.persistedId ?? '',
        embedded: true,
      ),
      RailPanel.projects => ProjectsPanel(
        gateway: ws.gateway,
        onOpenSession: (id) {
          Navigator.of(context).pop();
          widget.onOpenSession(id);
        },
        embedded: true,
      ),
    };
  }

  Widget _buildActiveSettings(SettingsGroupId group) {
    return switch (group) {
      SettingsGroupId.model => ModelSettings(workspace: widget.workspace),
      SettingsGroupId.appearance => const AppearanceSettings(),
      SettingsGroupId.safety => ApprovalSettings(workspace: widget.workspace),
      SettingsGroupId.voice => const VoiceSettings(),
      SettingsGroupId.gateway => GatewaySettings(workspace: widget.workspace),
      SettingsGroupId.tools => SkillSettings(workspace: widget.workspace),
      SettingsGroupId.shortcuts => const ShortcutSettings(),
      SettingsGroupId.about => const AboutSettings(),
      _ => const SizedBox.shrink(),
    };
  }

  /// The capabilities hub (skills, tools, MCP), as the drawer's "工具" (Tools) tab.
  Widget _tools(ThemeData theme) {
    return CapabilitiesHub(
      workspace: widget.workspace,
      sessionId: widget.workspace.active?.persistedId ?? '',
      embedded: true,
    );
  }

  /// The eight panels, as the drawer's "共享" (Shared) tab. Styled with unified
  /// card material, typography and spacing matching Sessions.
  Widget _shared(ThemeData theme) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final items = panelItemsFor(widget.workspace);
    return StaggerScope(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final (panel, icon, label) = items[i];
          final (subtitle, tag) = switch (panel) {
            RailPanel.agents => (
              isZh ? '多智能体协同与委派' : 'Subagents & live delegates',
              'subagents',
            ),
            RailPanel.fleet => (
              isZh ? '节点网络与集群状态' : 'Connected peers & swarm',
              'mesh',
            ),
            RailPanel.memory => (
              isZh ? '长期记忆与用户画像' : 'Persistent context & recall',
              'context',
            ),
            RailPanel.shared => (
              isZh ? '跨 Agent 共享上下文' : 'Cross-agent shared memory',
              'sync',
            ),
            RailPanel.skills => (
              isZh ? '可用技能与工具库' : 'Installed tools & capabilities',
              'skills',
            ),
            RailPanel.jobs => (
              isZh ? '计划任务与 Cron 定时器' : 'Scheduled & cron tasks',
              'cron',
            ),
            RailPanel.processes => (
              isZh ? '后台运行进程与终端' : 'Background tasks & shells',
              'pty',
            ),
            RailPanel.projects => (
              isZh ? '工作区项目与文件树' : 'Workspaces & directories',
              'fs',
            ),
          };

          return Staggered(
            index: i,
            child: _DrawerMenuRow(
              icon: icon,
              title: label,
              subtitle: subtitle,
              trailingTag: tag,
              selected: _activePanel == panel,
              onTap: () {
                Haptics.select();
                setState(() => _activePanel = panel);
              },
            ),
          );
        },
      ),
    );
  }

  /// Settings, as the design's drawer settings segment. Styled with unified
  /// card material, typography and spacing matching Sessions.
  Widget _settings(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final rows = <(IconData, String, String, SettingsGroupId, String)>[
      (
        Icons.tune_rounded,
        l10n?.settingsItemModel ?? 'Model',
        isZh
            ? 'glm-5-2-260617 · 采样与上下文'
            : 'glm-5-2-260617 · Sampling & context',
        SettingsGroupId.model,
        'core',
      ),
      (
        Icons.verified_user_outlined,
        l10n?.approvals ?? 'Approvals',
        isZh ? '智能审批 · 密钥与无人值守' : 'Approval gates · API keys',
        SettingsGroupId.safety,
        'safety',
      ),
      (
        Icons.contrast_rounded,
        l10n?.appearance ?? 'Appearance',
        isZh ? '暗色 · 极光 · 字体与缩放' : 'Dark mode · Aurora · Typography',
        SettingsGroupId.appearance,
        'theme',
      ),
      (
        Icons.dns_outlined,
        l10n?.gateway ?? 'Gateway',
        isZh ? 'Hermes / OpenClaw 连接与配置' : 'Hermes / OpenClaw connection',
        SettingsGroupId.gateway,
        'live',
      ),
      (
        Icons.extension_outlined,
        l10n?.skills ?? 'Skills',
        isZh ? '技能与扩展工具配置' : 'Skills and tool integrations',
        SettingsGroupId.tools,
        'tools',
      ),
      (
        Icons.keyboard_outlined,
        l10n?.settingsItemShortcuts ?? 'Shortcuts',
        isZh ? '快捷键与全局操作' : 'Keyboard shortcuts & actions',
        SettingsGroupId.shortcuts,
        'keys',
      ),
      (
        Icons.info_outline_rounded,
        l10n?.settingsItemAbout ?? 'About',
        'Caduceus v0.1.0 · Google DeepMind',
        SettingsGroupId.about,
        'system',
      ),
    ];

    return StaggerScope(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final (icon, title, subtitle, groupId, tag) = rows[i];
          return Staggered(
            index: i,
            child: _DrawerMenuRow(
              icon: icon,
              title: title,
              subtitle: subtitle,
              trailingTag: tag,
              selected: _activeSettingsGroup == groupId,
              onTap: () {
                Haptics.select();
                setState(() => _activeSettingsGroup = groupId);
              },
            ),
          );
        },
      ),
    );
  }
}

/// A drawer menu item matching the exact typography, padding,
/// hover effect, and material style of [SessionRow], with the feature icon.
class _DrawerMenuRow extends StatefulWidget {
  const _DrawerMenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingTag,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailingTag;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DrawerMenuRow> createState() => _DrawerMenuRowState();
}

class _DrawerMenuRowState extends State<_DrawerMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.ink.base.withValues(
                alpha: widget.selected ? .14 : (_hovered ? .10 : .07),
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: widget.selected
                  ? context.ink.primary
                  : context.ink.secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: widget.selected
                              ? context.ink.primary
                              : context.ink.secondary,
                        ),
                      ),
                    ),
                    if (widget.trailingTag case final tag?)
                      Text(
                        tag,
                        style: mono(context, size: 11, opacity: InkLevel.faint),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, size: 11, opacity: InkLevel.faint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, size: 16, color: context.ink.faint),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: Pressable(
          onTap: widget.onTap,
          haptic: false,
          scale: .98,
          semanticLabel: widget.title,
          child: widget.selected
              ? GlassPanel(
                  level: Glass.regular,
                  radius: Radii.mediumAll,
                  child: row,
                )
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Motion.standardCurve,
                  decoration: BoxDecoration(
                    borderRadius: Radii.mediumAll,
                    color: context.ink.base.withValues(
                      alpha: _hovered ? .09 : .04,
                    ),
                  ),
                  child: row,
                ),
        ),
      ),
    );
  }
}
