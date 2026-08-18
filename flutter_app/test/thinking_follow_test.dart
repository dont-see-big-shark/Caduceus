/// A growing thinking pane has to pull the view down too.
///
/// The transcript follows its own tail, but the reasoning renders inside the
/// list as a widget attached to a settled block — it grows without the
/// Markdown controller changing at all, so nothing told the list to scroll.
/// During a long think with no answer text yet, that means the newest
/// reasoning is written off the bottom of the screen.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/widgets/turn_timeline.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

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

void main() {
  testWidgets('reasoning growing under the prompt keeps itself in view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.historyLoaded = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: console,
            // ConsoleView does this for real; the test wires the same hook so
            // it measures the mechanism rather than the whole screen.
            builder: (context, _) {
              console.markdown.requestFollow();
              return StreamingMarkdownView(
                controller: console.markdown,
                afterBlock: (index) {
                  final turn = console.turns
                      .where((t) => t.anchorBlock == index)
                      .firstOrNull;
                  if (turn == null) return null;
                  return TurnTimeline(
                    console: console,
                    turn: turn,
                    isCurrent: true,
                  );
                },
              );
            },
          ),
        ),
      ),
    );

    // Enough transcript that the list actually scrolls.
    for (var i = 0; i < 12; i++) {
      console.markdown.append('Earlier paragraph number $i.\n\n');
    }
    console.appendLocalPrompt('a question');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A long think, no answer yet — the case the report describes.
    for (var i = 0; i < 60; i++) {
      console.handle(_reasoning('reasoning line $i, long enough to wrap.\n'));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 300));

    final position = console.markdown.scrollController.position;
    expect(
      position.pixels,
      0,
      reason: 'the newest reasoning must stay on screen while it is written',
    );

    console.dispose();
  });
}
