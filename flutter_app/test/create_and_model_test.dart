/// Creating a session, and switching a model, through the real UI.
///
/// Both were reported as simply not working. Neither was a protocol failure —
/// `session.create` and `config.set` both succeed against the reference
/// server — so both were in the client.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
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

Future<(Workspace, _Socket)> _connected() async {
  final socket = _Socket();
  final gateway = HermesGateway(
    HermesEndpoint.tunnelled(token: 't', port: 9219),
    connector: (_) async => socket,
  );
  await gateway.connect();
  return (Workspace(gateway), socket);
}

/// The real reply shape: two ids, and they are not the same.
const _created = {
  'session_id': 'c5c0820a',
  'stored_session_id': '20260803_113947_a6f6ae',
  'message_count': 0,
  'messages': <Object>[],
  'info': {'model': 'glm-5-2-260617', 'cwd': '/'},
};

void main() {
  testWidgets('a new session is keyed by the durable id, not the handle', (
    tester,
  ) async {
    // session.create returns session_id (the gateway handle) *and*
    // stored_session_id (what session.list reports). Keying the console by
    // the handle meant it never matched any row in the sidebar, so creating
    // one looked like nothing had happened.
    final (workspace, socket) = await _connected();
    final creating = workspace.createSession();
    await tester.pump();
    socket.reply('session.create', _created);
    final console = await creating;
    // createSession also refreshes the list; leaving that call unanswered
    // leaves its 30 s timeout timer pending past the end of the test.
    await tester.pump();
    socket.reply('session.list', {'sessions': <Object>[]});
    await tester.pump();

    expect(console, isNotNull);
    expect(
      console!.persistedId,
      '20260803_113947_a6f6ae',
      reason: 'the sidebar and session.list speak the durable id',
    );
    expect(
      console.liveId,
      'c5c0820a',
      reason: 'every RPC and event uses the handle',
    );
    expect(workspace.activeId, '20260803_113947_a6f6ae');
    expect(
      console.model,
      'glm-5-2-260617',
      reason: 'the reply already says which model it starts on',
    );

    workspace.dispose();
  });

  testWidgets('events for a new session reach its console', (tester) async {
    // The routing table has to map handle to durable id, or the new session
    // receives nothing it is sent.
    final (workspace, socket) = await _connected();
    final creating = workspace.createSession();
    await tester.pump();
    socket.reply('session.create', _created);
    final console = await creating;
    await tester.pump();
    socket.reply('session.list', {'sessions': <Object>[]});
    await tester.pump();

    socket._in.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': 'message.delta',
          'session_id': 'c5c0820a',
          'payload': {'text': 'hello from the agent'},
        },
      }),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(console!.markdown.text, contains('hello from the agent'));
    workspace.dispose();
  });

  testWidgets('creating on a phone lands in the new session', (tester) async {
    // Creating a session has to put the user *in* it. It previously only set
    // activeId, which on the compact layout changed nothing on screen.
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (workspace, socket) = await _connected();
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(workspace: workspace)),
    );
    await tester.pump();
    socket.reply('session.list', {'sessions': <Object>[]});
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sessions'));
    await tester.pumpAndSettle();
    // Scoped: the empty state behind the drawer offers the same action.
    await tester.tap(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('New session'),
      ),
    );
    await tester.pump();
    socket.reply('session.create', _created);
    await tester.pump();
    socket.reply('session.list', {'sessions': <Object>[]});
    await tester.pumpAndSettle();

    expect(
      find.byType(ConsoleView),
      findsOneWidget,
      reason: 'the session exists; the screen has to say so',
    );
    workspace.dispose();
  });

  testWidgets('switching a model updates what the picker calls current', (
    tester,
  ) async {
    // The inventory is cached to avoid a 3-7 second re-query. It kept naming
    // the old model as current after a switch, so reopening the picker showed
    // the tick beside the model you had just switched away from.
    final (workspace, socket) = await _connected();
    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'l1',
      'resumed': 's1',
      'running': false,
      'info': {'model': 'glm-5-2-260617'},
      'messages': <Object>[],
    });
    final console = await opening;

    final loading = workspace.modelInventory('s1');
    await tester.pump();
    socket.reply('model.options', {
      'model': 'glm-5-2-260617',
      'provider': 'zhipu',
      'providers': [
        {
          'slug': 'copilot',
          'name': 'GitHub Copilot',
          'authenticated': true,
          'models': ['gpt-5.4', 'claude-sonnet-5'],
        },
      ],
    });
    expect((await loading)!.currentModel, 'glm-5-2-260617');

    final switching = workspace.setModel('s1', 'claude-sonnet-5');
    await tester.pump();
    socket.reply('config.set', {'key': 'model', 'value': 'claude-sonnet-5'});
    expect(await switching, isTrue);

    // Addressed with the live handle, as every session-scoped call must be.
    expect(socket.lastOf('config.set')!['params']['session_id'], 'l1');
    expect(console.model, 'claude-sonnet-5');

    // And served from cache, without a second round trip that would take
    // seconds — but naming the right model.
    final again = await workspace.modelInventory('s1');
    expect(again!.currentModel, 'claude-sonnet-5');

    workspace.dispose();
  });
}
