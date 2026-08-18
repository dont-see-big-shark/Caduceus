/// Reasoning must repaint like a display, not like a counter.
///
/// The server delivers a short trace as a burst — 91 frames inside 892 ms was
/// measured against the reference server. At the 250 ms cadence the counters
/// use, that burst produced three repaints, which reads as "the thinking
/// appeared all at once at the end". The answer text never had the problem
/// because it bypasses the console and drives its own renderer.
library;

import 'package:caduceus/widgets/turn_timeline.dart';
import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

/// The console consumes domain events. These fixtures stay written in Hermes'
/// vocabulary and go through the app's own adapter, which is the path a real
/// frame takes.
AgentEvent _agent(GatewayEvent event) =>
    agentEventFromHermes(event.sessionId ?? '', event)!;

void main() {
  testWidgets('a burst of reasoning repaints many times, not three', (
    tester,
  ) async {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.historyLoaded = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: console,
            builder: (c, _) => TurnTimeline(
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

    int rendered() {
      final texts = tester.widgetList<SelectableText>(
        find.byType(SelectableText),
      );
      return texts.isEmpty ? 0 : (texts.first.data ?? '').length;
    }

    // 90 frames over ~900 ms, the shape the real server produced.
    final distinct = <int>{};
    for (var i = 0; i < 90; i++) {
      console.handle(
        _agent(
          GatewayEvent(
            type: 'reasoning.delta',
            sessionId: 's1',
            payload: {'text': 'w$i '},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      distinct.add(rendered());
    }

    // At 250 ms this was 3-4 distinct states across the whole burst.
    expect(
      distinct.length,
      greaterThan(10),
      reason:
          'the trace must visibly grow during the burst, not land in '
          'three jumps',
    );
    console.dispose();
  });

  testWidgets('answer-token counters stay on the slow cadence', (tester) async {
    // The reason the slow path exists: per-token chrome rebuilds are what the
    // incremental renderer was built to avoid.
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    var notifications = 0;
    console.addListener(() => notifications++);

    for (var i = 0; i < 300; i++) {
      console.handle(
        _agent(
          GatewayEvent(
            type: 'message.delta',
            sessionId: 's1',
            payload: {'text': 'tok$i '},
          ),
        ),
      );
    }
    // One immediate notification: the thinking-to-answering transition.
    expect(notifications, 1);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      notifications,
      lessThan(5),
      reason: '300 answer tokens must not become 300 rebuilds',
    );
    console.dispose();
  });
}
