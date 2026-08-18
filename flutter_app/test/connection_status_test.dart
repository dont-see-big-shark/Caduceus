/// What a lost connection looks like.
///
/// It used to be a full-width filled bar — how this design shouts. A reconnect
/// that resolves in two seconds is not worth shouting about, and one that
/// never will needs a way out, not a louder colour.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/design/components.dart';
import 'package:caduceus/design/tokens.dart';
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

  /// Drops the socket, which is what the gateway watches for.
  Future<void> die() async => _in.close();
}

void main() {
  testWidgets('a broken connection is a pill, not a coloured band', (
    tester,
  ) async {
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

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(workspace: workspace)),
    );
    await tester.pump();
    socket.reply('session.list', {'sessions': <Object>[]});
    await tester.pump();

    expect(
      find.byType(StatusPill),
      findsNothing,
      reason: 'a healthy connection says nothing at all',
    );

    await socket.die();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final pill = find.byType(StatusPill);
    expect(pill, findsOneWidget);

    // The notice floats in an overlay (Stack + Positioned) — it must not take
    // a layout row that shoves the workbench down.
    expect(
      find.ancestor(of: pill, matching: find.byType(Stack)),
      findsWidgets,
      reason: 'a floating notice lives in an overlay, not in the column flow',
    );

    // It reports in the palette's own vocabulary, not Material's error colour.
    final widget = tester.widget<StatusPill>(pill);
    expect(
      [Palette.brass, Palette.coral],
      contains(widget.color),
      reason: 'brass while it is still trying, coral once it has given up',
    );
    expect(
      widget.pulsing,
      widget.color == Palette.brass,
      reason: 'breathing means still trying; steady means it stopped',
    );

    // Disposed inside the body, not in a tear-down: a dropped socket arms the
    // gateway's reconnect backoff, and the binding checks for pending timers
    // *before* tear-downs run.
    workspace.dispose();
    await gateway.dispose();
  });
}
