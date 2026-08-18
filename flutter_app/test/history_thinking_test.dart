/// Leaving a conversation and coming back must not lose its thinking.
///
/// Reported from the phone: navigate out, navigate in, and every thinking
/// block is gone. The server keeps each assistant message's reasoning;
/// loadHistory poured all of it into one session-wide buffer that nothing
/// rendered, and built no turns at all.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

/// Written in the wire's vocabulary and mapped through the app's own adapter,
/// which is the path a real transcript takes.
AgentMessage _user(String text) =>
    agentMessageFromHermes(SessionMessage(role: 'user', text: text));

AgentMessage _assistant(String text, {String? reasoning}) =>
    agentMessageFromHermes(
      SessionMessage(role: 'assistant', text: text, reasoning: reasoning),
    );

void main() {
  test('a resumed conversation keeps the thinking for every exchange', () {
    final console = SessionConsole(persistedId: 's1', liveId: 'l1');

    console.loadHistory([
      _user('first question'),
      _assistant('first answer', reasoning: 'weighing the first'),
      _user('second question'),
      _assistant('second answer', reasoning: 'weighing the second'),
      _user('third question'),
      _assistant('third answer', reasoning: 'weighing the third'),
    ]);

    expect(
      console.turns,
      hasLength(3),
      reason: 'one per exchange that had reasoning',
    );

    final traces = console.turns
        .map(
          (t) => t.entries.whereType<ThinkingSegment>().single.text.toString(),
        )
        .toList();
    expect(traces, [
      'weighing the first',
      'weighing the second',
      'weighing the third',
    ]);

    console.dispose();
  });

  test('each restored turn anchors under its own question', () {
    final console = SessionConsole(persistedId: 's1', liveId: 'l1');
    console.loadHistory([
      _user('q1'),
      _assistant('a1', reasoning: 'r1'),
      _user('q2'),
      _assistant('a2', reasoning: 'r2'),
    ]);

    final anchors = console.turns.map((t) => t.anchorBlock).toList();
    expect(
      anchors.toSet(),
      hasLength(2),
      reason: 'two turns sharing an anchor would stack in one place',
    );
    expect(anchors.first, lessThan(anchors.last));

    console.dispose();
  });

  test('a restored segment does not claim a duration nobody measured', () {
    // The server stores what was thought, not how long it took.
    final console = SessionConsole(persistedId: 's1', liveId: 'l1');
    console.loadHistory([
      _user('q'),
      _assistant('a', reasoning: 'some reasoning'),
    ]);

    final segment = console.turns.single.entries
        .whereType<ThinkingSegment>()
        .single;
    expect(segment.durationKnown, isFalse);
    expect(segment.open, isFalse, reason: 'it is finished, not still running');

    console.dispose();
  });

  test('exchanges without reasoning produce no empty blocks', () {
    final console = SessionConsole(persistedId: 's1', liveId: 'l1');
    console.loadHistory([
      _user('q1'),
      _assistant('a1'),
      _user('q2'),
      _assistant('a2', reasoning: '   '),
    ]);
    expect(
      console.turns,
      isEmpty,
      reason: 'a blank trace is not a thinking block',
    );
    console.dispose();
  });

  test('two answers to one question each keep their own trace in order', () {
    // One question with several answers is ordinary — that is what a tool call
    // looks like once it is written down. Anchoring every trace to the
    // question put the *second* answer's thinking above the *first* answer.
    final console = SessionConsole(persistedId: 's1', liveId: 'l1');

    console.loadHistory([
      _user('one question'),
      _assistant('first answer', reasoning: 'weighing the first'),
      _assistant('second answer', reasoning: 'weighing the second'),
    ]);

    expect(console.turns, hasLength(2));
    final anchors = console.turns.map((t) => t.anchorBlock).toList();
    expect(
      anchors[1],
      greaterThan(anchors[0]),
      reason:
          'the later trace belongs further down the transcript, not '
          'above the answer that preceded it',
    );
    console.dispose();
  });

  test('a turn that only thought is not dropped', () {
    // A message with no text at all used to be skipped before its reasoning
    // was ever read — losing the whole trace of a turn that thought and then
    // said nothing, which is the turn a reader most wants explained.
    final console = SessionConsole(persistedId: 's1', liveId: 'l1');

    console.loadHistory([
      _user('anything to do?'),
      _assistant('', reasoning: 'nothing needs attention'),
    ]);

    expect(console.turns, hasLength(1));
    final segment = console.turns.single.entries.single as ThinkingSegment;
    expect(segment.text.toString(), contains('nothing needs attention'));
    console.dispose();
  });
}
