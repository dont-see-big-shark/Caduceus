/// The design's mobile `bottom-nav` — 会话 / 面板 / 连接 / 设置
/// (Chat / Panels / Connect / Settings), not the panel list a first pass
/// guessed. Chat is the conversation; Panels opens the Capabilities Hub
/// sheet; Connect and Settings open their full destinations.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/capabilities_hub.dart';
import 'package:caduceus/connect_screen.dart';
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
  testWidgets('the bottom nav is the design\'s 会话/面板/连接/设置', (tester) async {
    await _open(tester);

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Panels'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    // The first pass invented Journey / Workspace here; the design has no
    // such items and neither may the app.
    expect(find.text('Journey'), findsNothing);
    expect(find.text('Workspace'), findsNothing);
  });

  testWidgets('Panels opens the Capabilities Hub as a sheet', (tester) async {
    final (workspace, socket) = await _open(tester);

    await tester.tap(find.text('Panels'));
    await tester.pumpAndSettle();
    // The hub asks the gateway as it opens; answer so the list settles.
    socket.reply('skills.manage', {
      'skills': {'read_file': 'Read a file from the workspace'},
    });
    socket.reply('tools.list', <Object>[]);
    socket.reply('plugins.list', <Object>[]);
    await tester.pumpAndSettle();

    expect(find.byType(CapabilitiesHub), findsOneWidget);
    // Tab labels carry live counts ('Skills · 1'), so match on the stem.
    expect(find.textContaining('Skills'), findsWidgets);
    expect(find.textContaining('Tools'), findsWidgets);
    expect(find.textContaining('MCP'), findsWidgets);
    expect(find.text('Browse Hub'), findsOneWidget);
  });

  testWidgets('Connect pushes the connect screen', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectScreen), findsOneWidget);
  });

  testWidgets('Settings opens the settings overlay', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    // The design's settings-nav opens with the CORE group.
    expect(find.text('Model'), findsOneWidget);
  });

  testWidgets('the zh locale renders the design\'s Chinese chrome', (
    tester,
  ) async {
    await _open(tester, locale: const Locale('zh'));

    // Bottom nav: 会话 / 面板 / 连接 / 设置 — the design's locked copy.
    expect(find.text('会话'), findsOneWidget);
    expect(find.text('面板'), findsWidgets);
    expect(find.text('连接'), findsOneWidget);
    expect(find.text('设置'), findsWidgets);

    // Drawer segments: 会话 / 面板 / 设置.
    await tester.tap(find.byTooltip('会话'));
    await tester.pumpAndSettle();
    expect(find.text('新建会话'), findsOneWidget);
    expect(find.text('搜索会话'), findsOneWidget);
  });

  testWidgets('iOS has no bottom nav — the top bar and drawer carry it', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _open(tester);

      // The design's `.bottomnav` is Android-only. On iOS these labels belong
      // to the top bar and drawer instead.
      expect(find.text('Chat'), findsNothing);
      expect(find.text('Panels'), findsNothing);
      expect(find.text('Connect'), findsNothing);
      expect(find.text('Settings'), findsNothing);

      // The session top bar still gives a way in.
      expect(find.byTooltip('Sessions'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// The design's UI language is 简体中文, and the chrome labels are locked
/// copy: 会话 / 面板 / 连接 / 设置. Verify the zh locale renders exactly that.
