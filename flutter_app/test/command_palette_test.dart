/// ⌘K — the way into every session action.
///
/// The palette is now the only route to several of these on a phone, so
/// "it opens" is not the interesting claim: what matters is that it filters,
/// that the keyboard drives it, that a disabled action cannot be run, and that
/// it closes *before* the thing it opened.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/widgets/command_palette.dart';
import 'package:caduceus/widgets/console_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ConsoleActions _actions({
  bool streaming = false,
  VoidCallback? onUndo,
  VoidCallback? onBranch,
  Set<Capability>? capabilities,
}) => ConsoleActions(
  streaming: streaming,
  // Everything, unless a test is specifically about a backend that cannot.
  supports: (c) => capabilities?.contains(c) ?? true,
  onSetCwd: () {},
  onUndo: onUndo ?? () {},
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
  onBranch: onBranch ?? () {},
  onShowStats: () {},
);

Future<void> _open(WidgetTester tester, List<Command> commands) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showCommandPalette(context, commands),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('filters as you type', (tester) async {
    await _open(tester, sessionCommands(_actions()));
    await tester.enterText(find.byType(TextField).last, 'check');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('File checkpoints…'), findsOneWidget);
  });

  testWidgets('matches what people call things, not only what they are '
      'named', (tester) async {
    // "revert" is nowhere in the label. Someone reaching for ⌘K has a verb in
    // mind, not the menu wording, and a palette that only matches its own
    // labels is a palette you have to already know.
    await _open(tester, sessionCommands(_actions()));
    await tester.enterText(find.byType(TextField).last, 'revert');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Undo last exchange'), findsOneWidget);
  });

  testWidgets('arrow keys and enter run the highlighted command', (
    tester,
  ) async {
    var branched = false;
    final commands = sessionCommands(_actions(onBranch: () => branched = true));
    await _open(tester, commands);

    await tester.enterText(find.byType(TextField).last, 'branch');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(branched, isTrue);
  });

  testWidgets('a disabled command does nothing', (tester) async {
    // Undo is unavailable mid-turn: the server would drop an exchange that is
    // still being written. Greying it out is not enough — it must not fire.
    var undone = false;
    final commands = sessionCommands(
      _actions(streaming: true, onUndo: () => undone = true),
    );
    await _open(tester, commands);

    await tester.tap(find.text('Undo last exchange'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(undone, isFalse, reason: 'undo is not available while streaming');
    expect(
      find.text('Undo last exchange'),
      findsOneWidget,
      reason: 'and the palette stays open rather than silently closing',
    );
  });

  testWidgets('closes itself before the panel it opens', (tester) async {
    // Several commands open a dialog. Leaving the palette underneath means
    // dismissing twice to get back to the conversation.
    var opened = 0;
    await _open(tester, [Command(label: 'Open a panel', run: () => opened++)]);

    await tester.tap(find.text('Open a panel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(opened, 1);
    expect(find.text('Type a command…'), findsNothing);
  });

  testWidgets('escape closes it', (tester) async {
    await _open(tester, sessionCommands(_actions()));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Type a command…'), findsNothing);
  });

  testWidgets('a phone can pull the sheet down to dismiss it', (tester) async {
    // 支持下拉关闭. On a phone the palette rises from the bottom, so pulling it
    // back down is the gesture the hand is already in position for.
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _open(tester, sessionCommands(_actions()));
    expect(find.text('Type a command…'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('palette-handle')),
      const Offset(0, 200),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Type a command…'), findsNothing);
  });

  testWidgets('a short tug springs back instead', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _open(tester, sessionCommands(_actions()));
    // Slowly, so it is distance and not velocity being judged.
    await tester.timedDrag(
      find.byKey(const ValueKey('palette-handle')),
      const Offset(0, 30),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Type a command…'),
      findsOneWidget,
      reason: 'half a gesture is not a dismissal',
    );
  });

  testWidgets('says so when nothing matches', (tester) async {
    await _open(tester, sessionCommands(_actions()));
    await tester.enterText(find.byType(TextField).last, 'zzzz');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Nothing matches'), findsOneWidget);
  });
}
