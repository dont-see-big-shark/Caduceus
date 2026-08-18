import 'package:flutter/material.dart';

import 'agents_panel.dart';
import 'design/theme.dart';
import 'fleet_panel.dart';
import 'jobs_panel.dart';
import 'l10n/app_localizations.dart';
import 'memory_panel.dart';
import 'panel_rail.dart';
import 'processes_panel.dart';
import 'projects_panel.dart';
import 'shared_memory_panel.dart';
import 'skills_panel.dart';
import 'widgets/master_nav.dart';
import 'widgets/panel_frame.dart';
import 'workspace.dart';

/// The Panels overlay — the same master–detail shape Settings uses: the eight
/// panels as a left-hand nav, the open one beside it, switching in place. On
/// a phone it is the same [Panel] as a bottom sheet, and tapping a row opens
/// that panel as its own sheet.
class PanelsOverlay extends StatefulWidget {
  const PanelsOverlay({
    required this.workspace,
    required this.peers,
    this.onOpenPanel,
    super.key,
  });

  final Workspace workspace;
  final MemoryPeers peers;

  /// Phone path: dismiss the picker and open the chosen panel as its own sheet.
  final ValueChanged<RailPanel>? onOpenPanel;

  @override
  State<PanelsOverlay> createState() => _PanelsOverlayState();
}

class _PanelsOverlayState extends State<PanelsOverlay> {
  // The first panel this backend can serve: the overlay opens on a panel
  // that can actually build, not one that throws for a non-Hermes gateway.
  RailPanel get _defaultPanel =>
      panelItemsFor(widget.workspace).firstOrNull?.$1 ?? RailPanel.memory;

  late RailPanel _selected = _defaultPanel;

  Widget _detail(RailPanel panel) => switch (panel) {
    RailPanel.agents => AgentsPanel(
      gateway: widget.workspace.gateway,
      liveSessionId: widget.workspace.active?.liveId ?? '',
      embedded: true,
    ),
    RailPanel.fleet => FleetPanel(
      workspace: widget.workspace,
      peers: widget.peers,
      embedded: true,
    ),
    RailPanel.memory => MemoryPanel(
      workspace: widget.workspace,
      peers: widget.peers,
      embedded: true,
    ),
    RailPanel.shared => SharedMemoryPanel(
      workspace: widget.workspace,
      peers: widget.peers,
      embedded: true,
    ),
    RailPanel.skills => SkillsPanel(
      workspace: widget.workspace,
      peers: widget.peers,
      embedded: true,
    ),
    RailPanel.jobs => JobsPanel(workspace: widget.workspace, embedded: true),
    RailPanel.processes => ProcessesPanel(
      workspace: widget.workspace,
      sessionId: widget.workspace.active?.persistedId ?? '',
      embedded: true,
    ),
    RailPanel.projects => ProjectsPanel(
      gateway: widget.workspace.gateway,
      onOpenSession: widget.workspace.open,
      embedded: true,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= Panel.phoneWidth;
    return Panel(
      title: Text(l10n?.panels ?? 'Panels'),
      content: wide
          ? SizedBox(
              width: 960,
              height: 560,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 214,
                    child: MasterNav(
                      header: l10n?.panels ?? 'Panels',
                      items: [
                        for (final (panel, icon, label) in panelItemsFor(
                          widget.workspace,
                        ))
                          MasterNavItem(
                            icon: icon,
                            label: label,
                            selected: panel == _selected,
                            onTap: () => setState(() => _selected = panel),
                          ),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: context.ink.hairline),
                  Expanded(child: _detail(_selected)),
                ],
              ),
            )
          : PanelFrame(
              preferredWidth: 360,
              preferredHeight: 400,
              child: ListView(
                children: [
                  for (final (panel, icon, label) in panelItems)
                    ListTile(
                      dense: true,
                      leading: Icon(icon, size: 18),
                      title: Text(label),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onOpenPanel?.call(panel);
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
