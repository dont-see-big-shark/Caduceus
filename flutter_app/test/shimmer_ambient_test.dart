/// The "Thinking 12s" shimmer is ambient motion, and ambient motion stops.
///
/// It was the one endless loop in the app that never asked: it called
/// `repeat()` in its initialiser and ran regardless of the reduce-motion
/// setting, of the degraded material, and of whether the list was being
/// dragged. Every other loop in the design honours `ambientAllowed`, and it is
/// only safe to let them stop because none of them is the sole carrier of any
/// information — the elapsed seconds are written out next to this one.
///
/// The consequence a test can actually catch: a never-settling animation makes
/// `pumpAndSettle` hang rather than fail, so any test that put a thinking turn
/// on screen and waited would time out.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/widgets/turn_timeline.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

/// The console consumes domain events; the fixture stays in Hermes'
/// vocabulary and goes through the app's own adapter, which is the path a
/// real frame takes.
AgentEvent _reasoning(String text) => agentEventFromHermes(
  's1',
  GatewayEvent(
    type: 'reasoning.delta',
    sessionId: 's1',
    payload: {'text': text},
  ),
)!;

Future<SessionConsole> _thinking(WidgetTester tester) async {
  final console = SessionConsole(persistedId: 's1', liveId: 's1');
  console.historyLoaded = true;
  console.handle(_reasoning('weighing it up'));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: console,
          builder: (context, _) => Column(
            children: [
              for (final turn in console.turns)
                TurnTimeline(console: console, turn: turn, isCurrent: true),
            ],
          ),
        ),
      ),
    ),
  );
  return console;
}

void main() {
  testWidgets('a thinking turn settles', (tester) async {
    await _thinking(tester);
    expect(find.textContaining('Thinking'), findsOneWidget);

    // The assertion is that this returns at all. With an unconditional
    // repeat() it never does, and the test dies on the suite timeout.
    await tester.pumpAndSettle();

    expect(find.textContaining('Thinking'), findsOneWidget);
  });

  testWidgets('the stopped pulse rests at full opacity', (tester) async {
    await _thinking(tester);
    await tester.pumpAndSettle();

    // Where a loop stops matters as much as that it stops. This one fades
    // between .35 and 1; frozen at .35 the dot reads as disabled, which is
    // the opposite of what it is there to say.
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('thinking-pulse')),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1.0);
  });
}
