/// Each question keeps its own thinking, under itself.
///
/// Reported from the phone: the previous turn appeared folded inside the
/// current turn's block as "Earlier turn · thought 7s", and scrolling back
/// through history showed no thinking at all. One widget held every turn and
/// rendered at the tail, so every turn's record piled under the newest
/// question.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/workspace.dart';
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
  test('every turn remembers where its question sits', () {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');

    console.appendLocalPrompt('first question');
    console.handle(_e('reasoning.delta', {'text': 'thinking about the first'}));
    console.handle(_e('message.delta', {'text': 'first answer\n\n'}));
    console.handle(_e('message.complete'));
    final firstAnchor = console.turns.first.anchorBlock;

    console.appendLocalPrompt('second question');
    console.handle(
      _e('reasoning.delta', {'text': 'thinking about the second'}),
    );

    expect(console.turns, hasLength(2));
    expect(
      console.turns.last.anchorBlock,
      greaterThan(firstAnchor),
      reason: 'the second turn anchors further down the transcript',
    );

    // Each turn's reasoning stays with that turn.
    final first = console.turns.first.entries.whereType<ThinkingSegment>();
    final second = console.turns.last.entries.whereType<ThinkingSegment>();
    expect(first.single.text.toString(), contains('the first'));
    expect(second.single.text.toString(), contains('the second'));
    expect(
      second.single.text.toString(),
      isNot(contains('the first')),
      reason: 'a turn must not absorb the previous turn is reasoning',
    );

    console.dispose();
  });

  test('anchors are distinct, so two turns cannot render in one place', () {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    for (var i = 0; i < 4; i++) {
      console.appendLocalPrompt('question $i');
      console.handle(_e('reasoning.delta', {'text': 'thought $i'}));
      console.handle(_e('message.delta', {'text': 'answer $i\n\n'}));
      console.handle(_e('message.complete'));
    }

    final anchors = console.turns.map((t) => t.anchorBlock).toList();
    expect(
      anchors.toSet(),
      hasLength(anchors.length),
      reason: 'two turns sharing an anchor would stack in one spot',
    );
    expect(
      anchors,
      orderedEquals(List.of(anchors)..sort()),
      reason: 'anchors advance with the transcript',
    );

    console.dispose();
  });

  test('a turn with no prompt of its own still anchors somewhere valid', () {
    // Resuming a session that is already mid-turn: reasoning arrives with no
    // local prompt appended first.
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.handle(_e('reasoning.delta', {'text': 'already running'}));
    expect(console.turns, hasLength(1));
    expect(
      console.turns.single.anchorBlock,
      greaterThanOrEqualTo(-1),
      reason:
          '-1 means "before any block", which the view handles by '
          'rendering at the tail instead',
    );
    console.dispose();
  });
}
