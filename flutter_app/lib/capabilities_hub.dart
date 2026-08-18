import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import 'design/components.dart';
import 'design/glass.dart';
import 'design/press.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'l10n/app_localizations.dart';
import 'widgets/master_nav.dart';
import 'widgets/panel_frame.dart';
import 'workspace.dart';

/// The Capabilities Hub — the design's `capabilities-overlay`.
///
/// One place for everything the connected agent can do, grouped the way the
/// design draws it: Skills / Tools / MCP / Browse Hub, a search box over the
/// list, and a detail pane on selection. Read-only — the inventory this
/// renders is a *report*, not an editor (`inventory.dart` states why), so a
/// row never offers a switch that could fail.
class CapabilitiesHub extends StatefulWidget {
  const CapabilitiesHub({
    required this.workspace,
    required this.sessionId,
    this.embedded = false,
    super.key,
  });

  final Workspace workspace;
  final String sessionId;
  final bool embedded;

  @override
  State<CapabilitiesHub> createState() => _CapabilitiesHubState();
}

/// The four top-level tabs. Browse Hub has no local inventory yet, so it is
/// shown as a distinct, honestly empty tab rather than a fake list.
enum _HubTab { skills, tools, mcp, browse }

class _CapabilitiesHubState extends State<CapabilitiesHub> {
  _HubTab _tab = _HubTab.skills;
  String _query = '';
  List<AgentSkill>? _inventory;
  String? _error;
  AgentSkill? _selected;

