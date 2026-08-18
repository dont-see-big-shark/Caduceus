/// The *Request administrator* control — `SavedConnection.requestAdmin` and
/// the scopes it asks for.
///
/// Least privilege is the default: a connection asks for chatScopes unless
/// the person explicitly turned on administrator, and the saved record keeps
/// that choice across launches. `operator.admin` is what lets the shared
/// memory base write MEMORY.md.
library;

import 'package:caduceus/backend_factory.dart';
import 'package:caduceus/backends/claw_backend.dart';
import 'package:caduceus/connection_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('requestAdmin survives a save and a reload', () async {
    final store = ConnectionStore();
    final saved = await store.save(
      label: 'nas',
      url: 'wss://example.test',
      token: 'secret',
      backendId: SavedConnection.openclaw,
      requestAdmin: true,
    );

    expect(saved.requestAdmin, isTrue);
    final restored = SavedConnection.fromJson(saved.toJson());
    expect(restored.requestAdmin, isTrue);

    // Default is off, and an off record omits the field so an older build
    // reading it is unaffected.
    final plain = await store.save(
      label: 'nas2',
      url: 'wss://example2.test',
      token: 'secret',
      backendId: SavedConnection.openclaw,
    );
    expect(plain.requestAdmin, isFalse);
    expect(plain.toJson().containsKey('requestAdmin'), isFalse);
    expect(SavedConnection.fromJson(plain.toJson()).requestAdmin, isFalse);
  });

  test('buildBackend asks for admin only when requestAdmin is on', () async {
    final plain = await buildBackend(
      SavedConnection(
        id: 'c1',
        label: 'nas',
        url: 'wss://example.test',
        backendId: SavedConnection.openclaw,
      ),
      'secret',
    );
    final plainClaw = plain.backend as ClawBackend;
    expect(plainClaw.gateway.scopes, isNot(contains('operator.admin')));
    expect(plainClaw.gateway.scopes, ClawGateway.chatScopes);

    final admin = await buildBackend(
      SavedConnection(
        id: 'c2',
        label: 'nas',
        url: 'wss://example.test',
        backendId: SavedConnection.openclaw,
        requestAdmin: true,
      ),
      'secret',
    );
    final adminClaw = admin.backend as ClawBackend;
    expect(adminClaw.gateway.scopes, contains('operator.admin'));
    expect(adminClaw.gateway.scopes, ClawGateway.adminScopes);
  });
}
