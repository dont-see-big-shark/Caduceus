/// Settings as the design draws it: groups you drill into, not one flat list.
///
/// The shape follows the window — master-detail where there is room for two
/// columns, a list that pushes where there is not. The value on each row is
/// the part worth having: Gateway · connected answers the question without
/// opening anything.
library;

import 'dart:async';

import 'package:caduceus/settings/settings_pages.dart';
import 'package:caduceus/l10n/app_localizations.dart';
import 'package:caduceus/settings_page.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

const _phone = Size(393, 852);
const _mac = Size(1280, 800);

Future<Workspace> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
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
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPage(workspace: workspace),
    ),
  );
  await tester.pump();
  return workspace;
}

void main() {
  testWidgets('every group is reachable from the master list', (tester) async {
    await _pump(tester, _phone);

    for (final group in SettingsGroupId.values) {
      expect(find.text(group.label), findsOneWidget, reason: group.label);
    }
  });

  testWidgets('a phone pushes into a group and comes back', (tester) async {
    await _pump(tester, _phone);

    // The master list is one column, not two: 393 points of master-detail is
    // two columns of nothing.
    expect(find.text('Pick a group on the left'), findsNothing);

    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();

    expect(find.textContaining('The microphone types'), findsOneWidget);
    expect(
      find.text('Gateway'),
      findsNothing,
      reason: 'the list is gone — this pushed, it did not expand',
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Gateway'), findsOneWidget);
  });

  testWidgets('a Mac shows both halves at once', (tester) async {
    await _pump(tester, _mac);

    // The design opens on the Model page, not an empty picker.
    expect(find.text('Pick a group on the left'), findsNothing);

    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();

    expect(find.textContaining('The microphone types'), findsOneWidget);
    expect(
      find.text('Gateway'),
      findsOneWidget,
      reason: 'the nav stays — that is what the width is for',
    );
  });

  testWidgets('the open group is named by the page header', (tester) async {
    await _pump(tester, _mac);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    // The design's `page-title`: the open page carries its own title and a
    // one-line subtitle, so the right pane is never anonymous.
    expect(
      find.text('Dark material, motion and type hierarchy'),
      findsOneWidget,
    );
  });

  testWidgets('values live on the pages, not the nav', (tester) async {
    await _pump(tester, _phone);

    // The nav is for navigating — the design's compact settings-nav-item has
    // no value on it. The value is on the page: with no session open, the
    // Model page says so rather than staying blank.
    await tester.tap(find.text('Model'));
    await tester.pumpAndSettle();

    expect(find.text('no session open'), findsOneWidget);
  });

  testWidgets("the master list is the design's 4 groups x 17 items", (
    tester,
  ) async {
    await _pump(tester, _mac);

    // Group headers — 核心 / 设备 / 账户与连接 / 系统, mono uppercase.
    for (final label in ['CORE', 'DEVICE', 'ACCOUNT & CONNECTION', 'SYSTEM']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // The design's settings-nav, in its order.
    for (final group in SettingsGroupId.values) {
      expect(find.text(group.label), findsWidgets, reason: group.label);
    }
    expect(SettingsGroupId.values.length, 17);
    expect(SettingsSection.values.length, 4);
  });

  testWidgets('approvals offers only the modes Hermes documents', (
    tester,
  ) async {
    await _pump(tester, _phone);

    // The design's Safety page hosts the approvals surface.
    await tester.tap(find.text('Safety'));
    await tester.pumpAndSettle();

    // config.set echoes back whatever string it is handed without validating
    // it, so an invented mode would be accepted here and then quietly mean
    // nothing to the agent. Only what the server's own catalogue names.
    expect(ApprovalMode.values.map((m) => m.key), ['smart', 'yolo']);
    for (final mode in ApprovalMode.values) {
      expect(find.text(mode.label), findsOneWidget);
    }

    // And it says what it would change, because the scope is the whole risk.
    expect(find.textContaining('session'), findsWidgets);
  });
}
