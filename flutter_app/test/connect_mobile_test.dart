/// The connect screen on a phone — the design's `connectView`, full-width.
///
/// The design locks "移动端 360/390/430px 无横向滚动", and the connect screen
/// is the front door: the saved-server row (label, backend, url, admin
/// switch, forget) is the widest thing on it. It was rendering fine on a Mac
/// and overflowing a 393-point row — which nothing caught, because no test
/// had ever pumped it at phone width with a saved server in the list.
library;

import 'package:caduceus/connect_screen.dart';
import 'package:caduceus/connection_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _widths = <String, Size>{
  '360': Size(360, 800),
  '390': Size(390, 844),
  '430': Size(430, 932),
};

Future<void> _seedSavedServer() async {
  final store = ConnectionStore();
  await store.save(
    label: 'Home',
    url: 'https://hermes.home:8080/ppc418zqxi5zop92xdsmf2to',
    token: 'secret',
    backendId: SavedConnection.hermes,
  );
  await store.save(
    label: 'NAS',
    url: 'wss://fnos-nas.taild1398d.ts.net',
    token: 'secret',
    backendId: SavedConnection.openclaw,
    requestAdmin: true,
  );
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final entry in _widths.entries) {
    testWidgets('a saved server row lays out at ${entry.key}', (tester) async {
      await _seedSavedServer();
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: ConnectScreen(autoReconnect: false)),
      );
      await tester.pumpAndSettle();

      // Both saved rows are visible (not clipped off the right edge), and
      // nothing overflowed — a RenderFlex overflow would have thrown already.
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('NAS'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the add-server form lays out at 393', (tester) async {
    await _seedSavedServer();
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: ConnectScreen(autoReconnect: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add another server'));
    await tester.pumpAndSettle();

    // The four entries — the design's segmented 手动 / QR / 6位码 / mDNS.
    for (final label in ['Manual', 'QR', '6-digit', 'Discover']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
