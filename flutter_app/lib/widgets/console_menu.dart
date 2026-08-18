import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import '../haptics.dart';
import 'menu_card.dart';
import '../design/press.dart';
import '../design/theme.dart';
import '../l10n/app_localizations.dart';

/// Everything that acts on the session, behind one control.
///
/// Shared by the phone's top bar and the desktop header so the two cannot
/// drift apart — they had already started to, with the model picker in one
/// and not the other.
class ConsoleActions {
  const ConsoleActions({
    required this.streaming,
    required this.onSetCwd,
    required this.onUndo,
    required this.onShowCheckpoints,
    required this.onShowProcesses,
    required this.onShowAgents,
    required this.onShowJourney,
    required this.onShowMemory,
    required this.onShowServer,
    required this.onShowSkills,
    required this.onShowFleet,
    required this.onShowSharedMemory,
    required this.onFindInConversation,
    required this.onCopyTranscript,
    required this.onBranch,
    required this.onShowStats,
    required this.supports,
  });

  final bool streaming;

  /// Whether the backend can serve a surface at all.
  ///
  /// Not "is it enabled" — whether it *exists*. A capability the backend does
  /// not declare means the menu item is absent, not greyed out, which is the
  /// rule this codebase already follows for the camera tile on a machine with
  /// no camera: a menu item that fails is worse than one that is not there.
  final bool Function(Capability) supports;
  final VoidCallback onSetCwd;
  final VoidCallback onUndo;
  final VoidCallback onShowCheckpoints;
  final VoidCallback onShowProcesses;
  final VoidCallback onShowAgents;
  final VoidCallback onShowJourney;

  /// The memory bridge — what this agent has written down about you.
  final VoidCallback onShowMemory;
  final VoidCallback onShowServer;

  /// The skills bridge — what every agent can do, side by side.
  final VoidCallback onShowSkills;

  /// The fleet — every agent, and the edges between them.
  final VoidCallback onShowFleet;

  /// The shared knowledge base — facts every agent should know.
  final VoidCallback onShowSharedMemory;
  final VoidCallback onFindInConversation;
  final VoidCallback onCopyTranscript;
  final VoidCallback onBranch;
  final VoidCallback onShowStats;
}

/// One row of the menu: what it says, what it does, and what a backend must
/// declare for it to exist at all.
class _Entry {
  const _Entry(this.value, this.label, {this.needs, this.icon});
  const _Entry.divider() : value = '', label = '', needs = null, icon = null;

  final String value;
  final String label;
  final Capability? needs;
  final IconData? icon;

  bool get divider => value.isEmpty;
}

/// Which capabilities this menu gates its actions on.
///
/// Exposed so a test can compare this surface against the command palette.
/// The two are not interchangeable — on desktop the "…" opens this menu, on a
/// phone it opens the palette, and there the palette *is* the session menu.
/// An action present in one and missing from the other is fully working on
/// one form factor and unreachable on the other. That is exactly how the
/// memory panel shipped.
///
/// Derived from the real entries rather than restated as a parallel list: two
/// lists that must agree are the drift this is meant to catch, not a way to
/// catch it. The labels need a [BuildContext] for translation and the
/// capabilities do not, which is why this can be called without one.
Set<Capability> consoleMenuNeeds() => {
  for (final entry in _entries(null))
    if (entry.needs != null) entry.needs!,
};

/// Every action, in order, with the capability it depends on.
List<_Entry> _getEntries(BuildContext context) =>
    _entries(AppLocalizations.of(context));

