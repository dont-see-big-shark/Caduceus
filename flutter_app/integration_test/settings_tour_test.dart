/// The settings page, and the degraded material, in both modes.
///
/// Two surfaces nothing had ever looked at: settings was never on the tour,
/// and the degraded material had no way to be switched on until now. Both are
/// exactly where the last several light-mode bugs came from — a value chosen
/// while looking at dark mode and then used unconditionally.
///
///   `flutter test integration_test/settings_tour_test.dart -d SIMULATOR_UDID`
///
/// **Afterwards run `flutter build ios`.** See ios_touch_test.dart.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/design/aurora.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:caduceus/settings_page.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Socket implements GatewayTransport {
  final _in = StreamController<String>.broadcast();
  @override
  Stream<String> get inbound => _in.stream;
  @override
  void send(String d) => jsonDecode(d);
  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }
}

Future<void> hold(WidgetTester tester, [int seconds = 6]) async {
  for (var i = 0; i < seconds * 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in Brightness.values) {
    testWidgets('settings and degraded material in ${mode.name}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      Materials.ambientPaused.value = false;
      Materials.degraded.value = false;

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
          builder: (context, child) =>
              Aurora(child: child ?? const SizedBox()),
          home: SettingsPage(workspace: workspace),
        ),
      );
      await tester.pump();

      // 1 — the page as it normally is: glass groups over the aurora.
      expect(find.text('Reduce visual effects'), findsOneWidget);
      await hold(tester);

      // 2 — the same page with the effects off. Nothing should move.
      final before = tester.getSize(find.byType(Switch).first);
      await tester.tap(find.text('Reduce visual effects'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(Materials.degraded.value, isTrue);
      expect(
        tester.getSize(find.byType(Switch).first),
        before,
        reason: '视觉降级但结构完全一致 — the layout is the promise',
      );
      await hold(tester);

      Materials.degraded.value = false;
      workspace.dispose();
      await gateway.dispose();
    });
  }
}
