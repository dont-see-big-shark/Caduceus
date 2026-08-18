/// A long think has to look different from a dead connection.
///
/// The complaint that prompted this: a turn spent nearly a minute reasoning
/// and the console showed a static `Reasoning · N chars` the whole time. There
/// was no elapsed time and no moving text, so "working" and "hung" rendered
/// identically.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/widgets/turn_timeline.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

/// The console consumes domain events. These fixtures stay written in Hermes'
/// vocabulary and go through the app's own adapter, which is the path a real
/// frame takes.
AgentEvent _agent(GatewayEvent event) =>
    agentEventFromHermes(event.sessionId ?? '', event)!;

AgentEvent _reasoning(String text) => _agent(
  GatewayEvent(
    type: 'reasoning.delta',
    sessionId: 's1',
    payload: {'text': text},
  ),
);

AgentEvent _answer(String text) => _agent(
  GatewayEvent(type: 'message.delta', sessionId: 's1', payload: {'text': text}),
);

AgentEvent _bare(String type) =>
    _agent(GatewayEvent(type: type, sessionId: 's1', payload: const {}));

void main() {
  AgentEvent toolStart(String id, String name) => _agent(
    GatewayEvent(
      type: 'tool.start',
      sessionId: 's1',
      payload: {'tool_id': id, 'name': name, 'context': 'ls -la'},
    ),
  );

  group('a corrected answer', () {
    // Only a backend that sends deltas and a cumulative snapshot both can
    // raise TextReset, so nothing here comes through the Hermes adapter.
    test('replaces this turn and keeps the conversation above it', () {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('first question');
      console.handle(_answer('an answer to the first'));
      console.handle(_bare('message.complete'));
      console.appendLocalPrompt('second question');
      console.handle(_answer('a wrong '));
      console.handle(_answer('second answer'));

      console.handle(
        const TextReset(sessionId: 's1', text: 'the right second answer'),
      );

      final text = console.markdown.text;
      expect(
        text,
        contains('an answer to the first'),
        reason: 'an hour of conversation must not be lost to one snapshot',
      );
      expect(text, contains('first question'));
      expect(text, contains('second question'));
      expect(text, contains('the right second answer'));
      expect(
        text,
        isNot(contains('a wrong second answer')),
        reason: 'words the agent never said may not stay on screen',
      );
    });

    test('with no answer yet, appends rather than truncating', () {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('go');
      console.handle(const TextReset(sessionId: 's1', text: 'server text'));

      expect(console.markdown.text, contains('go'));
      expect(console.markdown.text, contains('server text'));
    });
  });

  group('the collapsed preview of a thinking trace', () {
    const long =
        'The HEARTBEAT.md file is missing according to the project context, '
        'so there is nothing specific to check here and the right move is to '
        'reply with the acknowledgement and stop.';

    test('a live trace shows its newest line, tail first', () {
      final segment = ThinkingSegment(DateTime.now())..text.write(long);

      // Tail-first while a clock is running: that is where the movement is,
      // and watching it is how a long think reads as happening rather than
      // stuck.
      expect(segment.preview, startsWith('…'));
      expect(segment.preview, endsWith('stop.'));
    });

    test('a restored trace shows its first line, head first', () {
      final segment = ThinkingSegment.restored(long);

      // Nothing is moving and the reader is skimming. A trace that opens
      // mid-word behind an ellipsis reads as damage.
      expect(segment.preview, isNot(startsWith('…')));
      expect(segment.preview, startsWith('The HEARTBEAT.md file is missing'));
      expect(segment.preview, endsWith('…'));
    });

    test('a short restored trace is shown whole', () {
      expect(
        ThinkingSegment.restored('checked, nothing to do').preview,
        'checked, nothing to do',
      );
    });
  });

  group('turn state', () {
    test('sending a prompt starts the thinking clock', () {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      expect(console.isThinking, isFalse);

      console.appendLocalPrompt('hello');
      expect(
        console.isThinking,
        isTrue,
        reason:
            'the wait starts when the prompt goes out, not when the '
            'first reasoning token happens to arrive',
      );
      console.dispose();
    });

    test('reasoning before message.start still starts it', () {
      // The server emits reasoning.delta before message.start on this build,
      // so a turn that begins with a long think would otherwise show nothing.
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.handle(_reasoning('let me look at the config'));
      expect(console.isThinking, isTrue);
      console.dispose();
    });

    test('the first answer token stops the clock and keeps the figure', () {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('hello');
      console.handle(_reasoning('thinking about it'));
      expect(console.isThinking, isTrue);

      console.handle(_answer('Here'));
      expect(
        console.isThinking,
        isFalse,
        reason: 'answer text means the thinking phase is over',
      );
      expect(console.answerStarted, isTrue);
      // Frozen, not still counting.
      final first = console.thinkingElapsed;
      expect(console.thinkingElapsed, first);
      console.dispose();
    });

    test('a finished turn is kept, not erased by the next prompt', () {
      // Sending a second prompt used to discard the first turn's record
      // entirely: which tool ran, what it printed, how long the model thought
      // about it. "What did it actually do last time" had no answer.
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('first');
      console.handle(_reasoning('thinking about the first'));
      console.handle(toolStart('t1', 'terminal'));
      console.handle(_answer('done'));
      console.handle(_bare('message.complete'));

      console.appendLocalPrompt('second');
      expect(console.turns, hasLength(2));
      expect(
        console.turns.first.entries,
        hasLength(2),
        reason: "the first turn's thinking and tool are still there",
      );
      expect(
        console.timeline,
        isEmpty,
        reason: 'the current turn starts clean',
      );
      console.dispose();
    });

    test('retained turns are capped, and the drop is counted', () {
      // A day-long session would otherwise hold every reasoning trace it ever
      // produced.
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      for (var i = 0; i < SessionConsole.maxRetainedTurns + 3; i++) {
        console.appendLocalPrompt('prompt $i');
        console.handle(_reasoning('thought $i'));
        console.handle(_bare('message.complete'));
      }
      expect(console.turns, hasLength(SessionConsole.maxRetainedTurns));
      expect(
        console.forgottenTurns,
        3,
        reason: 'dropped turns are counted so the UI can say so',
      );
      console.dispose();
    });

    test('reasoning is scoped to the turn, not the session', () {
      // A session-wide buffer answers a question nobody asks. What matters is
      // what the model is thinking now.
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('first');
      console.handle(_reasoning('first turn thoughts'));
      console.handle(_answer('answer one'));
      console.handle(_bare('message.complete'));
      expect(console.reasoning.toString(), contains('first turn'));

      console.appendLocalPrompt('second');
      expect(
        console.reasoning.toString(),
        isEmpty,
        reason: "the new turn must not show the previous turn's reasoning",
      );
      console.dispose();
    });

    test('the preview is the newest line, not the oldest', () {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.handle(_reasoning('first line\nsecond line\n'));
      console.handle(_reasoning('newest line'));
      expect(console.reasoningPreview, 'newest line');
      console.dispose();
    });

    test('thinking, a tool, then thinking again is three entries', () {
      // The shape the client has to reproduce: reason, run something, reason
      // about what it printed. Two panes cannot express that at all.
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('go');
      console.handle(_reasoning('I should list the directory'));
      console.handle(toolStart('t1', 'terminal'));
      console.handle(_reasoning('that output is surprising'));

      expect(console.timeline, hasLength(3));
      expect(console.timeline[0], isA<ThinkingSegment>());
      expect(console.timeline[1], isA<ToolEntry>());
      expect(console.timeline[2], isA<ThinkingSegment>());

      // The first segment is closed by the tool and keeps its duration; the
      // second is still running.
      expect((console.timeline[0] as ThinkingSegment).open, isFalse);
      expect((console.timeline[2] as ThinkingSegment).open, isTrue);
      console.dispose();
    });

    test('a tool with no reasoning around it still lands in order', () {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('go');
      console.handle(toolStart('t1', 'terminal'));
      console.handle(toolStart('t2', 'read'));
      expect(console.timeline.map((e) => (e as ToolEntry).toolId), [
        't1',
        't2',
      ]);
      console.dispose();
    });

    test(
      'a model that only sends reasoning.available still shows thinking',
      () {
        // Some models deliver the whole trace in one frame instead of streaming
        // it. Handling only the delta channel showed them as having thought
        // nothing at all.
        final console = SessionConsole(persistedId: 's1', liveId: 's1');
        console.appendLocalPrompt('go');
        console.handle(
          _agent(
            GatewayEvent(
              type: 'reasoning.available',
              sessionId: 's1',
              payload: const {'text': 'the whole trace at once'},
            ),
          ),
        );
        expect(console.reasoning.toString(), 'the whole trace at once');
        expect(console.timeline, hasLength(1));
        console.dispose();
      },
    );

    test('a streamed trace is not doubled by the block that follows it', () {
      // The live server sends both: 13 reasoning.delta frames and then one
      // reasoning.available restating them. Appending both duplicates it.
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('go');
      console.handle(_reasoning('streamed thought'));
      console.handle(
        _agent(
          GatewayEvent(
            type: 'reasoning.available',
            sessionId: 's1',
            payload: const {'text': 'streamed thought'},
          ),
        ),
      );
      expect(console.reasoning.toString(), 'streamed thought');
      console.dispose();
    });

    test('a tool that returns plain text still shows its output', () {
      // The server does json.loads(result) and falls back to the raw string.
      // Reading only the Map shape showed nothing at all for those tools.
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.handle(
        _agent(
          GatewayEvent(
            type: 'tool.complete',
            sessionId: 's1',
            payload: const {
              'tool_id': 't1',
              'name': 'read',
              'duration_s': 0.2,
              'result': 'the file contents',
            },
          ),
        ),
      );
      expect(console.tools['t1']!.output, 'the file contents');
      console.dispose();
    });

    test("falls back to the server's summary when there is no output", () {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.handle(
        _agent(
          GatewayEvent(
            type: 'tool.complete',
            sessionId: 's1',
            payload: const {
              'tool_id': 't2',
              'name': 'edit',
              'duration_s': 0.1,
              'summary': 'edited 3 lines in main.dart',
            },
          ),
        ),
      );
      expect(console.tools['t2']!.output, 'edited 3 lines in main.dart');
      console.dispose();
    });

    test('a completion with no start still appears', () {
      // A reconnect landing mid-tool delivers tool.complete on its own.
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.handle(
        _agent(
          GatewayEvent(
            type: 'tool.complete',
            sessionId: 's1',
            payload: const {
              'tool_id': 'orphan',
              'name': 'terminal',
              'duration_s': 1.0,
              'result': {'output': '', 'exit_code': 0},
            },
          ),
        ),
      );
      expect(
        console.timeline,
        hasLength(1),
        reason: 'a result the user never saw start must not vanish',
      );
      console.dispose();
    });

    test('session.info carries more than the model', () {
      // approval_mode and yolo decide whether this session stops to ask before
      // running something destructive. Reading only `model` left that off
      // screen entirely.
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.handle(
        _agent(
          GatewayEvent(
            type: 'session.info',
            sessionId: 's1',
            payload: const {
              'model': 'a-model',
              'approval_mode': 'auto',
              'yolo': true,
              'cwd': '/srv/app',
              'branch': 'main',
              'config_warning': 'no provider credentials found',
            },
          ),
        ),
      );
      expect(console.model, 'a-model');
      expect(console.approvalMode, 'auto');
      expect(
        console.unattended,
        isTrue,
        reason: 'the user has to be able to tell that nothing will ask',
      );
      expect(console.configWarning, 'no provider credentials found');
      expect(console.cwd, '/srv/app');
      expect(console.branch, 'main');
      console.dispose();
    });

    test('a normal session is not flagged as unattended', () {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.handle(
        _agent(
          GatewayEvent(
            type: 'session.info',
            sessionId: 's1',
            payload: const {
              'model': 'm',
              'approval_mode': 'smart',
              'yolo': false,
            },
          ),
        ),
      );
      expect(console.unattended, isFalse);
      expect(console.configWarning, isNull);
      console.dispose();
    });

    test('a failed turn stops the clock', () {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('hello');
      console.setError('connection lost');
      expect(
        console.isThinking,
        isFalse,
        reason: 'a spinner that runs forever after a failure is a lie',
      );
      console.dispose();
    });
  });

  group('pane', () {
    Future<void> pump(WidgetTester tester, SessionConsole console) =>
        tester.pumpWidget(
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

    testWidgets('shows a running counter while thinking', (tester) async {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('hello');
      console.handle(_reasoning('checking the manifest'));
      await pump(tester, console);

      expect(find.textContaining('Thinking'), findsOneWidget);
      // Expanded while thinking: the reasoning is the only thing happening.
      expect(find.textContaining('checking the manifest'), findsOneWidget);
      // A breathing dot rather than a spinner: thinking can run for minutes,
      // and a spinner at that duration reads as a hang.
      expect(find.byKey(const ValueKey('thinking-pulse')), findsOneWidget);

      console.dispose();
    });

    testWidgets('switches to a final figure once the answer starts', (
      tester,
    ) async {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('hello');
      console.handle(_reasoning('some thought'));
      console.handle(_answer('The answer'));
      await pump(tester, console);
      await tester.pump();

      expect(find.textContaining('Thought for'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('thinking-pulse')),
        findsNothing,
        reason: 'a live indicator after the answer has started is wrong',
      );
      console.dispose();
    });

    testWidgets('collapsing keeps a live tail visible', (tester) async {
      // Collapsed, the tail is the only evidence anything is happening, so it
      // must not be hidden behind the disclosure.
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('hello');
      console.handle(_reasoning('inspecting the lockfile'));
      await pump(tester, console);

      await tester.tap(find.textContaining('Thinking'));
      // Not pumpAndSettle: the thinking spinner animates forever by design.
      await tester.pump();

      expect(find.text('inspecting the lockfile'), findsOneWidget);
      console.dispose();
    });

    testWidgets('the user\'s choice survives new tokens', (tester) async {
      final console = SessionConsole(persistedId: 's1', liveId: 's1');
      console.appendLocalPrompt('hello');
      console.handle(_reasoning('one'));
      await pump(tester, console);

      await tester.tap(find.textContaining('Thinking'));
      await tester.pump();
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);

      console.handle(_reasoning(' two'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byIcon(Icons.expand_more_rounded),
        findsOneWidget,
        reason:
            'a pane that reopens itself under the user is worse than '
            'one that never opened',
      );
      console.dispose();
    });
  });
}
