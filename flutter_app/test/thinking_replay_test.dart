/// Replays the exact frame sequence a real turn produced.
///
/// Captured from the reference server on 2026-08-02 by asking it a question
/// that forces multi-step reasoning. The order and the payload shapes are
/// verbatim; the counts are reduced. Every earlier thinking test fed the
/// events I *expected*, which is how a display that shows nothing can still
/// pass a suite:
///
///   message.start       payload: null
///   thinking.delta ×3   {"text":"◉_◉ cogitating..."}
///   reasoning.delta ×269 {"text":"Let"} …
///   message.delta ×171  {"text":"#"} …          ← interleaved with the above
///   reasoning.available {"text":"# Step-by-step\n\n| Step | …"}
///   message.complete    {"text":"# Step-by-step\n\n| Step | …"}
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
AgentEvent _e(String type, [Map<String, dynamic>? payload]) =>
    agentEventFromHermes(
      's1',
      GatewayEvent(type: type, sessionId: 's1', payload: payload ?? const {}),
    )!;

void main() {
  testWidgets('a real turn shows its reasoning while it is being written', (
    tester,
  ) async {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.historyLoaded = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: console,
            builder: (context, _) => TurnTimeline(
              console: console,
              turn: console.turns.isEmpty
                  ? Turn(anchorBlock: 0)
                  : console.turns.last,
              isCurrent: true,
            ),
          ),
        ),
      ),
    );

    console.appendLocalPrompt('A farmer has 17 sheep…');
    console.handle(_e('message.start'));
    // The server's own spinner label, delivered on the thinking channel.
    for (var i = 0; i < 3; i++) {
      console.handle(_e('thinking.delta', {'text': '◉_◉ cogitating...'}));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Real reasoning, one word per frame.
    for (final word in ['Let', ' me', ' work', ' through', ' the', ' sheep']) {
      console.handle(_e('reasoning.delta', {'text': word}));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('work through the sheep'),
      findsOneWidget,
      reason:
          'the reasoning has to be on screen while it is arriving — '
          'this is the whole complaint',
    );

    // The spinner label belongs on screen — as the status line explaining the
    // wait — but never *inside* the reasoning. Asserting it is absent
    // entirely was wrong: that is the channel that says why a 57-second wait
    // is taking 57 seconds.
    expect(
      console.reasoning.toString(),
      isNot(contains('cogitating')),
      reason: "the server's status line is not something the model thought",
    );
    expect(
      find.textContaining('cogitating'),
      findsOneWidget,
      reason: 'it is shown, as status, beside the clock counting the wait',
    );
    expect(
      find.textContaining('cogitatingLet me work'),
      findsNothing,
      reason: 'and it is not concatenated into the reasoning body',
    );

    console.dispose();
  });

  testWidgets('reasoning that continues after the answer starts still shows', (
    tester,
  ) async {
    // The capture interleaves 269 reasoning.delta with 171 message.delta, so
    // reasoning keeps arriving *after* the first answer token.
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.historyLoaded = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: console,
            builder: (context, _) => TurnTimeline(
              console: console,
              turn: console.turns.isEmpty
                  ? Turn(anchorBlock: 0)
                  : console.turns.last,
              isCurrent: true,
            ),
          ),
        ),
      ),
    );

    console.appendLocalPrompt('go');
    console.handle(_e('message.start'));
    console.handle(_e('reasoning.delta', {'text': 'first thought'}));
    console.handle(_e('message.delta', {'text': '#'}));
    console.handle(_e('reasoning.delta', {'text': ' and a later one'}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('and a later one'),
      findsOneWidget,
      reason: 'reasoning does not stop when the answer starts',
    );

    console.dispose();
  });

  test('the spinner label never reaches the reasoning buffer', () {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.appendLocalPrompt('go');
    console.handle(_e('thinking.delta', {'text': '◉_◉ cogitating...'}));
    console.handle(_e('reasoning.delta', {'text': 'real thought'}));
    expect(console.reasoning.toString(), 'real thought');
    console.dispose();
  });
}
