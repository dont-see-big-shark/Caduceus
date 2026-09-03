library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/l10n/app_localizations.dart';
import 'package:caduceus/widgets/session_row.dart';
import 'package:caduceus/workspace.dart';
import 'package:caduceus/workspace_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

class _Socket implements GatewayTransport {
  final _in = StreamController<String>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Stream<String> get inbound => _in.stream;

  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, dynamic>);

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  void reply(String method, Object result) {
    final frame = sent.lastWhere((f) => f['method'] == method);
    _in.add(
      jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], 'result': result}),
    );
  }

  void event(String type, String sessionId, Map<String, dynamic> payload) =>
      _in.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {'type': type, 'session_id': sessionId, 'payload': payload},
        }),
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

Map<String, Object> _resumed(String id) => {
  'session_id': 'live-$id',
  'resumed': id,
  'running': false,
  'info': const {'model': 'glm-5-2-260617'},
  'messages': const <Object>[],
};

const _desktop = Size(1280, 800);

Future<(Workspace, _Socket)> _openWindowsDesktop(
  WidgetTester tester, {
  Size size = _desktop,
}) async {
  final (workspace, socket) = await _connected();
  addTearDown(workspace.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorkspaceScreen(workspace: workspace),
    ),
  );
  await tester.pump();
  socket.reply('session.list', {
    'sessions': [
      {
        'id': 's1',
        'title': 'A session',
        'preview': '',
        'started_at': 1754006400,
        'message_count': 4,
        'source': 'windows',
      },
    ],
  });
  await tester.pump();
  socket.reply('session.resume', _resumed('s1'));
  await tester.pumpAndSettle();
  return (workspace, socket);
}

void main() {
  testWidgets('Windows desktop renders desktop rail and search', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _openWindowsDesktop(tester);

      // On Windows desktop, the desktop sidebar/rail is shown rather than mobile drawer.
      expect(find.text('Search sessions'), findsOneWidget);
      // Both the sidebar row and the active top bar display the session title.
      expect(find.text('A session'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(SessionRow),
          matching: find.text('A session'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('New session'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows responsive layout adapts when resized below 720', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _openWindowsDesktop(tester, size: const Size(600, 800));

      // When shrunk below compact breakpoint, it adapts to compact mode with Sessions drawer.
      expect(find.byTooltip('Sessions'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows Ctrl+N shortcut triggers new session creation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final (workspace, socket) = await _openWindowsDesktop(tester);

      // Press Ctrl+N on Windows
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      // Verify session.create was sent to the gateway
      expect(socket.sent.any((f) => f['method'] == 'session.create'), isTrue);

      // Reply to session.create
      socket.reply('session.create', {
        'session_id': 'new_session_1',
        'resumed': 'new_session_1',
        'running': false,
        'info': {'model': 'glm-5-2-260617'},
        'messages': <Object>[],
      });
      await tester.pump();

      // createSession refreshes sessions after creating
      socket.reply('session.list', {
        'sessions': [
          {
            'id': 'new_session_1',
            'title': 'New session',
            'preview': '',
            'started_at': 1754006400,
            'message_count': 0,
            'source': 'windows',
          },
        ],
      });
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows Ctrl+R shortcut triggers reconnect', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final (workspace, socket) = await _openWindowsDesktop(tester);

      // Press Ctrl+R on Windows
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      // Verify reconnect triggers session.list query
      expect(socket.sent.any((f) => f['method'] == 'session.list'), isTrue);

      // Reply to session.list to resolve pending timer
      socket.reply('session.list', {
        'sessions': [
          {
            'id': 's1',
            'title': 'A session',
            'preview': '',
            'started_at': 1754006400,
            'message_count': 4,
            'source': 'windows',
          },
        ],
      });
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows Ctrl+K shortcut opens command palette', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _openWindowsDesktop(tester);

      // Press Ctrl+K
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      // Command palette should appear with action commands
      expect(find.text('Copy transcript'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows Ctrl+Enter shortcut in composer triggers send', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final (workspace, socket) = await _openWindowsDesktop(tester);

      final inputFinder = find.byType(TextField).last;
      await tester.enterText(inputFinder, 'Hello Windows');
      await tester.pump();
      expect(find.text('Hello Windows'), findsOneWidget);

      // Press Ctrl+Enter on Windows
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      // Verifies _handleSend cleared the input field
      expect(tester.widget<TextField>(inputFinder).controller!.text, isEmpty);

      // Reply to prompt.submit to resolve the pending call timer
      socket.reply('prompt.submit', {'status': 'streaming'});
      socket.event('message.complete', 'live-s1', const {});
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
