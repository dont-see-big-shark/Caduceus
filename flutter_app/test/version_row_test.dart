/// The build that is actually running, on the screen someone reads it from.
///
/// A version constant written into the source drifts the first time someone
/// ships without touching it, and a version is worth showing only while it is
/// true — this is the line a user reads out when a session misbehaves against
/// a server nobody else can see.
library;

import 'package:caduceus/design/theme.dart';
import 'package:caduceus/settings/settings_pages.dart';
import 'package:caduceus/settings_page.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> _pump(WidgetTester tester) async {
  final gateway = HermesGateway(
    HermesEndpoint.tunnelled(token: 't', port: 9219),
  );
  final workspace = Workspace(gateway);
  addTearDown(workspace.dispose);

  // Opens straight into the About page — the row it sits behind is the last
  // of seventeen in the master list, and scrolling a lazy list to reach it
  // adds nothing to what is being tested.
  await tester.pumpWidget(
    MaterialApp(
      theme: caduceusTheme(Brightness.dark),
      home: SettingsPage(
        workspace: workspace,
        initialGroup: SettingsGroupId.about,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settles blank where the platform cannot answer', (tester) async {
    // Declared first on purpose: PackageInfo caches the first answer it gets
    // for the life of the isolate and offers no way to clear it, so this is
    // the only point at which the un-mocked path is still reachable. Every
    // platform channel is absent under `flutter test`, which is the same
    // shape as a platform where the plugin is not registered — and the row is
    // supplementary, so it must never be why Settings fails to open.
    await _pump(tester);

    // About is now a settings page behind the 系统 group, not a group in the
    // master list.
    expect(find.text('Version'), findsOneWidget);

    expect(find.text('Version'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('shows the bundle version and build number', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Caduceus',
      packageName: 'dev.caduceus.app',
      version: '0.1.0',
      buildNumber: '2041',
      buildSignature: '',
    );

    await _pump(tester);

    expect(find.text('0.1.0 · build 2041'), findsOneWidget);
  });
}
