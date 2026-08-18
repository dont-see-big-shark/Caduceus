/// Switching sessions, including faster than the transition.
///
/// The cross-fade keeps the outgoing transcript mounted for 320 ms. Switch
/// away and back inside that window and two views of the *same* console can
/// exist at once — each attaching the console's scroll controller, which is
/// the "ScrollController attached to multiple scroll views" crash this app has
/// already had once, from a different cause.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/workspace.dart';
import 'package:caduceus/workspace_screen.dart';
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

Map<String, Object> _resumed(String id) => {
  'session_id': 'live-$id',
  'resumed': id,
  'running': false,
  'info': const {'model': 'm'},
  'messages': [
    {'role': 'user', 'text': 'question in $id'},
    {'role': 'assistant', 'text': 'answer in $id ' * 40},
  ],
};

const _sessions = {
  'sessions': [
    {'id': 'a', 'title': 'Session A', 'message_count': 8, 'source': 'tui'},
    {'id': 'b', 'title': 'Session B', 'message_count': 9, 'source': 'tui'},
  ],
};

void main() {
  testWidgets('switching back inside the transition does not crash', (
    tester,
  ) async {
    // A desktop-width window, where both sessions are one click apart and a
    // fast double-switch is easy to do by accident.
    tester.view.physicalSize = const Size(1200, 800);
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

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(workspace: workspace)),
    );
    await tester.pump();
    socket.reply('session.list', _sessions);
    await tester.pump();
    socket.reply('session.resume', _resumed('a'));
    await tester.pump(const Duration(milliseconds: 400));

    // A → B, then straight back to A while the fade is still running. The
    // sidebar no longer hosts a session list (the design moved it to popups),
    // so switching is driven through the workspace — the cross-fade in the
    // console is the same code path either way.
    workspace.open('b');
    await tester.pump();
    socket.reply('session.resume', _resumed('b'));
    await tester.pump(const Duration(milliseconds: 60));

    workspace.open('a');
    await tester.pump(const Duration(milliseconds: 60));
    workspace.open('b');
    await tester.pump(const Duration(milliseconds: 60));

    expect(
      tester.takeException(),
      isNull,
      reason: 'two views of one console must not fight over its controller',
    );

    // And it settles somewhere sane rather than half-faded forever.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(workspace.activeId, 'b');
  });
}
