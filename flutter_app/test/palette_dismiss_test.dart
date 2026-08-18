/// The command palette has to close without typing.
///
/// It cleared only on the *next keystroke*, so dismissing the keyboard or
/// tapping the conversation left it open covering half the screen with no way
/// to get rid of it.
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

void main() {
  testWidgets('tapping the conversation closes the palette', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    final workspace = Workspace(gateway);
    addTearDown(() {
      workspace.dispose();
      unawaited(gateway.dispose());
    });

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
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
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '/');
    await tester.pump();
    socket.reply('commands.catalog', {
      'pairs': [
        ['/new', 'Start a new session'],
        ['/clear', 'Clear screen and start a new session'],
      ],
    });
    await tester.pumpAndSettle();
    expect(
      find.text('/new'),
      findsOneWidget,
      reason:
          'the palette fills once the catalog lands, even though the '
          'slash was typed before it arrived',
    );

    // Tap the conversation — the gesture people try first.
    await tester.tapAt(const Offset(200, 300));
    await tester.pumpAndSettle();

    expect(
      find.text('/new'),
      findsNothing,
      reason: 'it has to close without typing anything',
    );
  });
}
