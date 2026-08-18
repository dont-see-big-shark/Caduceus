/// A successful call is not a successful lookup.
///
/// `learning.detail` answers `{"ok": false, "message": "skill 'x' not found"}`
/// for a node the journey still lists — a skill removed from disk, say — and
/// the panel read straight past it to `content`, opening an editor on the
/// empty string. What the user saw was a dialog titled with the skill's name,
/// a blank grey box, and Save and Archive buttons for something that no longer
/// exists.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/journey_panel.dart';
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

  Map<String, dynamic> lastOf(String m) =>
      sent.lastWhere((f) => f['method'] == m);

  void reply(String m, Object r) => _in.add(
    jsonEncode({'jsonrpc': '2.0', 'id': lastOf(m)['id'], 'result': r}),
  );
}

/// One bucket holding one skill, the shape learning.journey returns.
const _journey = {
  'buckets': [
    {
      'label': 'This week',
      'nodes': [
        {
          'id': 'model-quota-battery-report',
          'label': 'model-quota-battery-report',
          'kind': 'skill',
        },
      ],
    },
  ],
  'axis': {'start': '', 'end': ''},
  'categories': <Object>[],
  'summary': <Object>[],
  'count': 1,
};

Future<(HermesGateway, _Socket)> _connected() async {
  final socket = _Socket();
  final gateway = HermesGateway(
    HermesEndpoint.tunnelled(token: 't', port: 9219),
    connector: (_) async => socket,
  );
  await gateway.connect();
  return (gateway, socket);
}

void main() {
  testWidgets('a missing entry says so instead of showing a blank editor', (
    tester,
  ) async {
    final (gateway, socket) = await _connected();
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: JourneyPanel(gateway: gateway)),
      ),
    );
    await tester.pump();
    socket.reply('learning.frames', _journey);
    await tester.pumpAndSettle();

    await tester.tap(find.text('model-quota-battery-report').first);
    await tester.pump();
    // Exactly what the reference server answers for a skill that is listed
    // but no longer on disk.
    socket.reply('learning.detail', {
      'ok': false,
      'message': "skill 'model-quota-battery-report' not found",
    });
    await tester.pumpAndSettle();

    expect(
      find.textContaining('not found'),
      findsOneWidget,
      reason: 'the reason has to reach the user',
    );
    expect(
      find.text('Save'),
      findsNothing,
      reason: 'saving into something that does not exist is not an option',
    );
    expect(find.text('Archive'), findsNothing);
    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'the blank box was the whole bug',
    );
  });

  testWidgets('an entry that does exist still opens for editing', (
    tester,
  ) async {
    final (gateway, socket) = await _connected();
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: JourneyPanel(gateway: gateway)),
      ),
    );
    await tester.pump();
    socket.reply('learning.frames', _journey);
    await tester.pumpAndSettle();

    await tester.tap(find.text('model-quota-battery-report').first);
    await tester.pump();
    socket.reply('learning.detail', {
      'ok': true,
      'kind': 'skill',
      'id': 'model-quota-battery-report',
      'label': 'model-quota-battery-report',
      'content': '---\nname: model-quota-battery-report\n---\n',
    });
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}