/// The one list. [l10n] is null when only the structure is wanted.
List<_Entry> _entries(AppLocalizations? l10n) {
  return [
    _Entry(
      'copy',
      l10n?.copyTranscript ?? 'Copy transcript',
      icon: Icons.content_copy_rounded,
    ),
    _Entry(
      'branch',
      l10n?.branchSession ?? 'Branch session…',
      needs: Capability.sessionBranching,
      icon: Icons.alt_route_rounded,
    ),
    _Entry(
      'find',
      l10n?.findInConversation ?? 'Find in conversation…',
      icon: Icons.search_rounded,
    ),
    _Entry(
      'undo',
      l10n?.undoLastExchange ?? 'Undo last exchange',
      needs: Capability.transcriptUndo,
      icon: Icons.undo_rounded,
    ),
    _Entry(
      'cwd',
      l10n?.workingDirectory ?? 'Working directory…',
      needs: Capability.cwdControl,
      icon: Icons.folder_open_rounded,
    ),
    _Entry(
      'stats',
      l10n?.usageAndContext ?? 'Usage and context…',
      needs: Capability.usageReporting,
      icon: Icons.donut_small_rounded,
    ),
    const _Entry.divider(),
    _Entry(
      'checkpoints',
      l10n?.fileCheckpoints ?? 'File checkpoints…',
      needs: Capability.checkpoints,
      icon: Icons.history_rounded,
    ),
    _Entry(
      'processes',
      l10n?.backgroundProcesses ?? 'Background processes…',
      needs: Capability.backgroundProcesses,
      icon: Icons.terminal_rounded,
    ),
    _Entry(
      'agents',
      l10n?.agents ?? 'Agents…',
      needs: Capability.subagents,
      icon: Icons.hub_rounded,
    ),
    _Entry(
      'journey',
      l10n?.journeyWhatItLearned ?? 'Journey — what it learned…',
      needs: Capability.learning,
      icon: Icons.auto_stories_rounded,
    ),
    _Entry(
      'memory',
      'Memory…',
      needs: Capability.memoryRead,
      icon: Icons.psychology_rounded,
    ),
    _Entry(
      'server',
      l10n?.toolsetsSkillsPlugins ?? 'Toolsets, skills, plugins…',
      needs: Capability.skills,
      icon: Icons.grid_view_rounded,
    ),
    _Entry(
      'skills',
      'Skills…',
      needs: Capability.skills,
      icon: Icons.extension_rounded,
    ),
    _Entry(
      'fleet',
      'Fleet…',
      needs: Capability.memoryRead,
      icon: Icons.device_hub_rounded,
    ),
    _Entry(
      'shared',
      'Shared memory…',
      needs: Capability.memoryRead,
      icon: Icons.dns_rounded,
    ),
  ];
}

class ConsoleMenu extends StatelessWidget {
  const ConsoleMenu({
    required this.actions,
    this.tapTargetSize = 36,
    super.key,
  });

  final ConsoleActions actions;

  /// The press target's square size. 44 pt on a phone so the compact top bar
  /// keeps the same minimum touch target as every other control there.
  final double tapTargetSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = _getEntries(context);
    final menu = MenuController();
    final isPhone = MediaQuery.sizeOf(context).width < 720;
    final menuWidth = isPhone ? 210.0 : 220.0;
    final dx = isPhone ? -124.0 : -(menuWidth - tapTargetSize);
    return Tooltip(
      message: l10n?.sessionActions ?? 'Session actions',
      child: MenuAnchor(
        controller: menu,
        // The design's `more-menu`: a compact glass card anchored to the
        // button, never a full-window surface.
        style: anchoredMenuStyle,
        alignmentOffset: Offset(dx, 6),
        menuChildren: [
          MenuCard(
            width: menuWidth,
            items: [
              for (final entry in entries)
                if (entry.needs == null || actions.supports(entry.needs!))
                  if (entry.divider)
                    const MenuItem(label: '', divider: true)
                  else
                    MenuItem(
                      label: entry.label,
                      icon: entry.icon,
                      enabled: entry.value != 'undo' || !actions.streaming,
                      onTap: () {
                        menu.close();
                        Haptics.select();
                        _handle(entry.value);
                      },
                    ),
            ],
          ),
        ],
        child: Pressable(
          onTap: () {
            Haptics.select();
            menu.open();
          },
          child: SizedBox(
            width: tapTargetSize,
            height: tapTargetSize,
            child: Center(
              child: Container(
                width: tapTargetSize >= 40 ? 38 : 32,
                height: tapTargetSize >= 40 ? 38 : 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    tapTargetSize >= 40 ? 14 : 10,
                  ),
                  color: context.ink.base.withValues(alpha: .07),
                  border: Border.all(color: context.ink.hairline),
                ),
                child: const Icon(Icons.more_horiz_rounded, size: 19),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handle(String value) {
    Haptics.select();
    switch (value) {
      case 'undo':
        actions.onUndo();
      case 'checkpoints':
        actions.onShowCheckpoints();
      case 'processes':
        actions.onShowProcesses();
      case 'agents':
        actions.onShowAgents();
      case 'journey':
        actions.onShowJourney();
      case 'memory':
        actions.onShowMemory();
      case 'server':
        actions.onShowServer();
      case 'skills':
        actions.onShowSkills();
      case 'fleet':
        actions.onShowFleet();
      case 'shared':
        actions.onShowSharedMemory();
      case 'find':
        actions.onFindInConversation();
      case 'copy':
        actions.onCopyTranscript();
      case 'branch':
        actions.onBranch();
      case 'stats':
        actions.onShowStats();
      case 'cwd':
        actions.onSetCwd();
    }
  }
}
