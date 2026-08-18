/// The console has to survive a user who needs bigger text.
///
/// macOS text scaling and the accessibility inspector are both things a real
/// user turns on and never turns off. A layout that only works at 1.0 is
/// broken for them, and nothing else in this suite would notice.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

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

  void event(String type, String sessionId, Map<String, dynamic> payload) =>
      _in.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {'type': type, 'session_id': sessionId, 'payload': payload},
        }),
      );
}

Future<SessionConsole> _console(
  WidgetTester tester,
  _Socket socket,
  Workspace workspace,
) async {
  final opening = workspace.open('s1');
  await tester.pump();
  socket.reply('session.resume', {
    'session_id': 'live1',
    'resumed': 's1',
    'running': false,
    'info': {'model': 'a-model-with-a-fairly-long-name', 'cwd': '/srv/project'},
    'messages': <Object>[],
  });
  return opening;
}

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('the console lays out at text scale $scale', (tester) async {
      final socket = _Socket();
      final gateway = HermesGateway(
        HermesEndpoint.tunnelled(token: 't', port: 9219),
        connector: (_) async => socket,
      );
      await gateway.connect();
      addTearDown(gateway.dispose);
      final workspace = Workspace(gateway);
      addTearDown(workspace.dispose);
      final console = await _console(tester, socket, workspace);

      // A small window, because that is where a layout runs out of room.
      tester.view.physicalSize = const Size(900, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: ConsoleView(workspace: workspace, console: console),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Everything on at once: this is the state that overflowed before.
      socket.event('reasoning.delta', 'live1', {'text': 'thinking ' * 40});
      socket.event('tool.start', 'live1', {
        'tool_id': 't1',
        'name': 'terminal',
        'context': 'a fairly long command line that wraps at this scale',
      });
      socket.event('approval.request', 'live1', {
        'tool': 'terminal',
        'command': 'rm -rf /tmp/something',
        'choices': ['once', 'session', 'deny'],
      });
      socket.event('message.delta', 'live1', {'text': 'Answer text.\n\n'});
      // Not pumpAndSettle: a running tool shows a progress indicator, which
      // never settles by design.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      // Flush the console's 600 ms scroll-pause timer (`_ambientIdle`): the
      // tail-follow jump on the final message starts it, and the test
      // binding's pending-timer check runs before `addTearDown` disposes the
      // workspace. Purely a test-timing artefact, not a layout concern.
      await tester.pump(const Duration(milliseconds: 700));

      // A RenderFlex overflow throws in a test binding, so reaching here is
      // the assertion. Named explicitly so a failure reads as what it is.
      expect(
        tester.takeException(),
        isNull,
        reason: 'the console must not overflow at scale $scale',
      );
    });
  }

  testWidgets('icon-only controls carry labels for a screen reader', (
    tester,
  ) async {
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    addTearDown(gateway.dispose);
    final workspace = Workspace(gateway);
    addTearDown(workspace.dispose);
    final console = await _console(tester, socket, workspace);

    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Tooltips are what make an IconButton announceable — VoiceOver reads the
    // tooltip, and an icon with none is a control it reads as nothing at all.
    // Matched through byTooltip rather than bySemanticsLabel because Tooltip
    // populates the semantics *tooltip* property, not the label.
    for (final tooltip in ['Attach something', 'Session actions', 'Send']) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }

    // State carried only by an icon and a colour has to be announced too.
    socket.event('tool.complete', 'live1', {
      'tool_id': 't9',
      'name': 'terminal',
      'duration_s': 0.2,
      'result': {'output': '', 'exit_code': 127, 'error': 'not found'},
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // ListTile merges its children's semantics into one node, so the label is
    // the whole row rather than the icon's word on its own.
    expect(
      find.bySemanticsLabel(RegExp(r'\bfailed\b')),
      findsWidgets,
      reason: 'a failed tool must not be distinguishable by colour alone',
    );

    handle.dispose();
  });
}
