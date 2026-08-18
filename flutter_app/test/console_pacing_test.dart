/// Per-token work must not become per-token rebuilds.
///
/// The renderer's whole value is that a settled block is parsed once. If the
/// surrounding chrome — header counters, reasoning pane, sidebar — rebuilt on
/// every `message.delta`, that saving would be spent again on widget rebuilds.
///
/// These tests pin the pacing so it cannot silently regress.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/workspace.dart';

/// The console consumes domain events. These fixtures stay written in Hermes'
/// vocabulary and go through the app's own adapter, which is the path a real
/// frame takes.
AgentEvent _agent(GatewayEvent event) =>
    agentEventFromHermes(event.sessionId ?? '', event)!;

AgentEvent delta(String text, {String session = 's1'}) => _agent(
  GatewayEvent(
    type: 'message.delta',
    sessionId: session,
    payload: {'text': text},
  ),
);

AgentEvent reasoning(String text, {String session = 's1'}) => _agent(
  GatewayEvent(
    type: 'reasoning.delta',
    sessionId: session,
    payload: {'text': text},
  ),
);

void main() {
  test('a burst of tokens does not produce a notification per token', () async {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    var notifications = 0;
    console.addListener(() => notifications++);

    for (var i = 0; i < 300; i++) {
      console.handle(delta('tok$i '));
    }

    // One, not zero and not three hundred: the *first* answer token ends the
    // thinking phase, and that transition has to reach the UI immediately —
    // holding it for 250 ms leaves a spinner and a "Thinking 12s" counter on
    // screen while the answer is already arriving underneath them. Every
    // token after the first is coalesced as before.
    expect(
      notifications,
      1,
      reason: '300 tokens must not trigger 300 rebuilds',
    );
    expect(console.deltaCount, 300, reason: 'counters still advance');

    // ...but the counter must not look frozen either.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(
      notifications,
      greaterThan(0),
      reason: 'stats must reach the UI within a fraction of a second',
    );
    expect(
      notifications,
      lessThan(5),
      reason: 'one coalesced notification, not a stream of them',
    );

    console.dispose();
  });

  test('reasoning deltas are coalesced the same way', () async {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    var notifications = 0;
    console.addListener(() => notifications++);

    for (var i = 0; i < 200; i++) {
      console.handle(reasoning('think '));
    }
    expect(notifications, 0);
    expect(console.reasoning.length, 200 * 'think '.length);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(notifications, inInclusiveRange(1, 4));
    console.dispose();
  });

  test('discrete events notify immediately', () {
    // Tool and approval frames are low-frequency and user-visible; delaying
    // them by 250 ms would make the UI feel laggy for no benefit.
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    var notifications = 0;
    console.addListener(() => notifications++);

    console.handle(
      _agent(
        GatewayEvent(
          type: 'tool.start',
          sessionId: 's1',
          payload: const {'tool_id': 't1', 'name': 'terminal', 'context': 'ls'},
        ),
      ),
    );
    expect(notifications, 1);

    console.handle(
      _agent(
        GatewayEvent(
          type: 'tool.complete',
          sessionId: 's1',
          payload: const {
            'tool_id': 't1',
            'name': 'terminal',
            'duration_s': 0.09,
            'result': {'output': 'a\nb', 'exit_code': 0},
          },
        ),
      ),
    );
    expect(notifications, 2);
    expect(console.tools['t1']!.done, isTrue);
    expect(console.tools['t1']!.failed, isFalse);

    console.dispose();
  });

  test('a failed tool is distinguishable from a successful one', () {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.handle(
      _agent(
        GatewayEvent(
          type: 'tool.complete',
          sessionId: 's1',
          payload: const {
            'tool_id': 't9',
            'name': 'terminal',
            'duration_s': 1.0,
            'result': {'output': '', 'exit_code': 127, 'error': 'not found'},
          },
        ),
      ),
    );
    expect(console.tools['t9']!.failed, isTrue);
    console.dispose();
  });

  test('disposing mid-stream does not fire a pending notification', () async {
    // The coalescing timer outlives a rapid open/close otherwise, and firing
    // after dispose throws.
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.handle(delta('x'));
    console.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Reaching here without an exception is the assertion.
  });
}
