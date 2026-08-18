/// The running turn's silence is reported at the bottom, not across the top.
///
/// "thinking · quiet 5s" used to be the *only* reason the header band existed
/// on a phone, so starting a turn opened a stripe across the top of the
/// conversation and pushed the whole transcript down — to report something
/// whose one useful response, stopping the turn, was at the other end of the
/// screen.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
import 'package:streaming_markdown/streaming_markdown.dart';
import 'package:caduceus/widgets/console_header.dart';
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
  void send(String d) => sent.add(jsonDecode(d) as Map<String, dynamic>);
  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  Map<String, dynamic>? lastOf(String m) {
    for (final f in sent.reversed) {
      if (f['method'] == m) return f;
    }
    return null;
  }

  void reply(String m, Object r) => _in.add(
    jsonEncode({'jsonrpc': '2.0', 'id': lastOf(m)!['id'], 'result': r}),
  );

  void event(String type, String sid, Map<String, dynamic> payload) => _in.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': type, 'session_id': sid, 'payload': payload},
    }),
  );
}

Future<(Workspace, _Socket, SessionConsole)> _open(
  WidgetTester tester, {
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final socket = _Socket();
  final gateway = HermesGateway(
    HermesEndpoint.tunnelled(token: 't', port: 9219),
    connector: (_) async => socket,
  );
  await gateway.connect();
  final workspace = Workspace(gateway);
  final opening = workspace.open('s1');
  await tester.pump();
  socket.reply('session.resume', {
    'session_id': 'live1',
    'resumed': 's1',
    'running': false,
    'info': {'model': 'glm-5-2-260617'},
    'messages': <Object>[],
  });
  final console = await opening;
  addTearDown(() {
    workspace.dispose();
    unawaited(gateway.dispose());
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConsoleView(workspace: workspace, console: console),
      ),
    ),
  );
  await tester.pump();
  return (workspace, socket, console);
}

void main() {
  testWidgets('a running turn opens no band across the top', (tester) async {
    final (_, socket, console) = await _open(tester);

    socket.event('message.start', 'live1', const {});
    await tester.pump();
    expect(console.streaming, isTrue);

    expect(
      tester.getSize(find.byType(ConsoleHeader)).height,
      0,
      reason:
          'the phone header has nothing to carry — the title is in the '
          'navigation bar and the status moved to the composer',
    );
    expect(find.textContaining('thinking · quiet'), findsNothing);

    // The 1 Hz idle tick outlives the widget tree otherwise, and a pending
    // timer fails the test for a reason that has nothing to do with it.
    socket.event('message.complete', 'live1', const {});
    await tester.pump();
  });

  testWidgets('the silence is counted next to the button that ends it', (
    tester,
  ) async {
    final (_, socket, console) = await _open(
      tester,
      // The quiet control lives in the desktop composer toolbar.
      size: const Size(1280, 800),
    );
    socket.event('message.start', 'live1', const {});
    await tester.pump();

    // Nothing yet: a turn streaming normally resets this every few hundred
    // milliseconds, and a counter flickering at zero beside send is noise.
    expect(find.textContaining('quiet'), findsNothing);

    console.lastActivity = DateTime.now().subtract(const Duration(seconds: 12));
    await tester.pump();

    expect(find.text('quiet 12s'), findsOneWidget);

    // Bottom half of the screen, near the composer — the whole point of
    // moving it. The stop button is the response it exists to prompt.
    expect(
      tester.getCenter(find.text('quiet 12s')).dy,
      greaterThan(852 / 2),
      reason: 'it belongs with the composer, not over the conversation',
    );

    socket.event('message.complete', 'live1', const {});
    await tester.pump();
  });

  testWidgets('the transcript is rendered with the design stylesheet', (
    tester,
  ) async {
    await _open(tester);

    // The stylesheet exists to kill the 5-point grey bar Markdown draws for
    // `---`. It does nothing at all unless it is handed to the view, and
    // nothing about the app fails visibly if that wiring is dropped.
    final view = tester.widget<StreamingMarkdownView>(
      find.byType(StreamingMarkdownView),
    );
    final rule = view.styleSheet?.horizontalRuleDecoration as BoxDecoration?;
    expect(rule, isNotNull);
    expect(rule!.border, isNull);
  });
}
