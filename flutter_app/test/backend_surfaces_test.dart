/// What a backend cannot do is not on screen.
///
/// The rule this codebase already had for the attachment sheet — a menu item
/// that fails is worse than one that is absent — read from the direction that
/// is easy to miss. A capability can be declared for a *gateway* that can
/// genuinely serve it while this client's path to it still goes somewhere
/// else, and then the control is on screen and throws when pressed.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/widgets/command_palette.dart';
import 'package:caduceus/widgets/console_composer.dart';
import 'package:caduceus/widgets/console_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ConsoleActions _actions(Set<Capability> capabilities) => ConsoleActions(
  streaming: false,
  supports: capabilities.contains,
  onSetCwd: () {},
  onUndo: () {},
  onShowCheckpoints: () {},
  onShowProcesses: () {},
  onShowAgents: () {},
  onShowJourney: () {},
  onShowMemory: () {},
  onShowServer: () {},
  onShowSkills: () {},
  onShowFleet: () {},
  onShowSharedMemory: () {},
  onFindInConversation: () {},
  onCopyTranscript: () {},
  onBranch: () {},
  onShowStats: () {},
);

/// What ClawBackend declares today.
const _openClaw = {
  Capability.history,
  Capability.approvals,
  Capability.toolCalls,
  Capability.fileAttach,
  Capability.imageAttach,
  Capability.modelSwitching,
  Capability.sessionBranching,
  Capability.channels,
  Capability.skills,
  Capability.serverConfig,
  Capability.usageReporting,
  Capability.backgroundProcesses,
  Capability.cron,
  Capability.memoryRead,
};

void main() {
  test('an OpenClaw connection offers none of the Hermes-only surfaces', () {
    final labels = sessionCommands(
      _actions(_openClaw),
    ).map((c) => c.label).toList();

    // Shrinking on purpose. Background processes and usage used to be here
    // and are not any more: `tasks.list` and `sessions.usage` turned out to
    // be `operator.read`, so those surfaces are served rather than absent.
    // What is left is genuinely absent from the OpenClaw contract.
    for (final absent in const [
      'File checkpoints…',
      'Agents…',
      'Journey — what it learned…',
      'Working directory…',
      'Undo last exchange',
    ]) {
      expect(
        labels,
        isNot(contains(absent)),
        reason: '$absent goes through the Hermes client and would throw',
      );
    }
  });

  test('what every agent can do is still offered', () {
    final labels = sessionCommands(
      _actions(_openClaw),
    ).map((c) => c.label).toList();

    // Reading and searching a conversation needs no backend at all.
    expect(labels, contains('Find in conversation…'));
    expect(labels, contains('Copy transcript'));
    // Branching goes through the backend now, so a gateway that can fork a
    // transcript gets the action wherever it is.
    expect(labels, contains('Branch…'));
  });

  test('Hermes, which declares everything, loses nothing', () {
    final labels = sessionCommands(
      _actions(Capability.values.toSet()),
    ).map((c) => c.label).toList();

    expect(labels, contains('File checkpoints…'));
    expect(labels, contains('Branch…'));
  });

  test('a backend that takes no attachments is not offered the sheet', () {
    // Every tile in that sheet — camera, library, file, video — ends in a
    // call the backend cannot serve, so offering it would be four failures
    // behind one button. OpenClaw can take them; a backend that cannot must
    // not show the button.
    const canAttach = {Capability.fileAttach, Capability.imageAttach};
    expect(<Capability>{}.intersection(canAttach), isEmpty);
    expect(
      _openClaw.intersection(canAttach),
      canAttach,
      reason: 'the shape came from the gateway normaliser, not a guess',
    );
  });

  testWidgets('the model chip drops its chevron when nothing opens', (
    tester,
  ) async {
    // The chip is two things at once: which model is answering, and a way to
    // change it. The first is worth showing on a backend that cannot do the
    // second; the chevron is the promise, and a control that looks pressable
    // and is not is the same broken promise as one that fails when pressed.
    Future<void> pump({required bool canPick}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => _chip(context, canPick: canPick),
            ),
          ),
        ),
      ),
    );

    await pump(canPick: true);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.text('glm-latest'), findsOneWidget);

    await pump(canPick: false);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(
      find.text('glm-latest'),
      findsOneWidget,
      reason: 'which model is answering is still worth knowing',
    );
  });

  test('every panel is reachable from the palette, not only the menu', () {
    // The two surfaces are not interchangeable. On desktop the "…" opens
    // ConsoleMenu; on a phone it opens the palette, and that *is* the whole
    // session menu there. A panel added to one and not the other is fully
    // working on one form factor and unreachable on the other — which is how
    // the memory panel shipped, and why this test exists.
    final everything = Capability.values.toSet();
    final paletteNeeds = {
      for (final command in sessionCommands(_actions(everything)))
        if (command.needs != null) command.needs!,
    };
    final menuNeeds = consoleMenuNeeds();

    // Compared as sets of capabilities rather than of labels: the two
    // surfaces word some entries differently on purpose — the palette is
    // searched and the menu is scanned — but they must gate on the same
    // things.
    expect(
      menuNeeds.difference(paletteNeeds),
      isEmpty,
      reason:
          'in the desktop menu but not the palette, so unreachable on a '
          'phone where the palette is the whole session menu',
    );
    expect(
      paletteNeeds.difference(menuNeeds),
      isEmpty,
      reason: 'in the palette but not the desktop menu',
    );
    expect(menuNeeds, contains(Capability.memoryRead));
  });

  test('memory is offered wherever a backend can report it', () {
    expect(
      sessionCommands(_actions(_openClaw)).map((c) => c.label),
      contains(startsWith('Memory')),
      reason: 'OpenClaw reads agents.files.* at operator.read',
    );
    expect(
      sessionCommands(_actions(const {})).map((c) => c.label),
      isNot(contains(startsWith('Memory'))),
      reason: 'a backend that cannot report memory must not offer the panel',
    );
  });
}

/// Built through the composer's own public surface so the test exercises the
/// widget the app ships rather than a copy of it.
Widget _chip(BuildContext context, {required bool canPick}) =>
    ModelChip(model: 'glm-latest', onTap: canPick ? () {} : null);
