/// Typing into the composer, including the boring parts.
///
/// Erasing everything you typed threw a RangeError on every keystroke that
/// emptied the field — `lastIndexOf(pattern, -1)` is an error, not an empty
/// answer. It was found by driving the app on a simulator, not by any of the
/// 121 tests, because every one of those only ever typed text *in*.
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
}

Future<(Workspace, SessionConsole)> _open(WidgetTester tester) async {
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
  return (workspace, await opening);
}

void main() {
  testWidgets('erasing everything you typed does not throw', (tester) async {
    final (workspace, console) = await _open(tester);
    addTearDown(() {
      final gateway = workspace.gateway;
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

    final field = find.byType(TextField).first;
    await tester.enterText(field, 'a question');
    await tester.pump();
    await tester.enterText(field, '');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('backspacing all the way out does not throw', (tester) async {
    // The real sequence, one character at a time — including the keystroke
    // that lands on an empty field, which is the one that threw.
    final (workspace, console) = await _open(tester);
    addTearDown(() {
      final gateway = workspace.gateway;
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

    final field = find.byType(TextField).first;
    const typed = 'hello';
    for (var i = typed.length; i >= 0; i--) {
      await tester.enterText(field, typed.substring(0, i));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason:
            'threw with ${i == 0 ? 'an empty field' : '"${typed.substring(0, i)}"'}',
      );
    }
  });
}
