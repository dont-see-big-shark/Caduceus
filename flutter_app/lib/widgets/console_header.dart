import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.dart';
import 'command_palette.dart';
import 'console_menu.dart';

import '../workspace.dart';

/// Top header bar for [ConsoleView].
///
/// Displays session info, status, working directory, git branch, model picker,
/// session action menu, and interrupt control.
class ConsoleHeader extends StatelessWidget {
  const ConsoleHeader({
    required this.console,
    required this.workspace,
    required this.actions,
    required this.onSetCwd,
    required this.onUndo,
    required this.onShowCheckpoints,
    required this.onShowProcesses,
    required this.onShowAgents,
    required this.onShowJourney,
    required this.onShowServer,
    required this.onFindInConversation,
    required this.onCopyTranscript,
    required this.onBranch,
    required this.onShowStats,
    required this.availableHeight,
    super.key,
  });

  /// The height this console actually has, from its `LayoutBuilder`.
  ///
  /// Not `MediaQuery.viewInsets`: `Scaffold` consumes the keyboard inset
  /// before the body is built, so inside it the inset always reads zero and
  /// any "room left" computed from it is the *unshrunken* screen. The
  /// constraint is the only honest number down here.
  final double availableHeight;

  final SessionConsole console;
  final Workspace workspace;
  final ConsoleActions actions;
  final VoidCallback onSetCwd;
  final VoidCallback onUndo;
  final VoidCallback onShowCheckpoints;
  final VoidCallback onShowProcesses;
  final VoidCallback onShowAgents;
  final VoidCallback onShowJourney;
  final VoidCallback onShowServer;
  final VoidCallback onFindInConversation;
  final VoidCallback onCopyTranscript;
  final VoidCallback onBranch;
  final VoidCallback onShowStats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: console,
      builder: (context, _) {
        // On a phone the id is already in the navigation bar above, and the
        // row that fits a Mac window overflows 393 points by a wide margin —
        // the first simulator run showed the striped overflow marker straight
        // through the middle of it.
        final compact = MediaQuery.sizeOf(context).width < 720;

        // A working directory of "/" is the server's default and says nothing;
        // showing it spent a whole row on a slash.
        final cwd = console.cwd.trim();
        final showsCwd = cwd.isNotEmpty && cwd != '/';

        // On a phone this band has nothing left to carry: the title is in the
        // navigation bar, the actions moved into it, and the running-turn
        // status moved down to the composer. An empty bar with a divider
        // under it is just a stripe eating vertical space on the screen that
        // has least of it.
        if (compact) return const SizedBox.shrink();

        // Landscape with the keyboard up leaves under 200 points for the whole
        // console, and at a raised text size the header and the composer
        // together no longer fit — the outer Column overflowed by 11. The band
        // is what gives way: it carries supplementary status, while the
        // composer is being used and the transcript is being read.
        if (availableHeight < 260) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, box) {
            // A desktop window can be squeezed to anything (the macOS
            // minimum is 760 pt, and the panel rail takes 320 of it), so the
            // header has to survive 140 pt. The ⌘K hint and the working
            // directory are the first to give way — the shortcut still works
            // and the menu stays — then only the title remains.
            final veryNarrow = !compact && box.maxWidth < 300;
            final titleOnly = !compact && box.maxWidth < 140;
            // The design's sub row: backend · model · working directory, all
            // machine text in mono. The model is blank for a session that
            // has never been opened.
            final sub = !compact && !veryNarrow && !titleOnly;
            final model = console.model.trim();
            final machine = sub && (model.isNotEmpty || showsCwd);
            return Container(
              key: const ValueKey('header'),
              padding: EdgeInsets.fromLTRB(16, 10, compact ? 4 : 12, 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.ink.hairline)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Flexible, not bare: a session title is server-set
                            // and can be a sentence, and it grows with the system
                            // text size on top of that. Unconstrained beside the
                            // working directory it overflowed a 1200 pt window by
                            // 286 pt at ×1.6 — the title pushing the path off the
                            // end rather than either of them giving way.
                            if (!compact)
                              Flexible(
                                child: Text(
                                  console.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                          ],
                        ),
                        // The design's `.console-head .sub` — one mono line:
                        // backend · model · working directory.
                        if (machine)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              children: [
                                if (model.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      '${workspace.backend.displayName} · $model',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: mono(
                                        context,
                                        size: 11,
                                        opacity: InkLevel.tertiary,
                                      ),
                                    ),
                                  ),
                                if (showsCwd) ...[
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: InkWell(
                                      onTap: console.streaming
                                          ? null
                                          : onSetCwd,
                                      child: Text(
                                        console.branch.isEmpty
                                            ? console.cwd
                                            : '${console.cwd}  (${console.branch})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: mono(
                                          context,
                                          size: 11,
                                          opacity: InkLevel.tertiary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Not on a phone: the compact bar directly above already draws
                  // this menu, and the simulator showed the two circles stacked
                  // one under the other, opening the same list. The band still
                  // earns its place when there is a working directory or a
                  // running turn to report — but not a second copy of the menu.
                  if (!compact && !veryNarrow) ...[
                    Tooltip(
                      message: 'Commands  ⌘K',
                      child: TextButton(
                        onPressed: () => showCommandPalette(
                          context,
                          sessionCommands(actions, context),
                        ),
                        child: Text('⌘K', style: mono(context, size: 11)),
                      ),
                    ),
                    if (!titleOnly) ConsoleMenu(actions: actions),
                  ],
                  // Model and interrupt both moved into the composer: the model
                  // sits beside the field it will answer, and send becomes stop
                  // while a turn runs. Duplicating them here cost width on a
                  // 393-point row and split one decision across two places.
                ],
              ),
            );
          },
        );
      },
    );
  }
}
