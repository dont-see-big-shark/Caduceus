/// The ＋ sheet and the chips under the field.
///
/// The prototype draws four tiles — 拍照 · 图库 · 文件 · 录像 — over two rows for
/// the sources that are not captures. What must never appear is a tile that
/// opens nothing: server-side *screen* recording has no method on the control
/// plane, and a device with no camera has no camera.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/capture.dart';
import 'package:caduceus/console_view.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

import 'fake_capture.dart';

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

Future<(Workspace, SessionConsole, _Socket)> _openWithSocket(
  WidgetTester tester,
) async {
  final (w, c) = await _open(tester);
  return (w, c, _lastSocket!);
}

_Socket? _lastSocket;

Future<(Workspace, SessionConsole)> _open(WidgetTester tester) async {
  final socket = _lastSocket = _Socket();
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
    'info': {'model': 'm'},
    'messages': <Object>[],
  });
  return (workspace, await opening);
}

Future<void> _mount(
  WidgetTester tester,
  Workspace workspace,
  SessionConsole console, {
  MediaCapture? media,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConsoleView(
          workspace: workspace,
          console: console,
          media: media ?? FakeMedia(),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Attach something'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('the sheet offers four tiles and two rows', (tester) async {
    final (workspace, console) = await _open(tester);
    addTearDown(() {
      final gateway = workspace.gateway;
      workspace.dispose();
      unawaited(gateway.dispose());
    });
    await _mount(tester, workspace, console);
    await _openSheet(tester);

    for (final tile in ['Photo', 'Library', 'File', 'Video']) {
      expect(find.text(tile), findsOneWidget, reason: tile);
    }
    expect(find.text('Paste from the clipboard'), findsOneWidget);
    expect(find.text('Reference a path on the server'), findsOneWidget);

    // Screen recording is the one the control plane genuinely cannot do.
    expect(find.textContaining('recording'), findsNothing);
  });

  testWidgets('and hides the camera where there is none', (tester) async {
    // macOS has no image_picker camera. A tile that opens nothing is worse
    // than a tile that is not there.
    final (workspace, console) = await _open(tester);
    addTearDown(() {
      final gateway = workspace.gateway;
      workspace.dispose();
      unawaited(gateway.dispose());
    });
    await _mount(
      tester,
      workspace,
      console,
      media: FakeMedia(hasCamera: false),
    );
    await _openSheet(tester);

    expect(find.text('Photo'), findsNothing);
    expect(find.text('Video'), findsNothing);
    expect(find.text('Library'), findsOneWidget, reason: 'still has files');
    expect(find.text('File'), findsOneWidget);
  });

  testWidgets('the server-path source starts an @ reference', (tester) async {
    // `@` completion already existed but you had to know to type it. The menu
    // is where people look.
    final (workspace, console, socket) = await _openWithSocket(tester);
    addTearDown(() {
      final gateway = workspace.gateway;
      workspace.dispose();
      unawaited(gateway.dispose());
    });
    await _mount(tester, workspace, console);

    await tester.tap(find.byTooltip('Attach something'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Reference a path on the server'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '@');

    // And it really did ask the server, rather than only typing a character:
    // completion resolves against the session's cwd, which is the whole point
    // of putting this in the menu.
    expect(socket.lastOf('complete.path'), isNotNull);
    socket.reply('complete.path', {'completions': <Object>[]});
    await tester.pump();
  });

  testWidgets('pasting puts clipboard text in the field, not a file', (
    tester,
  ) async {
    // A pasted snippet is something to talk about. Text in the prompt is
    // cheaper and more useful to the model than a file it has to open.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': 'a pasted snippet'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final (workspace, console) = await _open(tester);
    addTearDown(() {
      final gateway = workspace.gateway;
      workspace.dispose();
      unawaited(gateway.dispose());
    });
    await _mount(tester, workspace, console);

    await tester.tap(find.byTooltip('Attach something'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Paste from the clipboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, contains('a pasted snippet'));
  });
}
