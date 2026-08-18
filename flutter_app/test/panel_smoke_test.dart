/// Opens every panel and asserts it does not throw.
///
/// Cheap and worth having: the last defect of this shape was a `Spacer` inside
/// `AlertDialog.actions`, which throws on build because an OverflowBar rejects
/// `Expanded`. Nothing caught it, because nothing had ever opened that dialog
/// with a real entry in it. Panels are the least-visited screens in the app and
/// therefore the ones most likely to rot.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/console_view.dart';
import 'package:caduceus/workspace.dart';
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

  final _answered = <Object>{};

  /// Answers every outstanding call with an empty result.
  ///
  /// Deliberately not a table of method names: guessing them wrong leaves the
  /// call unanswered and its 30-second timeout pending, which fails the test
  /// for a reason that has nothing to do with the panel. Every list panel
  /// parses defensively (`(raw['x'] as List?) ?? const []`), so an empty
  /// object is a legitimate — and interesting — answer: it exercises each
  /// panel's *nothing to show* state, which is the one nobody looks at.
  void answerEverything() {
    for (final frame in sent) {
      final id = frame['id'];
      if (id == null || !_answered.add(id)) continue;
      _in.add(
        jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': <String, Object>{}}),
      );
    }
  }
}

void main() {
  for (final entry in const [
    ('File checkpoints…', 'checkpoints'),
    ('Background processes…', 'processes'),
    ('Agents…', 'agents'),
    ('Journey — what it learned…', 'journey'),
    ('Toolsets, skills, plugins…', 'server'),
    ('Usage and context…', 'stats'),
    ('Working directory…', 'cwd'),
    ('Find in conversation…', 'find'),
  ]) {
    testWidgets('${entry.$2} opens without throwing', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

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
        'info': {'model': 'm', 'cwd': '/srv/x'},
        'messages': <Object>[],
      });
      final console = await opening;
      addTearDown(() {
        workspace.dispose();
        unawaited(gateway.dispose());
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsoleView(
              workspace: workspace,
              console: console,
              compactChrome: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // The phone's session menu is the same anchored menu as the desktop
      // header now, so panels open straight from a row rather than through
      // the command palette.
      await tester.tap(find.byTooltip('Session actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.$1));
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Session actions'),
        findsOneWidget,
        reason:
            'the menu should have closed, which proves the row was '
            'really tapped and the panel really opened',
      );

      socket.answerEverything();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // A second round: some panels chain a call off the first reply.
      socket.answerEverything();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester.takeException(),
        isNull,
        reason: '${entry.$2} threw while opening',
      );
    });
  }
}
