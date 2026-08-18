/// Touch behaviour on the device, not on a forced ThemeData.
///
/// The widget suite sets `ThemeData(platform: TargetPlatform.iOS)` to exercise
/// the touch branches. That proves the branches work; it does not prove the
/// app takes them on a real iPhone, because the value that actually decides is
/// the platform the framework reports at runtime. This runs on the simulator
/// and asserts the same things without forcing anything.
///
///   `flutter test integration_test/ios_touch_test.dart -d SIMULATOR_UDID`
///
/// **Afterwards, rebuild before opening Xcode.** Running an integration test
/// on a device rewrites `ios/Flutter/Generated.xcconfig` to point FLUTTER_TARGET
/// at a temporary listener file under `/var/folders/…`. That file is deleted
/// when the run ends, so the next Xcode build fails in the Run Script phase
/// with the useless message "Command PhaseScriptExecution failed with a nonzero
/// exit code" — the real cause is several lines above it, a missing
/// `listener.dart`. Any `flutter build ios` puts FLUTTER_TARGET back to
/// `lib/main.dart`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/backends/hermes_mapping.dart';
import 'package:caduceus/console_view.dart';
import 'package:caduceus/widgets/turn_timeline.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:integration_test/integration_test.dart';

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

bool _fieldFocused(WidgetTester tester) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .any((f) => f.focusNode.hasFocus);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<(Workspace, _Socket, SessionConsole)> setUpConsole(
    WidgetTester tester,
  ) async {
    final socket = _Socket();
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
      'messages': <Object>[],
    });
    final console = await opening;
    return (workspace, socket, console);
  }

  testWidgets('the device really is a touch platform', (tester) async {
    // If this fails, every touch branch in the app is dead code on the device
    // and the widget tests that force the platform were proving nothing.
    expect(
      defaultTargetPlatform,
      anyOf(TargetPlatform.iOS, TargetPlatform.android),
      reason: 'this test is only meaningful on a phone or a simulator',
    );
  });

  testWidgets('opening a session does not raise the keyboard', (tester) async {
    final (workspace, _, console) = await setUpConsole(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      _fieldFocused(tester),
      isFalse,
      reason: 'the keyboard covers half the transcript the user just opened',
    );

    workspace.dispose();
  });

  testWidgets('tapping the conversation puts the keyboard away', (
    tester,
  ) async {
    final (workspace, _, console) = await setUpConsole(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConsoleView(workspace: workspace, console: console),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(_fieldFocused(tester), isTrue, reason: 'the field was tapped');

    await tester.tapAt(const Offset(200, 220));
    await tester.pumpAndSettle();
    expect(_fieldFocused(tester), isFalse);

    workspace.dispose();
  });

  testWidgets('the reasoning pane brings no scroll view of its own', (
    tester,
  ) async {
    final (workspace, _, console) = await setUpConsole(tester);
    console.appendLocalPrompt('go');
    console.handle(
      agentEventFromHermes(
        'live1',
        GatewayEvent(
          type: 'reasoning.delta',
          sessionId: 'live1',
          payload: {'text': 'a long thought line\n' * 60},
        ),
      )!,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ListenableBuilder(
                listenable: console,
                builder: (c, _) => TurnTimeline(
                  console: console,
                  turn: console.turns.isEmpty
                      ? Turn(anchorBlock: 0)
                      : console.turns.last,
                  isCurrent: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(SingleChildScrollView).evaluate().length,
      0,
      reason:
          'a capped pane inside the turn means a drag can move either '
          'it or the conversation, with nothing on screen to say which',
    );

    workspace.dispose();
  });
}
