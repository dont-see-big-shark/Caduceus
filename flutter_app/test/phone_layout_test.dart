/// The desktop shell does not fit a phone, and nothing else would notice.
///
/// Every layout test so far ran at the default 800×600, which is wider than
/// the compact breakpoint. An iPhone 17 Pro is 393 points wide: a 300-point
/// sidebar leaves 93 points of conversation, and a panel that asks for 620
/// overflows the screen by 227.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
import 'package:caduceus/widgets/panel_frame.dart';
import 'package:caduceus/workspace.dart';
import 'package:caduceus/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

/// iPhone 17 Pro, logical points.
const _phone = Size(393, 852);

/// iPad Pro 13" portrait, logical points.
const _tablet = Size(1024, 1366);

/// The same iPhone on its side. Wider than the breakpoint, so it gets the
/// split layout — and only 393 points tall, which is the case a portrait-only
/// test never exercises.
const _phoneLandscape = Size(852, 393);

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

  void event(String type, String sessionId, Map<String, dynamic> payload) =>
      _in.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {'type': type, 'session_id': sessionId, 'payload': payload},
        }),
      );

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

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a phone shows one pane, not a sidebar beside a transcript', (
    tester,
  ) async {
    final (workspace, socket) = await _connected();
    addTearDown(workspace.dispose);
    _size(tester, _phone);

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(workspace: workspace)),
    );
    await tester.pump();
    socket.reply('session.list', {
      'sessions': [
        {'id': 's1', 'title': 'A session', 'message_count': 4},
      ],
    });
    // A non-empty list is opened on arrival, so the resume has to be answered
    // or the console sits on a spinner and nothing ever settles.
    await tester.pump();
    socket.reply('session.resume', _resumed('s1'));
    await tester.pumpAndSettle();

    expect(
      find.byType(VerticalDivider),
      findsNothing,
      reason: 'the split layout must not be used at phone width',
    );
    // The conversation is the screen now; sessions are behind the app bar.
    expect(
      find.byType(Drawer),
      findsNothing,
      reason: 'the drawer is closed until asked for',
    );
    expect(
      find.byTooltip('Sessions'),
      findsOneWidget,
      reason: 'and there has to be a way to ask for it',
    );

    await tester.tap(find.byTooltip('Sessions'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('A session'),
      ),
      findsOneWidget,
      reason: 'the session list lives in the drawer',
    );
  });

  testWidgets('a tablet keeps the split layout', (tester) async {
    final (workspace, socket) = await _connected();
    addTearDown(workspace.dispose);
    _size(tester, _tablet);

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(workspace: workspace)),
    );
    await tester.pump();
    socket.reply('session.list', {'sessions': <Object>[]});
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Show sessions'),
      findsOneWidget,
      reason: 'there is room for both panes here — the icon rail stays',
    );
  });

  testWidgets('picking a session from the drawer opens it', (tester) async {
    final (workspace, socket) = await _connected();
    addTearDown(workspace.dispose);
    _size(tester, _phone);

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(workspace: workspace)),
    );
    await tester.pump();
    // Two rows, because the top one is already open on arrival — the switch
    // worth testing is to the *other* one.
    socket.reply('session.list', {
      'sessions': [
        {'id': 's1', 'title': 'A session', 'message_count': 4},
        {'id': 's2', 'title': 'Another session', 'message_count': 9},
      ],
    });
    await tester.pump();
    socket.reply('session.resume', _resumed('s1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Another session'));
    await tester.pump();
    socket.reply('session.resume', _resumed('s2'));
    await tester.pumpAndSettle();

    expect(workspace.activeId, 's2');
    expect(
      find.byType(ConsoleView),
      findsOneWidget,
      reason: 'picking a session shows it',
    );
    expect(
      find.byType(Drawer),
      findsNothing,
      reason: 'and closes the drawer behind it',
    );
  });

  testWidgets('the console header fits a phone', (tester) async {
    // This is the defect the simulator found and the widget suite did not:
    // the header row packed a session id, a working directory, a menu and a
    // model name, and overflowed 393 points with the striped marker straight
    // through the middle of it. The existing accessibility test runs at
    // 900x640, which is wide enough to hide it.
    // Disposed at the end of the body, not in a teardown: `running: true`
    // starts the 1 Hz elapsed-time timer and the binding checks for pending
    // timers before teardowns run.
    final (workspace, socket) = await _connected();
    _size(tester, _phone);

    final opening = workspace.open('20260802_125608_7a70dd');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': '20260802_125608_7a70dd',
      'running': true,
      'info': {
        'model': 'glm-5-2-260617',
        'cwd': '/srv/a/long/enough/path/to/matter',
      },
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      tester.takeException(),
      isNull,
      reason: 'the header overflowed at phone width',
    );

    workspace.dispose();
  });

  testWidgets('a phone on its side still lays out', (tester) async {
    // 852 points wide clears the breakpoint, so this takes the split path at
    // a height no desktop window ever has.
    final (workspace, socket) = await _connected();
    addTearDown(workspace.dispose);
    _size(tester, _phoneLandscape);

    await tester.pumpWidget(
      MaterialApp(home: WorkspaceScreen(workspace: workspace)),
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

    expect(tester.takeException(), isNull);
    expect(
      find.byTooltip('Show sessions'),
      findsOneWidget,
      reason: '852 points clears the breakpoint, so the split stays',
    );
  });

  testWidgets('the console survives a keyboard in landscape', (tester) async {
    // The worst geometry the app has: 393 points of height with ~200 of it
    // taken by the keyboard, leaving the header, the turn timeline and the
    // composer to share what is left.
    final (workspace, socket) = await _connected();
    _size(tester, _phoneLandscape);

    final opening = workspace.open('s1');
    await tester.pump();
    socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': true,
      'info': {'model': 'glm-5-2-260617', 'cwd': '/srv/project'},
      'messages': <Object>[],
    });
    final console = await opening;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: _phoneLandscape,
            viewInsets: EdgeInsets.only(bottom: 200),
          ),
          child: Scaffold(
            body: ConsoleView(workspace: workspace, console: console),
          ),
        ),
      ),
    );
    await tester.pump();
    // Everything on at once, in the smallest space available.
    socket.event('reasoning.delta', 'live1', {'text': 'thinking ' * 30});
    socket.event('tool.start', 'live1', {
      'tool_id': 't1',
      'name': 'terminal',
      'context': 'a long command line',
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      tester.takeException(),
      isNull,
      reason: 'the console overflowed with the keyboard up in landscape',
    );

    workspace.dispose();
  });

  testWidgets('a panel fits a phone in landscape too', (tester) async {
    // 393 points of height, less than the 400 several panels ask for.
    _size(tester, _phoneLandscape);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PanelFrame(
              preferredWidth: 620,
              preferredHeight: 460,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.getSize(find.byType(PanelFrame));
    expect(box.height, lessThanOrEqualTo(_phoneLandscape.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a panel never asks for more width than the screen has', (
    tester,
  ) async {
    _size(tester, _phone);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PanelFrame(
              preferredWidth: 620,
              preferredHeight: 460,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.getSize(find.byType(PanelFrame));
    expect(
      box.width,
      lessThanOrEqualTo(_phone.width),
      reason:
          'a 620-point panel on a 393-point screen clipped its own '
          'content on both sides',
    );
    expect(box.height, lessThanOrEqualTo(_phone.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a panel keeps its preferred size when there is room', (
    tester,
  ) async {
    _size(tester, _tablet);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PanelFrame(
              preferredWidth: 620,
              preferredHeight: 460,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(PanelFrame)).width,
      620,
      reason: 'clamping must not shrink panels that already fit',
    );
  });
}
