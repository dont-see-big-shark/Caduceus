/// Drives the app to each redesigned surface and holds it there to be seen.
///
/// This exists because this machine's Xcode has no `Developer/Applications`,
/// so there is no Simulator window to click and no way to reach the drawer or
/// the command palette by hand. The test opens each surface and parks for a
/// few seconds; a `simctl io screenshot` running alongside catches it.
///
/// It asserts as it goes, so it is still a test and not only a puppet — but
/// its real job is to make blind UI work visible.
///
///   `flutter test integration_test/design_tour_test.dart -d SIMULATOR_UDID`
///
/// **Afterwards run `flutter build ios`.** A device test run rewrites
/// FLUTTER_TARGET to a temp listener that is then deleted, and the next Xcode
/// build fails with "PhaseScriptExecution failed" for that reason and no
/// other. See ios_touch_test.dart.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/design/aurora.dart';
import 'package:caduceus/design/glass.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:caduceus/workspace.dart';
import 'package:caduceus/workspace_screen.dart';
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

  void event(String type, String sid, Map<String, dynamic> payload) => _in.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': type, 'session_id': sid, 'payload': payload},
    }),
  );
}

const _sessions = {
  'sessions': [
    {
      'id': 's1',
      'title': 'Reconnect strategy for the websocket',
      'preview': '',
      'started_at': 1785000000,
      'message_count': 102,
      'source': 'desktop',
    },
    {
      'id': 's2',
      'title': 'Wanning food recommendations',
      'preview': '',
      'started_at': 1784900000,
      'message_count': 11,
      'source': 'tui',
    },
    {
      'id': 's3',
      'title': 'Why the sky is blue',
      'preview': '',
      'started_at': 1784800000,
      'message_count': 2,
      'source': 'telegram',
    },
  ],
};

/// Long enough for a screenshot taken from another shell to land inside it.
const _hold = Duration(seconds: 6);

/// Holds a surface on screen, pumping the whole time.
///
/// A single `pump(6s)` produces one frame six seconds later, so anything mid
/// animation — a staggered list arriving, the composer's rim light — is caught
/// frozen at whatever value it had. That is how the command palette came back
/// from a screenshot looking like an empty sheet when its rows were merely
/// part-way through their entrance.
Future<void> hold(WidgetTester tester, [Duration total = _hold]) async {
  final frames = total.inMilliseconds ~/ 50;
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Both modes. Light is not dark with the colours swapped, and the two bugs
  // that shipped in it — an unreadable status pill, unreadable danger text —
  // were both on surfaces no screenshot had ever covered.
  for (final mode in Brightness.values) {
    testWidgets('a tour of the redesigned surfaces in ${mode.name}', (
      tester,
    ) async {
      // Ambient loops are live here on purpose: this run is about how it looks,
      // and the aurora and the composer rim are half of that. Nothing below
      // uses pumpAndSettle for exactly that reason.
      Materials.ambientPaused.value = false;

      final socket = _Socket();
      final gateway = HermesGateway(
        HermesEndpoint.tunnelled(token: 't', port: 9219),
        connector: (_) async => socket,
      );
      await gateway.connect();
      final workspace = Workspace(gateway);

      await tester.pumpWidget(
        MaterialApp(
          theme: caduceusTheme(mode),
          // The app wraps every route in `Aurora` from `main.dart`'s builder,
          // and the theme makes every scaffold transparent so that background
          // shows through. Without it here the tour was screenshotting the
          // engine's bare black behind the chrome — invisible in dark mode,
          // and the first light run made it obvious.
          builder: (context, child) => Aurora(child: child ?? const SizedBox()),
          home: WorkspaceScreen(workspace: workspace),
        ),
      );
      await tester.pump();
      socket.reply('session.list', _sessions);
      await tester.pump();
      socket.reply('session.resume', {
        'session_id': 'live1',
        'resumed': 's1',
        'running': false,
        'info': {'model': 'glm-5-2-260617', 'cwd': '/srv/caduceus'},
        'messages': [
          {'role': 'user', 'text': 'Look at the websocket reconnect strategy'},
          {
            'role': 'assistant',
            'text':
                'Exponential backoff with 20% jitter, capped at 8 s. '
                'Heartbeat every 15 s; two consecutive misses mark it offline '
                'and queued prompts are written to disk.\n\n'
                '- `backoff`: 0.5 s → 8 s\n'
                '- `heartbeat`: 15 s\n',
          },
        ],
      });
      await tester.pump(const Duration(milliseconds: 400));

      // 1 — the conversation, glass over an opaque transcript.
      expect(find.byType(GlassPanel), findsWidgets);
      await hold(tester);

      // 2 — a turn running: the composer's rim lights and send becomes stop.
      socket.event('message.start', 'live1', const {});
      await tester.pump();
      socket.event('reasoning.delta', 'live1', const {
        'text': 'Reading lib/transport/ws_channel.dart to check the backoff.',
      });
      socket.event('tool.start', 'live1', const {
        'name': 'read_file',
        'id': 't1',
        'context': 'lib/transport/ws_channel.dart',
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byIcon(Icons.stop_rounded),
        findsOneWidget,
        reason: 'send turns into stop while a turn runs',
      );
      await hold(tester);

      socket.event('tool.end', 'live1', const {
        'id': 't1',
        'name': 'read_file',
        'ok': true,
        'output': '218 lines · websocket reconnect policy',
      });
      socket.event('message.delta', 'live1', const {
        'text': 'The cap is 8 seconds today. Want it raised to 30?',
      });
      await tester.pump(const Duration(milliseconds: 400));
      await hold(tester);

      // 3 — the drawer: glass sliding over the conversation.
      socket.event('message.complete', 'live1', const {});
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Sessions'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('New session'), findsOneWidget);
      await hold(tester);

      await tester.tapAt(const Offset(360, 400));
      await tester.pump(const Duration(milliseconds: 400));

      // 4 — the command palette, on the thickest glass in the system.
      //
      // The catalog is requested *by* the first slash, not before it — that
      // ordering is the bug the palette-dismiss work fixed, so the tour has to
      // follow it too: type, then answer.
      await tester.enterText(find.byType(TextField).first, '/');
      await tester.pump(const Duration(milliseconds: 300));
      socket.reply('commands.catalog', {
        'pairs': [
          ['/undo', 'Undo the last exchange'],
          ['/compress', 'Summarise older messages'],
          ['/checkpoints', 'File checkpoints'],
          ['/model', 'Switch the model'],
        ],
      });
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('/undo'), findsOneWidget);
      await hold(tester);

      // 5 — the session menu: the same anchored menu as the desktop header,
      // so a phone and a Mac present one action surface.
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('Session actions'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Copy transcript'), findsOneWidget);
      await hold(tester);

      workspace.dispose();
      await gateway.dispose();
    });
  }
}
