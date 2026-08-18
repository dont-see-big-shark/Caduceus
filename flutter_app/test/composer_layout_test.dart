/// The composer's controls, and what the primary button does.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
import 'package:caduceus/design/glass.dart';
import 'package:caduceus/design/press.dart';
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

Future<(Workspace, _Socket, SessionConsole)> _open(WidgetTester tester) async {
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
  return (workspace, socket, await opening);
}

void main() {
  testWidgets('the composer controls share one height', (tester) async {
    // Reported from the phone: the attach button, the field and send did not
    // line up. An IconButton's default 48 pt box against a dense field's
    // ~40 pt is the reason.
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (workspace, _, console) = await _open(tester);
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
    await tester.pumpAndSettle();

    // The buttons, not the glyphs inside them: an icon is the same size
    // either way, and it was the button boxes that disagreed. `Pressable` is
    // what wraps a composer control now that they are no longer IconButtons.
    Size boxOf(IconData icon) => tester.getSize(
      find
          .ancestor(of: find.byIcon(icon), matching: find.byType(Pressable))
          .first,
    );

    final attach = boxOf(Icons.add_rounded);
    final send = boxOf(Icons.arrow_upward_rounded);
    expect(
      attach.height,
      send.height,
      reason: 'the two buttons must agree on a height',
    );
    expect(
      attach.height,
      greaterThanOrEqualTo(44),
      reason: '44 pt is the smallest target iOS asks for',
    );
  });

  testWidgets('send becomes stop while a turn is running', (tester) async {
    // Disposed at the end of the body: streaming starts a 1 Hz timer and the
    // binding checks for pending timers before teardowns run.
    final (workspace, socket, console) = await _open(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);

    socket.event('message.start', 'live1', const {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byIcon(Icons.stop_rounded),
      findsOneWidget,
      reason: 'the button you already have your thumb on should stop it',
    );

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    expect(socket.lastOf('session.interrupt'), isNotNull);
    // The gateway too: an unanswered call leaves its 30 s timeout timer
    // pending, which the binding checks for. Not awaited — closing its
    // broadcast streams does not complete inside a pumped test.
    final gateway = workspace.gateway;
    workspace.dispose();
    unawaited(gateway.dispose());
  });

  testWidgets('typing during a turn turns stop back into send', (tester) async {
    // Queueing a follow-up is still possible mid-turn; the button has to
    // follow what the user is actually doing.
    final (workspace, socket, console) = await _open(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();
    socket.event('message.start', 'live1', const {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'a follow-up');
    await tester.pump();
    expect(
      find.byIcon(Icons.arrow_upward_rounded),
      findsOneWidget,
      reason: 'there is something to send now',
    );
    // The gateway too: an unanswered call leaves its 30 s timeout timer
    // pending, which the binding checks for. Not awaited — closing its
    // broadcast streams does not complete inside a pumped test.
    final gateway = workspace.gateway;
    workspace.dispose();
    unawaited(gateway.dispose());
  });

  testWidgets('the model opens the picker from beside the field', (
    tester,
  ) async {
    final (workspace, socket, console) = await _open(tester);
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
    await tester.pumpAndSettle();

    expect(
      find.text('glm-5-2-260617'),
      findsOneWidget,
      reason: 'the model belongs next to what it will answer',
    );
    await tester.tap(find.text('glm-5-2-260617'));
    await tester.pump();
    await tester.pump();
    expect(socket.lastOf('model.options'), isNotNull);
    socket.reply('model.options', {
      'model': 'glm-5-2-260617',
      'providers': <Object>[],
    });
    await tester.pumpAndSettle();
  });

  testWidgets('the phone composer keeps the model inside the card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (workspace, _, console) = await _open(tester);
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
    await tester.pumpAndSettle();

    // The Claude-style phone composer is one card: the field on top, then a
    // toolbar band carrying the model switch and send. The model must not
    // float above the card as it did before.
    final card = find
        .ancestor(
          of: find.byIcon(Icons.arrow_upward_rounded),
          matching: find.byType(GlassPanel),
        )
        .first;
    expect(
      find.descendant(of: card, matching: find.text('glm-5-2-260617')),
      findsOneWidget,
      reason: 'the model switch belongs inside the composer card',
    );
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.add_rounded)),
      findsOneWidget,
      reason: 'the attach control stays inside the same card',
    );
  });
}
