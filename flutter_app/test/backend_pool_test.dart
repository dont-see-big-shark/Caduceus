/// Holding more than one agent at once.
///
/// The app held exactly one `AgentBackend`, which is why the memory bridge
/// could not ask both servers anything in one breath. These pin the properties
/// that make a pool worth having rather than just possible: one unreachable
/// server must not cost the answers the others can give, a failure must be
/// *reported* rather than silently dropped, and the connection the workspace
/// already holds must be reused rather than opened twice.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backend_factory.dart';
import 'package:caduceus/backend_pool.dart';
import 'package:caduceus/connection_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A backend that does nothing but record whether it was connected and
/// disposed. Enough to pin ownership, which is what these tests are about.
class _FakeBackend implements AgentBackend {
  _FakeBackend(this.id, {this.connectThrows});

  @override
  final String id;

  final Object? connectThrows;

  var connects = 0;
  var disposes = 0;

  @override
  String get displayName => id;

  @override
  Future<void> connect() async {
    connects++;
    if (connectThrows != null) throw connectThrows!;
  }

  @override
  Future<void> dispose() async => disposes++;

  @override
  Future<List<MemoryEntry>> memory() async => const [];

  @override
  bool supports(Capability capability) => capability == Capability.memoryRead;

  @override
  AgentConnection get connectionState => AgentConnection.disconnected;

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, _FakeBackend> built;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
    built = {};
  });

  Future<BuiltBackend> Function(SavedConnection, String) factory({
    Map<String, Object> throwsFor = const {},
  }) => (connection, token) async {
    final backend = _FakeBackend(
      connection.backendId,
      connectThrows: throwsFor[connection.id],
    );
    built[connection.id] = backend;
    return BuiltBackend(backend: backend);
  };

  Future<ConnectionStore> storeWith(List<(String, String)> servers) async {
    final store = ConnectionStore();
    for (final (label, backendId) in servers) {
      await store.save(
        label: label,
        url: 'wss://$label.test',
        token: 'tok-$label',
        backendId: backendId,
      );
    }
    return store;
  }

  test('every saved server is connected, not just one', () async {
    // The whole point. One AgentBackend was the limitation.
    final store = await storeWith([
      ('nas', SavedConnection.openclaw),
      ('hermes-box', SavedConnection.hermes),
    ]);
    final pool = BackendPool(store: store, buildFor: factory());
    addTearDown(pool.dispose);

    final pooled = await pool.connectAll();
    expect(pooled, hasLength(2));
    expect(pool.usable, hasLength(2));
    expect(built.values.map((b) => b.connects), everyElement(1));
  });

  test('one unreachable server does not cost the others', () async {
    // A pool that failed as a unit would be no better than the single
    // backend it replaces — worse, since one dead server would hide a live
    // one's memory.
    final store = await storeWith([
      ('nas', SavedConnection.openclaw),
      ('down', SavedConnection.hermes),
    ]);
    final saved = await store.list();
    final broken = saved.firstWhere((c) => c.label == 'down');

    final pool = BackendPool(
      store: store,
      buildFor: factory(throwsFor: {broken.id: Exception('no route to host')}),
    );
    addTearDown(pool.dispose);

    await pool.connectAll();
    expect(pool.usable, hasLength(1));
    expect(pool.usable.single.connection.label, 'nas');
  });

  test('a failure is reported, never silently dropped', () async {
    // "This agent does not have that memory" and "this agent could not be
    // asked" are opposite claims. A pool that swallowed the second would make
    // the bridge lie about what it compared.
    final store = await storeWith([('down', SavedConnection.hermes)]);
    final saved = await store.list();

    final pool = BackendPool(
      store: store,
      buildFor: factory(
        throwsFor: {saved.single.id: Exception('no route to host')},
      ),
    );
    addTearDown(pool.dispose);

    await pool.connectAll();
    expect(pool.failures, hasLength(1));
    expect(pool.failures.values.single, contains('no route to host'));
  });

  test(
    'a server with no readable token fails with a reason, not a crash',
    () async {
      final store = await storeWith([('nas', SavedConnection.openclaw)]);
      final saved = await store.list();
      // Wipe the Keychain the way a macOS rebuild does.
      FlutterSecureStorage.setMockInitialValues(<String, String>{});

      final pool = BackendPool(store: store, buildFor: factory());
      addTearDown(pool.dispose);

      await pool.connectAll();
      expect(pool.usable, isEmpty);
      expect(pool.failures.values.single, contains('No saved token'));
      expect(
        built,
        isEmpty,
        reason: 'nothing to connect with, so nothing built',
      );
      expect(saved, hasLength(1));
    },
  );

  group('ownership', () {
    test('an adopted backend is used but never closed', () async {
      // The workspace's connection is live and belongs to the workspace.
      // Closing it here would take the conversation down with the panel.
      final store = await storeWith([('nas', SavedConnection.openclaw)]);
      final mine = _FakeBackend('openclaw');

      final pool = BackendPool(store: store, buildFor: factory());
      pool.adopt('c-mine', mine);
      await pool.dispose();

      expect(mine.disposes, 0);
      expect(
        mine.connects,
        0,
        reason: 'an adopted backend is already connected',
      );
    });

    test('what the pool opened, the pool closes', () async {
      final store = await storeWith([('nas', SavedConnection.openclaw)]);
      final pool = BackendPool(store: store, buildFor: factory());

      await pool.connectAll();
      expect(built.values.single.disposes, 0);
      await pool.dispose();
      expect(built.values.single.disposes, 1);
    });

    test('the already-held connection is not opened a second time', () async {
      // On OpenClaw a second socket to the same gateway is a second device
      // pairing, which needs a second human approval. This is the test that
      // keeps that from happening quietly.
      final store = await storeWith([
        ('nas', SavedConnection.openclaw),
        ('hermes-box', SavedConnection.hermes),
      ]);
      final saved = await store.list();
      final mine = saved.firstWhere((c) => c.label == 'nas');

      final pool = BackendPool(store: store, buildFor: factory());
      addTearDown(pool.dispose);

      pool.adopt(mine.id, _FakeBackend('openclaw'));
      await pool.connectAll(except: {mine.id});

      expect(built.keys, [
        saved.firstWhere((c) => c.label == 'hermes-box').id,
      ], reason: 'only the server we did not already hold was opened');
      expect(pool.usable, hasLength(2), reason: 'both are usable regardless');
    });

    test('connecting twice does not open a second socket', () async {
      final store = await storeWith([('nas', SavedConnection.openclaw)]);
      final pool = BackendPool(store: store, buildFor: factory());
      addTearDown(pool.dispose);

      await pool.connectAll();
      await pool.connectAll();
      expect(built.values.single.connects, 1);
    });
  });
}
