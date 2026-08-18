import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'l10n/app_localizations.dart';
import 'widgets/panel_frame.dart';
import 'workspace.dart';

/// What the server can actually do: its inventory, and how it is configured.
class ServerPanel extends StatefulWidget {
  const ServerPanel({
    required this.workspace,
    required this.sessionId,
    super.key,
  });

  final Workspace workspace;
  final String sessionId;

  @override
  State<ServerPanel> createState() => _ServerPanelState();
}

const _groupLabels = <SkillGroup, String>{
  SkillGroup.tool: 'Tools',
  SkillGroup.skill: 'Skills',
  SkillGroup.plugin: 'Plugins',
  SkillGroup.command: 'Commands',
};

class _ServerPanelState extends State<ServerPanel>
    with TickerProviderStateMixin {
  TabController? _tabs;

  List<AgentSkill>? _inventory;
  List<ServerConfigSection>? _config;
  List<String> _reloads = const [];
  String? _busy;
  String? _error;

  Workspace get _ws => widget.workspace;

  bool get _hasConfig => _ws.supports(Capability.serverConfig);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  List<SkillGroup> get _groups => [
    for (final group in _groupLabels.keys)
      if (_inventory?.any((s) => s.group == group) ?? false) group,
  ];

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final inventory = await _ws.skills(widget.sessionId);
      final config = _hasConfig
          ? await _ws.serverConfig()
          : const <ServerConfigSection>[];
      final reloads = _ws.supports(Capability.serverMaintenance)
          ? await _ws.reloadTargets(widget.sessionId)
          : const <String>[];
      if (!mounted) return;
      setState(() {
        _inventory = inventory;
        _config = config;
        _reloads = reloads;
        final tabs = _groups.length + (_hasConfig ? 1 : 0);
        _tabs?.dispose();
        _tabs = TabController(length: tabs == 0 ? 1 : tabs, vsync: this);
      });
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    }
  }

  String _groupLabel(SkillGroup group, AppLocalizations? l10n) {
    switch (group) {
      case SkillGroup.tool:
        return l10n?.tools ?? 'Tools';
      case SkillGroup.skill:
        return l10n?.skills ?? 'Skills';
      case SkillGroup.plugin:
        return l10n?.plugins ?? 'Plugins';
      case SkillGroup.command:
        return l10n?.commands ?? 'Commands';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tabs = _tabs;
    return Panel(
      title: Row(
        children: [
          Expanded(child: Text(l10n?.server ?? 'Server')),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: l10n?.reload ?? 'Reload',
          ),
        ],
      ),
      content: PanelFrame(
        child: switch ((_error, tabs)) {
          (final String message, _) => Center(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          (_, null) => const Center(child: CircularProgressIndicator()),
          (_, final TabController controller) => _body(theme, controller),
        },
      ),
    );
  }

  Widget _body(ThemeData theme, TabController controller) {
    final l10n = AppLocalizations.of(context);
    final groups = _groups;
    if (groups.isEmpty && !_hasConfig) {
      return Center(
        child: Text(
          l10n?.thisServerReportsNothing ??
              'This server reports nothing it can reach for.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return Column(
      children: [
        TabBar(
          controller: controller,
          isScrollable: true,
          tabs: [
            for (final group in groups) Tab(text: _groupLabel(group, l10n)),
            if (_hasConfig) Tab(text: l10n?.config ?? 'Config'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [
              for (final group in groups) _list(theme, group),
              if (_hasConfig) _configTab(theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _list(ThemeData theme, SkillGroup group) {
    final l10n = AppLocalizations.of(context);
    final items = [
      for (final skill in _inventory ?? const <AgentSkill>[])
        if (skill.group == group) skill,
    ];
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, _) =>
                Divider(height: 1, color: context.ink.hairline),
            itemBuilder: (context, i) {
              final skill = items[i];
              return ListTile(
                dense: true,
                leading: Icon(
                  skill.enabled
                      ? Icons.check_circle
                      : Icons.remove_circle_outline,
                  size: 16,
                ),
                title: Text(skill.name),
                subtitle: Text(
                  [
                    skill.description,
                    skill.detail,
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l10n?.readOnlyConfigNote ??
                'Read-only: turning any of this on or off changes the whole '
                    "server's configuration, not this session's.",
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _configTab(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      children: [
        for (final section in _config ?? const <ServerConfigSection>[]) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(section.title, style: theme.textTheme.labelSmall),
          ),
          for (final (label, value) in section.rows)
            ListTile(
              dense: true,
              title: Text(label),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
        ],
        if (_reloads.isNotEmpty) ...[
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n?.maintenanceNote ??
                  'Maintenance — affects every session on this server',
              style: theme.textTheme.labelSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final target in _reloads)
                  OutlinedButton(
                    onPressed: _busy != null ? null : () => _reload(target),
                    child: _busy == target
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('${l10n?.reload ?? "Reload"} $target'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _reload(String target) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text(l10n?.reloadTargetTitle(target) ?? 'Reload $target?'),
        content: Text(
          l10n?.reloadTargetMessage ??
              'This changes the server for every session on it, not just this one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n?.continueAction ?? 'Continue'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = target);
    try {
      await _ws.reloadServer(widget.sessionId, target);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    }
    if (mounted) setState(() => _busy = null);
  }
}
