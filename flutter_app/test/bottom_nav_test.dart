/// The design's mobile `bottom-nav` — 会话 / 面板 / 连接 / 设置
/// (Chat / Panels / Connect / Settings), not the panel list a first pass
/// guessed. Chat is the conversation; Panels opens the Capabilities Hub
/// sheet; Connect and Settings open their full destinations.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/l10n/app_localizations.dart';
import 'package:caduceus/workspace.dart';
import 'package:caduceus/workspace_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

const _phone = Size(393, 852);

Future<(Workspace, _Socket)> _open(
  WidgetTester tester, {
  Locale? locale,
}) async {
  final (workspace, socket) = await _connected();
  addTearDown(workspace.dispose);
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WorkspaceScreen(workspace: workspace),
    ),
  );
  await tester.pump();
  socket.reply('session.list', {
    'sessions': [
      {'id': 's1', 'title': 'A session', 'message_count': 4},
    ],
  });
  await tester.pump();
  socket.reply('session.resume', _resumed('s1'));
  await tester.pumpAndSettle();
  return (workspace, socket);
}

void main() {
  testWidgets(
    'Android has no bottom nav crowding conversation — edge-to-edge parity with iOS',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _open(tester);

        // The conversation surface is edge-to-edge on Android:
        // no bottom nav bar stealing height or colliding with the composer.
        expect(find.text('Chat'), findsNothing);
        expect(find.text('Panels'), findsNothing);
        expect(find.text('Connect'), findsNothing);
        expect(find.text('Settings'), findsNothing);

        // The session top bar provides the drawer entry point.
        expect(find.byTooltip('Sessions'), findsOneWidget);

        // The drawer carries all navigation destinations.
        await tester.tap(find.byTooltip('Sessions'));
        await tester.pumpAndSettle();
        expect(find.text('New session'), findsOneWidget);
        expect(find.text('Search sessions'), findsOneWidget);
        expect(find.text('Sessions'), findsWidgets);
        expect(find.text('Tools'), findsOneWidget);
        expect(find.text('Shared'), findsOneWidget);
        expect(find.text('Settings'), findsWidgets);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'iOS has no bottom nav crowding conversation — top bar and drawer carry it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _open(tester);

        expect(find.text('Chat'), findsNothing);
        expect(find.text('Panels'), findsNothing);
        expect(find.text('Connect'), findsNothing);
        expect(find.text('Settings'), findsNothing);

        expect(find.byTooltip('Sessions'), findsOneWidget);

        await tester.tap(find.byTooltip('Sessions'));
        await tester.pumpAndSettle();
        expect(find.text('New session'), findsOneWidget);
        expect(find.text('Search sessions'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('the zh locale renders Chinese chrome in drawer', (tester) async {
    await _open(tester, locale: const Locale('zh'));

    // The session top bar gives a way in with localized tooltip.
    expect(find.byTooltip('会话'), findsOneWidget);

    // Drawer segments: 会话 / 工具 / 共享 / 设置.
    await tester.tap(find.byTooltip('会话'));
    await tester.pumpAndSettle();
    expect(find.text('新建会话'), findsOneWidget);
    expect(find.text('搜索会话'), findsOneWidget);
    expect(find.text('会话'), findsWidgets);
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('共享'), findsOneWidget);
    expect(find.text('设置'), findsWidgets);
  });
}

/// The design's UI language is 简体中文, and the chrome labels are locked
/// copy: 会话 / 面板 / 连接 / 设置. Verify the zh locale renders exactly that.
