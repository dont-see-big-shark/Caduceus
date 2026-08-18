/// Where connecting lands you.
///
/// It landed on an empty screen offering a new session. Nobody connects to a
/// server they have been working on in order to start over — the conversation
/// they were in is what they came back for, and it was behind a drawer with
/// nothing saying which row held it.
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

/// `session.list` is ordered by last activity server-side, so the row on top
/// is the one to open — note the older `started_at` sorting *above* the newer
/// one, which is exactly the case picking the newest timestamp would get wrong.
const _twoSessions = {
  'sessions': [
    {
      'id': '20260801_090000_aaaaaa',
      'title': 'the one used ten minutes ago',
      'preview': '',
      'started_at': 1754006400,
      'message_count': 12,
      'source': 'desktop',
    },
    {
      'id': '20260803_113947_bbbbbb',
      'title': 'started yesterday, abandoned',
      'preview': '',
      'started_at': 1754179200,
      'message_count': 2,
      'source': 'tui',
    },
  ],
};

void main() {
  testWidgets('connecting lands in the most recent session', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (workspace, socket) = await _connected();
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(workspace: workspace)),
    );
    await tester.pump();
    socket.reply('session.list', _twoSessions);
    await tester.pump();

    // Top of the list, not the newest start time.
    expect(
      socket.lastOf('session.resume')!['params']['session_id'],
      '20260801_090000_aaaaaa',
    );
    socket.reply('session.resume', {
      'session_id': 'live-1',
      'resumed': '20260801_090000_aaaaaa',
      'running': false,
      'info': {'model': 'glm-5-2-260617'},
      'messages': [
        {'role': 'user', 'text': 'where were we'},
      ],
    });
    await tester.pumpAndSettle();

    expect(workspace.activeId, '20260801_090000_aaaaaa');
    expect(
      find.byType(ConsoleView),
      findsOneWidget,
      reason: 'the conversation is the screen, not an invitation to start one',
    );

    workspace.dispose();
  });

  testWidgets('the new-session screen never flashes on the way in', (
    tester,
  ) async {
    // Landing in the last session was not enough on its own: for the two round
    // trips it takes, the shell had no console and showed the empty state, so
    // every connect still put "New session" in front of the user first.
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final (workspace, socket) = await _connected();
    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(workspace: workspace)),
    );

    // Before session.list is answered.
    await tester.pump();
    expect(find.text('New session'), findsNothing);
    expect(find.text('No session open'), findsNothing);

    // And between the list and the resume that follows it.
    socket.reply('session.list', _twoSessions);
    await tester.pump();
    expect(find.text('New session'), findsNothing);
    expect(find.text('No session open'), findsNothing);

    socket.reply('session.resume', {
      'session_id': 'live-1',
      'resumed': '20260801_090000_aaaaaa',
      'running': false,
      'info': {'model': 'glm-5-2-260617'},
      'messages': <Object>[],
    });
    await tester.pumpAndSettle();
    expect(find.byType(ConsoleView), findsOneWidget);

    workspace.dispose();
  });

  testWidgets('a first connection with no sessions still offers one', (
    tester,
  ) async {
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

    expect(socket.lastOf('session.resume'), isNull);
    expect(find.text('No session open'), findsOneWidget);

    workspace.dispose();
  });

  testWidgets('skips the shell session the gateway makes on connect', (
    tester,
  ) async {
    // Connecting creates a session server-side: title-less, one message,
    // stamped to the second the socket opened. It sorts first by last
    // activity, so opening `sessions.first` landed the user in a blank
    // session they had never seen — the exact empty screen this is meant to
    // replace. Confirmed against the live server with a bare client that
    // made no session calls at all.
    final (workspace, socket) = await _connected();
    final opening = workspace.openMostRecent();
    await tester.pump();
    socket.reply('session.list', {
      'sessions': [
        {
          'id': '20260805_002442_632166',
          'title': '',
          'preview': '',
          'started_at': 1785900000,
          'message_count': 1,
          'source': 'tui',
        },
        ..._twoSessions['sessions']!,
      ],
    });
    await tester.pump();

    expect(
      socket.lastOf('session.resume')!['params']['session_id'],
      '20260801_090000_aaaaaa',
      reason: 'the newest *conversation*, not the newest row',
    );
    socket.reply('session.resume', {
      'session_id': 'live-1',
      'resumed': '20260801_090000_aaaaaa',
      'running': false,
      'info': {'model': 'm'},
      'messages': <Object>[],
    });
    await opening;
    expect(workspace.activeId, '20260801_090000_aaaaaa');

    workspace.dispose();
  });

  testWidgets('a real one-message session is still worth opening', (
    tester,
  ) async {
    // The guard keys on "no title *and* nothing said". A short exchange the
    // server has already titled must not be mistaken for a shell.
    final (workspace, socket) = await _connected();
    final opening = workspace.openMostRecent();
    await tester.pump();
    socket.reply('session.list', {
      'sessions': [
        {
          'id': 'short-but-real',
          'title': 'One quick question',
          'preview': '',
          'started_at': 1785900000,
          'message_count': 1,
          'source': 'tui',
        },
      ],
    });
    await tester.pump();

    expect(
      socket.lastOf('session.resume')!['params']['session_id'],
      'short-but-real',
    );
    socket.reply('session.resume', {
      'session_id': 'live-1',
      'resumed': 'short-but-real',
      'running': false,
      'info': {'model': 'm'},
      'messages': <Object>[],
    });
    await opening;

    workspace.dispose();
  });

  testWidgets('a later refresh does not yank you out of what you are in', (
    tester,
  ) async {
    // openMostRecent runs on reconnects and rebuilds too. Whatever is open
    // stays open — being moved to another conversation mid-read would be
    // worse than the empty screen this replaced.
    final (workspace, socket) = await _connected();
    final opening = workspace.open('20260803_113947_bbbbbb');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live-2',
      'resumed': '20260803_113947_bbbbbb',
      'running': false,
      'info': {'model': 'glm-5-2-260617'},
      'messages': <Object>[],
    });
    await opening;

    final again = workspace.openMostRecent();
    await tester.pump();
    socket.reply('session.list', _twoSessions);
    await again;

    expect(workspace.activeId, '20260803_113947_bbbbbb');
    expect(
      socket.lastOf('session.resume')!['params']['session_id'],
      '20260803_113947_bbbbbb',
      reason: 'no second resume was sent for the top row',
    );

    workspace.dispose();
  });
}
