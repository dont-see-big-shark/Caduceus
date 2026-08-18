/// 文末光标闪烁 — the caret at the end of an answer still arriving.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
import 'package:caduceus/design/components.dart';
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

void main() {
  testWidgets('the caret appears only while a turn is running', (tester) async {
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
      'info': {'model': 'm'},
      'messages': <Object>[],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byType(StreamCaret),
      findsNothing,
      reason:
          'a caret under a finished answer says the opposite of what it '
          'means',
    );

    socket.event('message.start', 'live1', const {});
    socket.event('message.delta', 'live1', const {'text': 'half a sen'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(StreamCaret), findsOneWidget);

    socket.event('message.complete', 'live1', const {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(StreamCaret), findsNothing);

    final g = workspace.gateway;
    workspace.dispose();
    unawaited(g.dispose());
  });

  testWidgets('it rests visible when motion is off', (tester) async {
    // Frozen mid-blink in the *off* half, a caret is invisible — and an
    // invisible caret is indistinguishable from a finished answer. Reduced
    // motion must lose the blink, not the caret.
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Center(child: StreamCaret())),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(StreamCaret),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 1.0);
  });
}