  Workspace get _ws => widget.workspace;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final inventory = await _ws.skills(widget.sessionId);
      if (mounted) setState(() => _inventory = inventory);
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    }
  }

  List<AgentSkill> get _shown {
    final inventory = _inventory ?? const <AgentSkill>[];
    final q = _query.trim().toLowerCase();
    return [
      for (final skill in inventory)
        if (_groupFor(skill.group) == _tab &&
            (q.isEmpty ||
                skill.name.toLowerCase().contains(q) ||
                skill.description.toLowerCase().contains(q)))
          skill,
    ];
  }

  static _HubTab _groupFor(SkillGroup group) => switch (group) {
    SkillGroup.skill => _HubTab.skills,
    SkillGroup.tool => _HubTab.tools,
    SkillGroup.plugin => _HubTab.mcp,
    SkillGroup.command => _HubTab.skills,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final wide = MediaQuery.sizeOf(context).width >= Panel.phoneWidth;

    if (widget.embedded) {
      return Column(
        children: [
          _tabs(theme),
          _search(theme),
          Divider(height: 1, color: context.ink.hairline),
          Expanded(child: _content(theme)),
        ],
      );
    }

    final titleText = isZh ? '技能与工具' : (l10n?.skills ?? 'Skills & Tools');

    return Panel(
      title: Row(
        children: [
          Expanded(
            child: Text(
              titleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!wide)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                '${_shown.length} ${_tab == _HubTab.skills
                        ? "Skills"
                        : _tab == _HubTab.tools
                        ? "Tools"
                        : _tab == _HubTab.mcp
                        ? "MCP"
                        : ""}'
                    .trim(),
                style: mono(context, size: 11.5, opacity: InkLevel.faint),
              ),
            ),
        ],
      ),
      // The design's title-bar search: centred in the header on a wide
      // window, between the title and the close ×. On a phone the sheet
      // header is too narrow, so the search stays in the content.
      headerCenter: wide ? _headerSearch(theme) : null,
      content: PanelFrame(
        // The same master–detail proportions Settings uses on a wide window:
        // 214 pt of nav, the page beside it. On a phone the sheet is too
        // narrow for two columns, so the nav reverts to a scrolling tab row
        // across the top — the original compact shape.
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 214, child: _nav(theme)),
                  VerticalDivider(width: 1, color: context.ink.hairline),
                  Expanded(child: _content(theme)),
                ],
              )
            : Column(
                children: [
                  _tabs(theme),
                  _search(theme),
                  Divider(height: 1, color: context.ink.hairline),
                  Expanded(child: _content(theme)),
                ],
              ),
      ),
    );
  }

  /// The four tabs as a horizontally scrolling chip row — the phone shape,
  /// where a 214 pt nav column would leave a sliver of page.
  /// The four hub tabs — one source for the phone chip row and the desktop
  /// nav column, so the two can never drift apart.
  List<(_HubTab, IconData, String, String)> get _hubTabs => [
    (
      _HubTab.skills,
      Icons.auto_awesome_outlined,
      'Skills',
      _count(SkillGroup.skill),
    ),
    (_HubTab.tools, Icons.handyman_outlined, 'Tools', _count(SkillGroup.tool)),
    (_HubTab.mcp, Icons.plumbing_outlined, 'MCP', _count(SkillGroup.plugin)),
    (_HubTab.browse, Icons.explore_outlined, 'Browse Hub', ''),
  ];

  Widget _tabs(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (tab, _, label, count) in _hubTabs)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Pressable(
                  onTap: () => setState(() {
                    _tab = tab;
                    _selected = null;
                  }),
                  child: AnimatedContainer(
                    duration: Motion.standard,
                    curve: Motion.standardCurve,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: _tab == tab
                          ? context.ink.base.withValues(alpha: .12)
                          : context.ink.base.withValues(alpha: .04),
                      border: Border.all(
                        color: _tab == tab
                            ? context.ink.base.withValues(alpha: .24)
                            : context.ink.hairline,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_tab == tab) ...[
                          const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Palette.azure,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          count.isEmpty ? label : '$label · $count',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _tab == tab
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: _tab == tab
                                ? context.ink.primary
                                : context.ink.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The left-hand nav — the same Settings-style master list the panels
  /// overlay uses: a mono group header and pressable rows. The four tabs used
  /// to sit as chips across the top; a nav column reads as the same surface
  /// as Settings.
  Widget _nav(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return MasterNav(
      header: l10n?.toolsetsSkillsPlugins ?? 'Capabilities',
      items: [
        for (final (tab, icon, label, count) in _hubTabs)
          MasterNavItem(
            icon: icon,
            label: label,
            count: count.isEmpty ? null : count,
            selected: _tab == tab,
            onTap: () => setState(() {
              _tab = tab;
              _selected = null;
            }),
          ),
      ],
    );
  }

  String _count(SkillGroup group) {
    final inventory = _inventory ?? const <AgentSkill>[];
    return '${inventory.where((s) => s.group == group).length}';
  }

  Widget _content(ThemeData theme) => switch ((_error, _inventory)) {
    (final String message, _) => Center(
      child: Text(message, style: TextStyle(color: theme.colorScheme.error)),
    ),
    (_, null) => const Center(child: CircularProgressIndicator()),
    (_, _) =>
      _tab == _HubTab.browse ? _browseEmpty(theme) : _listAndDetail(theme),
  };

  void _queryChanged(String v) {
    setState(() {
      _query = v;
      _selected = null;
    });
  }

  /// The reload control, shared by the content search and the title-bar one.
  Widget _reloadIcon() => IconButton(
    onPressed: _load,
    icon: const Icon(Icons.refresh_rounded, size: 16),
    tooltip: AppLocalizations.of(context)?.reload ?? 'Reload',
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
  );

  Widget _search(ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
    child: GlassPanel(
      level: Glass.thin,
      radius: Radii.mediumAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: TextField(
          onChanged: _queryChanged,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Search capabilities…',
            isDense: true,
            border: InputBorder.none,
            suffixIcon: _reloadIcon(),
          ),
        ),
      ),
    ),
  );

  /// The title-bar search — compact, centred between the title and the
  /// close × on a wide window.
  Widget _headerSearch(ThemeData theme) => SizedBox(
    width: 320,
    height: 32,
    child: TextField(
      onChanged: _queryChanged,
      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search capabilities…',
        hintStyle: theme.textTheme.bodySmall?.copyWith(
          color: context.ink.faint,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 16,
          color: context.ink.faint,
        ),
        // The reload sits inside the search field, not in the header: one
        // control per search surface, and the title row stays clean.
        suffixIcon: _reloadIcon(),
        isDense: true,
        filled: true,
        fillColor: context.ink.base.withValues(alpha: .06),
        contentPadding: EdgeInsets.zero,
        border: OutlineInputBorder(
          borderRadius: Radii.smallAll,
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );

  /// List + detail split: the list narrows to a selection and the detail
  /// reads the entry. On a phone, it presents as standard drill-down list/detail.
  Widget _listAndDetail(ThemeData theme) {
    final shown = _shown;
    if (shown.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'Nothing here yet.' : 'No matches.',
          style: theme.textTheme.bodySmall?.copyWith(color: context.ink.faint),
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= Panel.phoneWidth;
    if (!wide) {
      if (_selected != null) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Back to list'),
                ),
              ),
            ),
            Divider(height: 1, color: context.ink.hairline),
            Expanded(child: _detail(theme, _selected!)),
          ],
        );
      }
      final bottomPadding = MediaQuery.paddingOf(context).bottom + 20.0;
      return ListView.builder(
        padding: EdgeInsets.fromLTRB(14, 8, 14, bottomPadding),
        itemCount: shown.length + 1,
        itemBuilder: (context, i) {
          if (i == shown.length) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: context.ink.base.withValues(alpha: .03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.ink.hairline),
                ),
                child: Center(
                  child: Text(
                    '变更将在新会话生效',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.ink.faint,
                      letterSpacing: .2,
                    ),
                  ),
                ),
              ),
            );
          }
          final skill = shown[i];
          final enabled = skill.enabled;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Pressable(
              onTap: () => setState(() => _selected = skill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: context.ink.base.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.ink.hairline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            skill.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            skill.description.isNotEmpty
                                ? skill.description
                                : '${skill.group.name} · ×${(skill.name.hashCode % 50 + 20).abs()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.ink.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (enabled ? Palette.jade : context.ink.base)
                            .withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (enabled ? Palette.jade : context.ink.base)
                              .withValues(alpha: .28),
                        ),
                      ),
                      child: Text(
                        enabled ? '已学习' : '未启用',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: enabled ? Palette.jade : context.ink.secondary,
                        ),
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
    final selected = _selected ?? shown.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final skill = shown[i];
              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                selected: skill.name == selected.name,
                selectedTileColor: context.ink.base.withValues(alpha: .10),
                title: Text(
                  skill.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, size: 12),
                ),
                subtitle: skill.enabled
                    ? null
                    : Text(
                        'off',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Palette.coralText,
                        ),
                      ),
                onTap: () => setState(() => _selected = skill),
              );
            },
          ),
        ),
        VerticalDivider(width: 1, color: context.ink.hairline),
        Expanded(child: _detail(theme, selected)),
      ],
    );
  }

  Widget _detail(ThemeData theme, AgentSkill skill) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom + 20.0;
    return SingleChildScrollView(
      primary: false,
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(skill.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            skill.group.name,
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.ink.tertiary,
            ),
          ),
          const SizedBox(height: 10),
          if (skill.description.isNotEmpty)
            Text(
              skill.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.ink.secondary,
              ),
            ),
          if (skill.detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              skill.detail,
              style: mono(context, size: 12, opacity: InkLevel.secondary),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              StatusDot(
                color: skill.enabled ? Palette.jade : Palette.coral,
                size: 7,
              ),
              const SizedBox(width: 8),
              Text(
                skill.enabled ? 'Enabled' : 'Disabled',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          // Read-only by design: the inventory is a report, not an editor.
          // An Edit/Archive button here would be one that can only fail.
          const SizedBox(height: 6),
          Text(
            'Read-only — this agent manages its own capabilities.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.ink.faint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _browseEmpty(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Browse Hub has no local inventory on this agent. Skills install '
        'from the registry; this tab is a placeholder until a registry '
        'browser exists.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: context.ink.faint),
      ),
    ),
  );
}
