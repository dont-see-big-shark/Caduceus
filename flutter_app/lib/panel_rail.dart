import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import 'agents_panel.dart';
import 'design/glass.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'fleet_panel.dart';
import 'jobs_panel.dart';
import 'memory_panel.dart';
import 'processes_panel.dart';
import 'projects_panel.dart';
import 'shared_memory_panel.dart';
import 'skills_panel.dart';
import 'workspace.dart';

/// Which panel the right-hand rail is showing.
enum RailPanel {
  agents,
  fleet,
  memory,
  shared,
  skills,
  jobs,
  processes,
  projects,
}

/// The eight panels, in the design's order — one source for the rail, the
/// drawer and the Panels overlay.
const panelItems = <(RailPanel, IconData, String)>[
  (RailPanel.agents, Icons.group_outlined, 'Agents'),
  (RailPanel.fleet, Icons.hub_outlined, 'Fleet'),
  (RailPanel.memory, Icons.psychology_outlined, 'Memory'),
  (RailPanel.shared, Icons.auto_stories_outlined, 'Shared'),
  (RailPanel.skills, Icons.auto_awesome_outlined, 'Skills'),
  (RailPanel.jobs, Icons.schedule_rounded, 'Jobs'),
  (RailPanel.processes, Icons.terminal_rounded, 'Processes'),
  (RailPanel.projects, Icons.folder_outlined, 'Projects'),
];

/// Which capability gates a panel, or null when every backend may build it.
///
/// The Hermes-gateway panels (Agents, Projects) are gated so a non-Hermes
/// backend (OpenClaw) never builds a surface that would throw on `gateway` —
/// the same rule the console menu already applies to its actions.
Capability? panelCapability(RailPanel panel) => switch (panel) {
  RailPanel.agents => Capability.subagents,
  RailPanel.projects => Capability.projects,
  RailPanel.jobs => Capability.cron,
  RailPanel.processes => Capability.backgroundProcesses,
  RailPanel.skills => Capability.skills,
  RailPanel.memory ||
  RailPanel.shared ||
  RailPanel.fleet => Capability.memoryRead,
};

/// The panels this workspace's backend can actually serve.
List<(RailPanel, IconData, String)> panelItemsFor(Workspace workspace) =>
    panelItems.where((item) {
      final need = panelCapability(item.$1);
      return need == null || workspace.supports(need);
    }).toList();

/// The desktop right-hand panel container — the design's floating right
/// column. The eight panel widgets host here `embedded`, so the same panels
/// that open as dialogs elsewhere render as a glass column without nesting
/// dialogs. The rail is default-collapsed; the header row floats it open and
/// the close button folds it again.
class PanelRail extends StatefulWidget {
  const PanelRail({
    required this.workspace,
    required this.open,
    required this.panel,
    required this.onClose,
    required this.onSelect,
    this.peers = MemoryPeers.none,
    super.key,
  });

  final Workspace workspace;
  final MemoryPeers peers;

  /// Whether the rail is currently visible.
  final bool open;

  /// The panel to show when open. Null shows the rail as a picker only.
  final RailPanel? panel;

  final VoidCallback onClose;
  final ValueChanged<RailPanel> onSelect;

  @override
  State<PanelRail> createState() => _PanelRailState();
}

class _PanelRailState extends State<PanelRail> {
  List<(RailPanel, IconData, String)> get _items =>
      panelItemsFor(widget.workspace);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!widget.open) {
      // A collapsed rail is still the affordance to float it: the icon strip
      // stays, so the panels are one tap away rather than hidden behind a
      // menu. The strip itself is a thin sheet, never a nested glass panel.
      return Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 48,
          child: Column(
            children: [
              for (final (panel, icon, label) in _items)
                _RailButton(
                  icon: icon,
                  tooltip: label,
                  selected: widget.panel == panel,
                  onTap: () => widget.onSelect(panel),
                ),
            ],
          ),
        ),
      );
    }

    return GlassPanel(
      level: Glass.regular,
      radius: BorderRadius.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: the same icon strip, now on a surface, plus a close.
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    children: [
                      for (final (panel, icon, label) in _items)
                        _RailButton(
                          icon: icon,
                          tooltip: label,
                          selected: widget.panel == panel,
                          onTap: () => widget.onSelect(panel),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  tooltip: 'Close panel',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.ink.hairline),
          Expanded(
            child: widget.panel == null
                ? Center(
                    child: Text(
                      'Pick a panel above',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.ink.faint,
                      ),
                    ),
                  )
                : _panelBody(widget.panel!),
          ),
        ],
      ),
    );
  }

  Widget _panelBody(RailPanel panel) {
    final ws = widget.workspace;
    switch (panel) {
      case RailPanel.agents:
        return AgentsPanel(
          gateway: ws.gateway,
          liveSessionId: ws.active?.liveId ?? '',
          embedded: true,
        );
      case RailPanel.fleet:
        return FleetPanel(workspace: ws, peers: widget.peers, embedded: true);
      case RailPanel.memory:
        return MemoryPanel(workspace: ws, peers: widget.peers, embedded: true);
      case RailPanel.shared:
        return SharedMemoryPanel(
          workspace: ws,
          peers: widget.peers,
          embedded: true,
        );
      case RailPanel.skills:
        return SkillsPanel(workspace: ws, peers: widget.peers, embedded: true);
      case RailPanel.jobs:
        return JobsPanel(workspace: ws, embedded: true);
      case RailPanel.processes:
        return ProcessesPanel(
          workspace: ws,
          sessionId: ws.active?.persistedId ?? '',
          embedded: true,
        );
      case RailPanel.projects:
        return ProjectsPanel(
          gateway: ws.gateway,
          onOpenSession: ws.open,
          embedded: true,
        );
    }
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(
        icon,
        size: 18,
        color: selected ? Palette.brass : context.ink.tertiary,
      ),
      // Selected = a thicker chip rather than a tinted square: the rail is
      // chrome, and hierarchy here is material, not colour.
      style: selected
          ? IconButton.styleFrom(
              backgroundColor: context.ink.base.withValues(alpha: .08),
            )
          : null,
      visualDensity: VisualDensity.compact,
    );
  }
}
