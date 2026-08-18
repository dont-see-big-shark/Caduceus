/// Startup preset seeding, pinned at the storage interface.
library;

import 'dart:convert';

import 'package:caduceus/backends/claw_identity.dart';
import 'package:caduceus/connection_store.dart';
import 'package:caduceus/startup_presets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('compiled defaults contain no credentials', () {
    expect(startupPresets.connectionUrl, isEmpty);
    expect(startupPresets.connectionToken, isEmpty);
    expect(startupPresets.openClawUrl, isEmpty);
    expect(startupPresets.openClawToken, isEmpty);
    expect(startupPresets.openClawSeed, isEmpty);
    expect(startupPresets.hermesUrl, isEmpty);
    expect(startupPresets.hermesToken, isEmpty);
  });

  test('a partial preset is ignored rather than saved as unusable', () async {
    final store = ConnectionStore();

    await seedStartupPresets(
      store,
      const StartupPresets(openClawUrl: 'wss://partial.test'),
    );

    expect(await store.list(), isEmpty);
    expect(
      await ClawIdentityStore().deviceIdFor(
        StartupPresets.openClawConnectionId,
      ),
      isNull,
    );
  });

  test(
    'complete presets save only their own credentials and device seed',
    () async {
      final store = ConnectionStore();

      final deviceSeed = base64Encode(List.filled(32, 7));
      await seedStartupPresets(
        store,
        StartupPresets(
          openClawUrl: 'wss://openclaw.test',
          openClawToken: 'openclaw-token',
          openClawSeed: deviceSeed,
          hermesUrl: 'https://hermes.test',
          hermesToken: 'hermes-token',
        ),
      );

      final byId = {
        for (final connection in await store.list()) connection.id: connection,
      };
      final openClaw = byId[StartupPresets.openClawConnectionId]!;
      final hermes = byId[StartupPresets.hermesConnectionId]!;

      expect(openClaw.backendId, SavedConnection.openclaw);
      expect(openClaw.requestAdmin, isTrue);
      expect(await store.tokenFor(openClaw.id), 'openclaw-token');
      expect(
        await ClawIdentityStore().deviceIdFor(openClaw.id),
        isNotNull,
        reason: 'the seed should be installed without generating a new device',
      );

      expect(hermes.backendId, SavedConnection.hermes);
      expect(await store.tokenFor(hermes.id), 'hermes-token');
    },
  );

  test(
    'a preset never overwrites a connection the user already owns',
    () async {
      final store = ConnectionStore();
      await store.save(
        id: StartupPresets.hermesConnectionId,
        label: 'Production',
        url: 'https://production.test',
        token: 'existing-token',
      );

      await seedStartupPresets(
        store,
        const StartupPresets(
          hermesUrl: 'https://development.test',
          hermesToken: 'development-token',
        ),
      );

      final connection = (await store.list()).single;
      expect(connection.label, 'Production');
      expect(connection.url, 'https://production.test');
      expect(await store.tokenFor(connection.id), 'existing-token');
    },
  );
}
