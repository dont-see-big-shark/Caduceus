/// A question belongs to the exchange that asked it.
///
/// Blocking prompts used to render as a banner pinned above the transcript.
/// With more than one turn on screen that banner could not say which question
/// it belonged to, and it pushed the conversation down rather than being part
/// of it — the answer arrived detached from what prompted it.
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
AgentEvent _e(String type, Map<String, dynamic> payload) =>
    agentEventFromHermes(
      's1',
      GatewayEvent(type: type, sessionId: 's1', payload: payload),
    )!;

void main() {
  test('a question lands in the turn that asked it, in order', () {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.appendLocalPrompt('teach me japanese');
    console.handle(_e('reasoning.delta', {'text': 'I should ask what level'}));
    console.handle(
      _e('clarify.request', {
        'request_id': 'r1',
        'prompt': 'Which level are you at?',
        'choices': ['N5', 'N4'],
      }),
    );

    expect(console.timeline, hasLength(2));
    expect(console.timeline[0], isA<ThinkingSegment>());
    expect(console.timeline[1], isA<PromptEntry>());
    expect(
      (console.timeline[0] as ThinkingSegment).open,
      isFalse,
      reason: 'asking a question ends the thinking that led to it',
    );
    console.dispose();
  });

  test("a second turn's question does not join the first turn", () {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.appendLocalPrompt('first');
    console.handle(
      _e('clarify.request', {'request_id': 'r1', 'prompt': 'first question'}),
    );
    console.handle(_e('message.complete', const {}));

    console.appendLocalPrompt('second');
    console.handle(
      _e('clarify.request', {'request_id': 'r2', 'prompt': 'second question'}),
    );

    expect(console.turns, hasLength(2));
    expect(
      console.turns.first.entries
          .whereType<PromptEntry>()
          .single
          .prompt
          .question,
      'first question',
    );
    expect(
      console.turns.last.entries
          .whereType<PromptEntry>()
          .single
          .prompt
          .question,
      'second question',
    );
    console.dispose();
  });

  testWidgets('the question renders inside its turn with its choices', (
    tester,
  ) async {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.appendLocalPrompt('teach me japanese');
    console.handle(
      _e('clarify.request', {
        'request_id': 'r1',
        'prompt': 'Which level are you at?',
        'choices': ['N5 basics', 'N4 grammar'],
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: console,
            builder: (context, _) => SingleChildScrollView(
              child: TurnTimeline(
                console: console,
                turn: console.turns.last,
                isCurrent: true,
                onAnswerPrompt: (prompt, value) async => true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Which level are you at?'), findsOneWidget);
    expect(find.text('N5 basics'), findsOneWidget);
    expect(find.text('N4 grammar'), findsOneWidget);
    console.dispose();
  });

  testWidgets('a blocked turn can be abandoned instead of answered', (
    tester,
  ) async {
    // The server releases a blocking wait on "a real answer or
    // session.interrupt" and nothing else, so a question you do not want to
    // answer is a dead end without an exit offered here.
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.appendLocalPrompt('go');
    console.handle(
      _e('clarify.request', {
        'request_id': 'r1',
        'prompt': 'Which one?',
        'choices': ['A', 'B'],
      }),
    );

    var stopped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: console,
            builder: (context, _) => SingleChildScrollView(
              child: TurnTimeline(
                console: console,
                turn: console.turns.last,
                isCurrent: true,
                onAnswerPrompt: (prompt, value) async => true,
                onStop: () => stopped++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.textContaining("stop this turn"));
    await tester.pump();
    expect(stopped, 1);
    console.dispose();
  });

  testWidgets('a finished turn offers no stop', (tester) async {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.appendLocalPrompt('go');
    console.handle(
      _e('clarify.request', {'request_id': 'r1', 'prompt': 'Which one?'}),
    );
    console.removePrompt(console.prompts.single);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TurnTimeline(
              console: console,
              turn: console.turns.last,
              isCurrent: true,
              onAnswerPrompt: (prompt, value) async => true,
              onStop: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('stop this turn'),
      findsNothing,
      reason: 'stopping a turn that is not blocked does nothing',
    );
    console.dispose();
  });

  testWidgets('an answered question stops offering buttons', (tester) async {
    // It stays as a record of what was asked, but a choice that can no longer
    // be delivered must not look live.
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.appendLocalPrompt('go');
    console.handle(
      _e('clarify.request', {
        'request_id': 'r1',
        'prompt': 'Pick one',
        'choices': ['A'],
      }),
    );
    final asked = console.prompts.single;
    console.removePrompt(asked);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: console,
            builder: (context, _) => SingleChildScrollView(
              child: TurnTimeline(
                console: console,
                turn: console.turns.last,
                isCurrent: true,
                onAnswerPrompt: (prompt, value) async => true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('Pick one'),
      findsOneWidget,
      reason: 'the record of the question stays',
    );
    final button = tester.widgetList<FilledButton>(find.byType(FilledButton));
    expect(
      button.every((b) => b.onPressed == null),
      isTrue,
      reason: 'its choices are no longer live',
    );
    console.dispose();
  });
}
