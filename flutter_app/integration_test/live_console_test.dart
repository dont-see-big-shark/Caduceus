/// The real app, on macOS, against a real Hermes.
///
/// Everything else in this repo stops at a fake socket. This one launches the
/// actual binary, connects over the actual network, drives the actual widgets,
/// and asserts on what is on screen — which is the only way to catch the class
/// of bug that has bitten this project repeatedly: sandbox entitlements, plugin
/// registration, wire shapes, and UI wiring that unit tests on either side of
/// the seam both pass.
///
/// Needs a server, so it is not part of `flutter test`:
///
///   flutter test integration_test/live_console_test.dart -d macos \
///     --dart-define=SERVER_URL=... --dart-define=TOKEN=...
///
/// Without those defines it skips rather than fails — a red suite that only
/// means "no server today" trains people to ignore it.
library;

import 'package:caduceus/console_view.dart';
import 'package:caduceus/workspace.dart';
import 'package:caduceus/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:integration_test/integration_test.dart';

const _url = String.fromEnvironment('SERVER_URL');
const _token = String.fromEnvironment('TOKEN');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'connect, create a session, send a prompt, see the answer',
    (tester) async {
      if (_url.isEmpty || _token.isEmpty) {
        markTestSkipped('SERVER_URL/TOKEN not provided');
        return;
      }

      final gateway = HermesGateway(
        HermesEndpoint.parse(_url, credential: _token),
      );
      await gateway.connect();
      final workspace = Workspace(gateway);
      addTearDown(() async {
        workspace.dispose();
        await gateway.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: WorkspaceScreen(workspace: workspace),
        ),
      );
      // A real round trip, not a fake: give the session list time to land.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      // Deliberately not asserted on: this test is about the send path, and
      // `session.list` is a method that can wedge server-side independently of
      // it (see docs/PROTOCOL.md). Coupling them makes a server fault look like
      // a client regression.
      if (workspace.sessions.isEmpty) {
        // ignore: avoid_print
        print('note: session.list returned nothing — check the server');
      }

      // Its own session, so nothing the user has running is disturbed.
      final console = await workspace.createSession();
      expect(console, isNotNull, reason: 'session.create must succeed');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ConsoleView), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).last,
        'Reply with exactly: pong',
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(
        console!.streaming,
        isTrue,
        reason: 'the composer must mark the turn as started',
      );

      // Poll rather than pumpAndSettle: the transcript is deliberately animated
      // by arriving tokens, so settle would wait for a quiescence that only
      // happens when the turn ends anyway.
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (console.streaming && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(
        console.streaming,
        isFalse,
        reason: 'message.complete must arrive and clear the flag',
      );
      expect(
        console.deltaCount,
        greaterThan(0),
        reason: 'at least one message.delta must have been routed',
      );
      expect(
        console.markdown.text.toLowerCase(),
        contains('pong'),
        reason: 'the answer must reach the renderer',
      );
      expect(console.lastError, isNull);

      // And it is actually on screen, not merely in the controller.
      await tester.pump();
      expect(find.textContaining('pong', findRichText: true), findsWidgets);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'a reasoning turn shows its thinking on screen',
    (tester) async {
      // The complaint this exists for: "还是没有 thinking 里面的过程，显示不出来".
      // Everything below the UI was verified separately — the server really
      // sends reasoning.delta, the handler really routes it, a replay of the
      // captured frames really renders. What none of that covers is the app as
      // it actually runs, which is where the user is looking.
      if (_url.isEmpty || _token.isEmpty) {
        markTestSkipped('SERVER_URL/TOKEN not provided');
        return;
      }

      final gateway = HermesGateway(
        HermesEndpoint.parse(_url, credential: _token),
      );
      await gateway.connect();
      final workspace = Workspace(gateway);
      addTearDown(() async {
        workspace.dispose();
        await gateway.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(home: WorkspaceScreen(workspace: workspace)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      final console = await workspace.createSession();
      expect(console, isNotNull);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // A question that cannot be answered by recall, so the model has to
      // reason where the client can see it.
      await tester.enterText(
        find.byType(TextField).last,
        'A farmer has 17 sheep. All but 9 run away. Then he buys twice as many '
        'as he has left. How many now? Think it through step by step.',
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      // Watch for reasoning while the turn runs, not only at the end: the whole
      // point is that it is visible *during* the wait.
      var sawThinkingOnScreen = false;
      var sawStatusLine = false;
      final deadline = DateTime.now().add(const Duration(seconds: 150));
      while (console!.streaming && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        if (console.statusLine.isNotEmpty) sawStatusLine = true;
        // Either label counts: a fast turn can close the segment before the
        // next sample, and "Thought for 3s" is the same widget having done its
        // job. Requiring the running label made this test flaky, not the app.
        final labelled =
            find.textContaining('Thinking').evaluate().isNotEmpty ||
            find.textContaining('Thought for').evaluate().isNotEmpty;
        if (console.reasoning.isNotEmpty && labelled) {
          sawThinkingOnScreen = true;
        }
      }

      // Printed before the assertions so a failure says which half broke.
      // ignore: avoid_print
      print(
        'LIVE reasoning=${console.reasoning.length} chars  '
        'timeline=${console.timeline.length}  '
        'onScreen=$sawThinkingOnScreen  status=$sawStatusLine  '
        'answer=${console.markdown.text.length} chars',
      );

      expect(
        console.reasoning.isNotEmpty,
        isTrue,
        reason: 'the server sent reasoning.delta; it must reach the console',
      );
      expect(
        sawThinkingOnScreen,
        isTrue,
        reason: 'a thinking segment must be rendered during the turn',
      );
      expect(
        console.reasoning.toString(),
        isNot(contains('cogitating')),
        reason: 'the status line must not be mixed into the reasoning',
      );

      expect(console.lastError, isNull);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'reasoning grows on screen during a real turn',
    (tester) async {
      // The cadence fix, measured against the server rather than a fake. A
      // widget test can prove the console repaints; only a real turn proves the
      // text a user is reading actually advances while they read it.
      if (_url.isEmpty || _token.isEmpty) {
        markTestSkipped('SERVER_URL/TOKEN not provided');
        return;
      }

      final gateway = HermesGateway(
        HermesEndpoint.parse(_url, credential: _token),
      );
      await gateway.connect();
      final workspace = Workspace(gateway);
      addTearDown(() async {
        workspace.dispose();
        await gateway.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(home: WorkspaceScreen(workspace: workspace)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      final console = await workspace.createSession();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // A question with enough to reason about that the trace does not arrive
      // in one burst — the short-burst case is bounded by the provider, not by
      // this client, and cannot demonstrate anything either way.
      await tester.enterText(
        find.byType(TextField).last,
        'Explain step by step why the sky is blue, then estimate how many '
        'photons reach one eye per second. Show your reasoning.',
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      int renderedLength() {
        final texts = tester.widgetList<SelectableText>(
          find.byType(SelectableText),
        );
        return texts.isEmpty ? 0 : (texts.first.data ?? '').length;
      }

      // Distinct on-screen lengths seen while the reasoning is arriving. One or
      // two means it landed in jumps; many means it advanced as it was read.
      final seen = <int>{};
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (console!.streaming &&
          DateTime.now().isBefore(deadline) &&
          !console.answerStarted) {
        await tester.pump(const Duration(milliseconds: 200));
        final n = renderedLength();
        if (n > 0) seen.add(n);
      }

      // ignore: avoid_print
      print(
        'LIVE CADENCE: ${seen.length} distinct rendered lengths, '
        'final ${console.reasoning.length} chars of reasoning',
      );

      expect(
        console.reasoning.isNotEmpty,
        isTrue,
        reason: 'this question must produce reasoning',
      );
      expect(
        seen.length,
        greaterThan(5),
        reason: 'the reasoning must visibly advance, not land in a few jumps',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'a resumed conversation restores every thinking block',
    (tester) async {
      // The server stores reasoning per assistant message; the client used to
      // drop all of it on resume, so leaving a conversation and coming back lost
      // every thinking block in it.
      if (_url.isEmpty || _token.isEmpty) {
        markTestSkipped('SERVER_URL/TOKEN not provided');
        return;
      }

      final gateway = HermesGateway(
        HermesEndpoint.parse(_url, credential: _token),
      );
      await gateway.connect();
      final workspace = Workspace(gateway);
      addTearDown(() async {
        workspace.dispose();
        await gateway.dispose();
      });

      await workspace.refreshSessions();
      final listed = workspace.sessions
          .where((s) => s.messageCount >= 4)
          .toList();
      expect(listed, isNotEmpty, reason: 'need a session with some history');

      final resumed = await gateway.openSession(listed.first.id);
      final expected = resumed.messages
          .where((m) => (m.reasoning ?? '').trim().isNotEmpty)
          .length;

      final console = await workspace.open(listed.first.id);
      await tester.pump();

      // ignore: avoid_print
      print(
        'LIVE HISTORY: ${resumed.messages.length} messages, '
        '$expected carry reasoning, ${console.turns.length} turns restored',
      );

      expect(
        console.turns.length,
        expected,
        reason: 'one thinking block per message that has reasoning',
      );
      for (final turn in console.turns) {
        expect(turn.entries.whereType<ThinkingSegment>(), isNotEmpty);
        expect(
          turn.anchorBlock,
          greaterThanOrEqualTo(0),
          reason: 'each block anchors somewhere in the transcript',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'a searching turn builds the segments the reference shows',
    (tester) async {
      if (_url.isEmpty || _token.isEmpty) {
        markTestSkipped('SERVER_URL/TOKEN not provided');
        return;
      }
      final gateway = HermesGateway(
        HermesEndpoint.parse(_url, credential: _token),
      );
      await gateway.connect();
      final workspace = Workspace(gateway);
      addTearDown(() async {
        workspace.dispose();
        await gateway.dispose();
      });

      final console = await workspace.createSession();
      await tester.pump();
      await workspace.send(console!.persistedId, '搜索万宁有哪些美食');

      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (console.streaming && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      final shape = console.turns.last.entries
          .map(
            (e) => switch (e) {
              ThinkingSegment(:final text) => 'think(${text.length} chars)',
              ToolEntry(:final toolId) =>
                'tool(${console.tools[toolId]?.name ?? '?'})',
              PromptEntry(:final prompt) => 'ask(${prompt.kind})',
            },
          )
          .toList();
      // ignore: avoid_print
      print('LIVE TURN SHAPE: $shape');
      expect(shape, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'the console panels open against real data',
    (tester) async {
      if (_url.isEmpty || _token.isEmpty) {
        markTestSkipped('SERVER_URL/TOKEN not provided');
        return;
      }

      final gateway = HermesGateway(
        HermesEndpoint.parse(_url, credential: _token),
      );
      await gateway.connect();
      final workspace = Workspace(gateway);
      addTearDown(() async {
        workspace.dispose();
        await gateway.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: WorkspaceScreen(workspace: workspace),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      final console = await workspace.createSession();
      expect(console, isNotNull);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Session actions live behind the header's overflow menu; the jobs panel
      // is a sidebar action.
      for (final panel in [
        ('File checkpoints…', 'Checkpoints'),
        ('Background processes…', 'Background processes'),
        ('Agents…', 'Agents'),
        ('Journey — what it learned…', 'Journey'),
        ('Toolsets, skills, plugins…', 'Server'),
      ]) {
        await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text(panel.$1));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(
          find.text(panel.$2),
          findsOneWidget,
          reason: '${panel.$2} must open',
        );
        await tester.tap(find.text('Close'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      for (final sidebar in [
        (Icons.schedule_rounded, 'Scheduled jobs'),
        (Icons.folder_outlined, 'Projects'),
      ]) {
        await tester.tap(find.byIcon(sidebar.$1).first);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(find.text(sidebar.$2), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      // Every panel loads over the wire; none of them may have failed.
      expect(console!.lastError, isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
