/// The keyboard belongs to the user, not to the composer.
///
/// Reported as "键盘收不回去" — the keyboard cannot be put away. It was not a
/// dismissal failure: the composer took focus back after every action, so
/// sending, attaching a file, or opening a session all raised it again. On a
/// desktop that is correct behaviour; on a phone the keyboard is half the
/// screen.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
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

class _Socket implements GatewayTransport {
  final _in = StreamController<String>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Stream<String> get inbound => _in.stream;

  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, dynamic>);

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  void reply(String method, Object result) {
    final frame = sent.lastWhere((f) => f['method'] == method);
    _in.add(
      jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], 'result': result}),
    );
  }
}

Future<SessionConsole> _console(
  WidgetTester tester,
  Workspace workspace,
  _Socket socket,
) async {
  final opening = workspace.open('s1');
  await tester.pump();
  socket.reply('session.resume', {
    'session_id': 'live1',
    'resumed': 's1',
    'running': false,
    'messages': <Object>[],
  });
  return opening;
}

Future<(Workspace, _Socket)> _connected() async {
  final socket = _Socket();
  final gateway = HermesGateway(
    HermesEndpoint.tunnelled(token: 't', port: 9219),
    connector: (_) async => socket,
  );
  await gateway.connect();
  return (Workspace(gateway), socket);
}

/// Focus is the precise signal. Keyboard visibility follows from it, and
/// asserting on focus says what the code actually controls.
bool _composerFocused(WidgetTester tester) {
  // Exact: does a real text field hold focus. An earlier version of this
  // helper asked whether *anything* had focus, which is true for the
  // surrounding FocusScope even after an unfocus, so it passed regardless.
  final fields = tester.widgetList<EditableText>(find.byType(EditableText));
  return fields.any((f) => f.focusNode.hasFocus);
}

void main() {
  testWidgets('opening a session on a phone leaves the keyboard down', (
    tester,
  ) async {
    // Raising it before the transcript has been read covers half of what the
    // user opened the session to see.
    final (workspace, socket) = await _connected();
    addTearDown(workspace.dispose);
    final console = await _console(tester, workspace, socket);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('opening a session on a desktop focuses the composer', (
    tester,
  ) async {
    final (workspace, socket) = await _connected();
    addTearDown(workspace.dispose);
    final console = await _console(tester, workspace, socket);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: 'on a desktop the caret should be where you type next',
    );
  });

  testWidgets('once dismissed on a phone, sending does not drag it back', (
    tester,
  ) async {
    // This is the reported bug. Not that dismissal failed — that the composer
    // took focus back after every action, so putting the keyboard away only
    // lasted until the next thing you did.
    // Not addTearDown: sending starts the 1 Hz elapsed-time timer, and the
    // binding asserts on pending timers *before* teardowns run.
    final (workspace, socket) = await _connected();
    final console = await _console(tester, workspace, socket);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'hello');
    await tester.pump();
    // The user puts it away.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    // The prompt.submit call has a 30 s timeout timer attached; leaving it
    // unanswered leaks it past the end of the test.
    socket.reply('prompt.submit', {'status': 'streaming'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      _composerFocused(tester),
      isFalse,
      reason:
          'the keyboard was dismissed on purpose; sending must not '
          'summon it again',
    );

    workspace.dispose();
  });

  testWidgets('tapping the conversation dismisses the keyboard', (
    tester,
  ) async {
    final (workspace, socket) = await _connected();
    addTearDown(workspace.dispose);
    final console = await _console(tester, workspace, socket);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: 'the field was tapped, so it should be up',
    );

    // A tap on the conversation, which is what people try first.
    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_composerFocused(tester), isFalse);
  });

  _nestedScrollTests();
}

/// Nested scrolling is a trap on a touch screen.
///
/// A capped, independently scrollable pane inside the conversation's own
/// scroll view means a drag can move either one, with nothing on screen to say
/// which. With a mouse the cap is a convenience; with a finger it is a coin
/// flip.
void _nestedScrollTests() {
  testWidgets('reasoning does not nest a scroll view on touch', (tester) async {
    final console = SessionConsole(persistedId: 's1', liveId: 's1');
    console.appendLocalPrompt('go');
    console.handle(
      _agent(
        GatewayEvent(
          type: 'reasoning.delta',
          sessionId: 's1',
          payload: {'text': 'a thought\n' * 80},
        ),
      ),
    );

    // The timeline itself no longer scrolls — it lives inside the
    // transcript's list now. What is left to check is the reasoning body:
    // capped and scrollable with a mouse, plain on touch.
    for (final (platform, expected) in [
      (TargetPlatform.iOS, 0),
      (TargetPlatform.macOS, 1),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            // A scrollable ancestor, as in the app: the timeline sizes to
            // its content and lives inside the transcript's list.
            body: ListView(
              children: [
                ListenableBuilder(
                  listenable: console,
                  builder: (c, _) => TurnTimeline(
                    console: console,
                    turn: console.turns.isEmpty
                        ? Turn(anchorBlock: 0)
                        : console.turns.last,
                    isCurrent: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final views = find.byType(SingleChildScrollView).evaluate().length;
      expect(
        views,
        expected,
        reason:
            '${platform.name}: expected '
            '${expected == 0 ? 'nothing scrollable inside the turn' : 'one capped reasoning pane'}',
      );
    }

    console.dispose();
  });
}
