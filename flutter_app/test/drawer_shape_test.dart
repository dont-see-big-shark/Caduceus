/// The drawer, against what the design draws.
///
/// It had drifted in four ways at once: the search field was hidden behind a
/// toggle, New session was the screen's second brass control, Settings was a
/// glyph in the header rather than a row that says what is inside it, and
/// every session row's second line read the same word.
library;

import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/widgets/session_drawer.dart';
import 'package:caduceus/widgets/session_row.dart';
import 'package:caduceus/design/components.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

Future<Workspace> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final gateway = HermesGateway(
    HermesEndpoint.tunnelled(token: 't', port: 9219),
  );
  final workspace = Workspace(gateway);
  addTearDown(() {
    workspace.dispose();
    unawaited(gateway.dispose());
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: caduceusTheme(Brightness.dark),
      home: Scaffold(
        body: SessionDrawer(
          workspace: workspace,
          onOpenSession: (_) {},
          onNewSession: () {},
          onOpenSettings: () {},
          onOpenPanel: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
  return workspace;
}

void main() {
  testWidgets('search is there without being asked for', (tester) async {
    await _pump(tester);

    // Not behind a magnifier that swaps the header for a field: searching is
    // one of the two things this drawer is for, and there was room all along.
    expect(find.text('Search sessions'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the drawer spends no brass', (tester) async {
    await _pump(tester);

    // One brass control per screen, and the composer's send button already
    // spends it. New session is glass here.
    expect(find.text('New session'), findsOneWidget);
    expect(find.byType(BrassButton), findsNothing);
  });

  testWidgets('settings lives in the segmented header, profile in the footer', (
    tester,
  ) async {
    await _pump(tester);

    // The design's drawer is head + segmented (Sessions / Panels / Settings),
    // so Settings is the segmented entry — exactly one.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);

    // The footer is the profile row — the connected backend, not a second
    // settings entry.
    expect(find.textContaining('Hermes'), findsOneWidget);
  });

  testWidgets('it signs its own name', (tester) async {
    await _pump(tester);

    expect(find.text('Caduceus'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget, reason: 'the mark, too');
  });

  _metaTests();
}

Widget _row({bool live = false, String model = ''}) => MaterialApp(
  theme: caduceusTheme(Brightness.dark),
  home: Scaffold(
    body: SessionRow(
      session: const AgentSession(
        id: 's1',
        title: 'Transport retry policy',
        preview: '',
        messageCount: 18,
        updatedAt: null,
        // Always "tui". That is the point of the test below.
        source: 'tui',
      ),
      selected: false,
      unread: false,
      live: live,
      model: model,
      onTap: () {},
    ),
  ),
);

void _metaTests() {
  testWidgets('a row says what the session is doing, not who made it', (
    tester,
  ) async {
    await tester.pumpWidget(_row());
    await tester.pump();

    // `source` is "tui" for every session the gateway has ever reported, so
    // it was the same word under every row — saying nothing, in the space of
    // something that would.
    expect(find.textContaining('tui'), findsNothing);
    expect(find.text('18 · idle'), findsOneWidget);
  });

  testWidgets('a running session says so', (tester) async {
    await tester.pumpWidget(_row(live: true));
    await tester.pump();
    expect(find.text('18 · running'), findsOneWidget);
  });

  testWidgets('and an open one names its model', (tester) async {
    await tester.pumpWidget(_row(model: 'gemini-3-flash'));
    await tester.pump();
    expect(find.text('18 · gemini-3-flash'), findsOneWidget);
  });
}
