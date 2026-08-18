/// Every screen, in both modes, at both sizes, at two text scales.
///
/// A grid rather than a list of cases, because every layout bug this app has
/// had came from a combination nobody had looked at: the header that fitted a
/// Mac window and overflowed a phone, the sidebar row whose fixed extent broke
/// under Dynamic Type, the light mode that was only ever seen on one screen.
///
/// Overflow is what widget tests are *better* at than screenshots — a
/// `RenderFlex overflowed` is a hard failure here and a thin yellow stripe in
/// a photograph, easy to miss at the edge of a frame.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
import 'package:caduceus/design/aurora.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/settings_page.dart';
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

  void event(String type, String sid, Map<String, dynamic> payload) => _in.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': type, 'session_id': sid, 'payload': payload},
    }),
  );
}

/// Long enough to wrap, with a table — the shapes that overflow.
const _answer =
    'Exponential backoff with 20% jitter, capped at 8 s. Heartbeat every '
    '15 s; two consecutive misses mark it offline.\n\n'
    '| setting | value |\n|---|---|\n| backoff | 0.5 s → 8 s |\n'
    '| heartbeat | 15 s |\n';

const _sizes = <String, Size>{
  // The design locks 移动端 360/390/430px 无横向滚动, so the phone column
  // runs all three widths plus the smallest iPhone in landscape.
  'phone 360': Size(360, 800),
  'phone 390': Size(390, 844),
  'phone 430': Size(430, 932),
  'phone landscape': Size(852, 393),
  'desktop': Size(1200, 800),
};

void main() {
  for (final mode in Brightness.values) {
    for (final entry in _sizes.entries) {
      for (final scale in [1.0, 1.6]) {
        final label = '${entry.key}, ${mode.name}, text ×$scale';

        testWidgets('the workspace lays out — $label', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

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
              // The app wraps every route in Aurora; without it the theme's
              // transparent scaffolds render on nothing.
              builder: (context, child) => Aurora(
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child ?? const SizedBox(),
                ),
              ),
              home: WorkspaceScreen(workspace: workspace),
            ),
          );
          await tester.pump();
          socket.reply('session.list', {
            'sessions': [
              {
                'id': 's1',
                'title': 'Reconnect strategy for the websocket transport',
                'message_count': 102,
                'source': 'desktop',
                'started_at': 1785000000,
              },
              {
                'id': 's2',
                'title': '万宁美食推荐攻略',
                'message_count': 11,
                'source': 'tui',
                'started_at': 1784900000,
              },
            ],
          });
          await tester.pump();
          socket.reply('session.resume', {
            'session_id': 'live1',
            'resumed': 's1',
            'running': false,
            'info': {'model': 'glm-5-2-260617', 'cwd': '/srv/caduceus'},
            'messages': [
              {'role': 'user', 'text': 'Look at the reconnect strategy'},
              {'role': 'assistant', 'text': _answer},
            ],
          });
          await tester.pump(const Duration(milliseconds: 400));

          expect(tester.takeException(), isNull, reason: label);

          // And while a turn is running, which adds the header's status line,
          // the rim light and the timeline.
          socket.event('message.start', 'live1', const {});
          socket.event('reasoning.delta', 'live1', const {
            'text':
                'Reading lib/transport/ws_channel.dart to check the '
                'backoff and the heartbeat interval.',
          });
          socket.event('tool.start', 'live1', const {
            'name': 'read_file',
            'id': 't1',
            'context': 'lib/transport/ws_channel.dart',
          });
          await tester.pump(const Duration(milliseconds: 400));

          expect(tester.takeException(), isNull, reason: '$label, streaming');

          workspace.dispose();
          // Not awaited: closing the gateway's broadcast streams never
          // completes inside a pumped test, and awaiting it hangs the whole
          // file until the runner kills the shell.
          unawaited(gateway.dispose());
        });

        testWidgets('settings lays out — $label', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

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
              builder: (context, child) => Aurora(
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child ?? const SizedBox(),
                ),
              ),
              home: SettingsPage(workspace: workspace),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(tester.takeException(), isNull, reason: label);

          workspace.dispose();
          // Not awaited: closing the gateway's broadcast streams never
          // completes inside a pumped test, and awaiting it hangs the whole
          // file until the runner kills the shell.
          unawaited(gateway.dispose());
        });
      }
    }
  }

  testWidgets('the console survives a keyboard at every text scale', (
    tester,
  ) async {
    // The worst geometry the app has: landscape, most of it keyboard.
    for (final scale in [1.0, 1.3, 1.6]) {
      tester.view.physicalSize = const Size(852, 393);
      tester.view.devicePixelRatio = 1.0;

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
        'running': true,
        'info': {'model': 'glm-5-2-260617', 'cwd': '/srv/project'},
        'messages': <Object>[],
      });
      final console = await opening;

      await tester.pumpWidget(
        MaterialApp(
          theme: caduceusTheme(Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(852, 393),
              viewInsets: const EdgeInsets.only(bottom: 200),
              textScaler: TextScaler.linear(scale),
            ),
            child: Aurora(
              child: Scaffold(
                body: ConsoleView(workspace: workspace, console: console),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull, reason: 'keyboard at ×$scale');

      workspace.dispose();
      unawaited(gateway.dispose());
    }
    tester.view.reset();
  });
}
