/// Several agents open at once.
///
/// Owning the lifecycle is the whole job of `AgentTabs`, so that is what these
/// pin. A tab that is not on screen must **stay connected** — that is what
/// makes it a tab rather than a bookmark — and closing one must dispose
/// exactly its own workspace and backend, not the active one and not all of
/// them.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/agent_tabs.dart';
import 'package:caduceus/backend_factory.dart';
import 'package:caduceus/connection_store.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  AgentConnection get connectionState => AgentConnection.disconnected;

  @override
  Stream<AgentConnection> get connection => const Stream.empty();

  @override
  Stream<AgentSession> get sessionUpdates => const Stream.empty();

  @override
  bool supports(Capability capability) => false;

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

  /// The store and a *label-keyed* map of what it holds.
  ///
  /// Keyed rather than indexed because `ConnectionStore.list()` returns
  /// newest-first, so positional access silently reverses the servers and the
  /// test fails for a reason that has nothing to do with tabs.
  Future<(ConnectionStore, Map<String, SavedConnection>)> storeWith(
    List<(String, String)> servers,
  ) async {
    final store = ConnectionStore();
    for (final (label, backendId) in servers) {
      await store.save(
        label: label,
        url: 'wss://$label.test',
        token: 'tok-$label',
        backendId: backendId,
      );
    }
    return (store, {for (final c in await store.list()) c.label: c});
  }

  test('two agents are open at once, and both stay connected', () async {
    // The feature. Connecting to a second agent used to mean disconnecting
    // from the first, because the app pushed one screen and disposed its
    // workspace on the way back.
    final (store, saved) = await storeWith([
      ('nas', SavedConnection.openclaw),
      ('hermes-box', SavedConnection.hermes),
    ]);
    final tabs = AgentTabs(store: store, buildFor: factory());
    addTearDown(tabs.dispose);

    await tabs.open(saved['nas']!);
    await tabs.open(saved['hermes-box']!);

    expect(tabs.length, 2);
    expect(
      built.values.map((b) => b.disposes),
      everyElement(0),
      reason: 'a tab out of view is still a live connection',
    );
  });

  test('the newly opened tab comes to the front', () async {
    final (store, saved) = await storeWith([
      ('a', SavedConnection.hermes),
      ('b', SavedConnection.hermes),
    ]);
    final tabs = AgentTabs(store: store, buildFor: factory());
    addTearDown(tabs.dispose);

    await tabs.open(saved['a']!);
    await tabs.open(saved['b']!);
    expect(tabs.active!.connection.label, 'b');
  });

  test(
    'opening an already-open connection focuses it, never duplicates',
    () async {
      // A second socket to the same server is a second OpenClaw device pairing,
      // needing a second human approval.
      final (store, saved) = await storeWith([
        ('a', SavedConnection.openclaw),
        ('b', SavedConnection.hermes),
      ]);
      final tabs = AgentTabs(store: store, buildFor: factory());
      addTearDown(tabs.dispose);

      await tabs.open(saved['a']!);
      await tabs.open(saved['b']!);
      await tabs.open(saved['a']!);

      expect(tabs.length, 2);
      expect(tabs.active!.connection.label, 'a');
      expect(built[saved['a']!.id]!.connects, 1);
    },
  );

  group('closing', () {
    test(
      'disposes exactly that tab, and leaves the others connected',
      () async {
        final (store, saved) = await storeWith([
          ('a', SavedConnection.hermes),
          ('b', SavedConnection.hermes),
        ]);
        final tabs = AgentTabs(store: store, buildFor: factory());
        addTearDown(tabs.dispose);

        await tabs.open(saved['a']!);
        await tabs.open(saved['b']!);
        await tabs.close(saved['a']!.id);

        expect(tabs.length, 1);
        expect(built[saved['a']!.id]!.disposes, 1);
        expect(
          built[saved['b']!.id]!.disposes,
          0,
          reason: 'closing one tab must not take the others down',
        );
      },
    );

    test('lands on the neighbour, not back at the first', () async {
      // Every tabbed thing behaves this way, and being thrown to the start
      // after closing the third of five is disorienting.
      final (store, saved) = await storeWith([
        ('a', SavedConnection.hermes),
        ('b', SavedConnection.hermes),
        ('c', SavedConnection.hermes),
      ]);
      final tabs = AgentTabs(store: store, buildFor: factory());
      addTearDown(tabs.dispose);

      for (final label in ['a', 'b', 'c']) {
        await tabs.open(saved[label]!);
      }
      tabs.setActive(1);
      await tabs.close(saved['b']!.id);

      expect(tabs.length, 2);
      expect(tabs.active!.connection.label, 'c');
    });

    test(
      'closing the last one leaves no active tab and does not throw',
      () async {
        final (store, saved) = await storeWith([('a', SavedConnection.hermes)]);
        final tabs = AgentTabs(store: store, buildFor: factory());
        addTearDown(tabs.dispose);

        await tabs.open(saved['a']!);
        await tabs.close(saved['a']!.id);

        expect(tabs.isEmpty, isTrue);
        expect(tabs.active, isNull);
      },
    );

    test('closing an id that is not open is a no-op', () async {
      final tabs = AgentTabs(
        store: (await storeWith([])).$1,
        buildFor: factory(),
      );
      addTearDown(tabs.dispose);
      await expectLater(tabs.close('never-opened'), completes);
    });
  });

  group('a connection that fails', () {
    test('throws instead of opening a dead tab', () async {
      // A strip full of entries that cannot answer is worse than one visible
      // error, and the caller has somewhere to show one.
      final (store, saved) = await storeWith([
        ('down', SavedConnection.hermes),
      ]);
      final tabs = AgentTabs(
        store: store,
        buildFor: factory(
          throwsFor: {saved['down']!.id: Exception('no route to host')},
        ),
      );
      addTearDown(tabs.dispose);

      await expectLater(tabs.open(saved['down']!), throwsA(isA<Exception>()));
      expect(tabs.isEmpty, isTrue);
    });

    test('does not leak the half-open backend', () async {
      // A backend that failed to connect still holds a socket and a timer.
      // Leaking one per failed attempt is how an app ends up with forty.
      final (store, saved) = await storeWith([
        ('down', SavedConnection.hermes),
      ]);
      final tabs = AgentTabs(
        store: store,
        buildFor: factory(throwsFor: {saved['down']!.id: Exception('boom')}),
      );
      addTearDown(tabs.dispose);

      await expectLater(tabs.open(saved['down']!), throwsA(anything));
      expect(built[saved['down']!.id]!.disposes, 1);
    });

    test(
      'a server with no readable token says so rather than crashing',
      () async {
        final (store, saved) = await storeWith([('a', SavedConnection.hermes)]);
        FlutterSecureStorage.setMockInitialValues(<String, String>{});

        final tabs = AgentTabs(store: store, buildFor: factory());
        addTearDown(tabs.dispose);

        await expectLater(
          tabs.open(saved['a']!),
          throwsA(
            isA<AgentException>().having(
              (e) => e.detail,
              'detail',
              contains('No token is saved'),
            ),
          ),
        );
      },
    );
  });

  test('every open agent is available to the memory bridge', () async {
    // What the tabs buy the bridge: the connections are already open because
    // the user opened them, so there is no pool to build and no handshake or
    // pairing check to pay.
    final (store, saved) = await storeWith([
      ('nas', SavedConnection.openclaw),
      ('hermes-box', SavedConnection.hermes),
    ]);
    final tabs = AgentTabs(store: store, buildFor: factory());
    addTearDown(tabs.dispose);

    await tabs.open(saved['nas']!);
    await tabs.open(saved['hermes-box']!);

    expect(tabs.connectedBackends.keys, containsAll(['openclaw', 'hermes']));
  });

  test('disposing the tabs closes every backend', () async {
    final (store, saved) = await storeWith([
      ('a', SavedConnection.hermes),
      ('b', SavedConnection.hermes),
    ]);
    final tabs = AgentTabs(store: store, buildFor: factory());

    await tabs.open(saved['a']!);
    await tabs.open(saved['b']!);
    await tabs.dispose();

    expect(built.values.map((b) => b.disposes), everyElement(1));
  });

  test('listeners are told when the front tab changes', () async {
    final (store, saved) = await storeWith([
      ('a', SavedConnection.hermes),
      ('b', SavedConnection.hermes),
    ]);
    final tabs = AgentTabs(store: store, buildFor: factory());
    addTearDown(tabs.dispose);

    await tabs.open(saved['a']!);
    await tabs.open(saved['b']!);

    var notifications = 0;
    tabs.addListener(() => notifications++);

    tabs.setActive(0);
    expect(notifications, 1);
    // Selecting the tab already in front changes nothing, so it says nothing.
    tabs.setActive(0);
    expect(notifications, 1);
  });

  group('restoring last launch', () {
    test(
      'reopens the tabs that were open, and the one that was in front',
      () async {
        final (store, saved) = await storeWith([
          ('a', SavedConnection.hermes),
          ('b', SavedConnection.hermes),
          ('c', SavedConnection.hermes),
        ]);
        await store.setOpenTabs([
          saved['a']!.id,
          saved['b']!.id,
          saved['c']!.id,
        ], 1);

        final tabs = AgentTabs(store: store, buildFor: factory());
        addTearDown(tabs.dispose);

        expect(await tabs.restore(), isEmpty);
        expect(tabs.length, 3);
        expect(tabs.active!.connection.label, 'b');
      },
    );

    test(
      'one unreachable server does not cost the others, or the launch',
      () async {
        // Three of four agents being fine must not leave the user at a form.
        final (store, saved) = await storeWith([
          ('up', SavedConnection.hermes),
          ('down', SavedConnection.hermes),
        ]);
        await store.setOpenTabs([saved['up']!.id, saved['down']!.id], 0);

        final tabs = AgentTabs(
          store: store,
          buildFor: factory(
            throwsFor: {saved['down']!.id: Exception('no route to host')},
          ),
        );
        addTearDown(tabs.dispose);

        final failures = await tabs.restore();
        expect(tabs.length, 1);
        expect(tabs.active!.connection.label, 'up');
        expect(
          failures.keys,
          ['down'],
          reason:
              'a dropped tab must be reported, or it looks like the app '
              'forgot it',
        );
      },
    );

    test(
      'a server forgotten since is skipped silently, not reported',
      () async {
        // It is not a failure; it is gone, and saying so would be noise.
        final (store, saved) = await storeWith([('a', SavedConnection.hermes)]);
        await store.setOpenTabs([saved['a']!.id, 'deleted-long-ago'], 0);

        final tabs = AgentTabs(store: store, buildFor: factory());
        addTearDown(tabs.dispose);

        expect(await tabs.restore(), isEmpty);
        expect(tabs.length, 1);
      },
    );

    test(
      'with no tabs recorded it falls back to the last-used server',
      () async {
        // Someone upgrading from a build that had no tabs should land where
        // they left off, not at a form.
        final (store, saved) = await storeWith([
          ('a', SavedConnection.hermes),
          ('b', SavedConnection.hermes),
        ]);
        await store.setLastUsed(saved['b']!.id);

        final tabs = AgentTabs(store: store, buildFor: factory());
        addTearDown(tabs.dispose);

        await tabs.restore();
        expect(tabs.length, 1);
        expect(tabs.active!.connection.label, 'b');
      },
    );

    test('a first launch restores nothing and does not throw', () async {
      final (store, _) = await storeWith([]);
      final tabs = AgentTabs(store: store, buildFor: factory());
      addTearDown(tabs.dispose);

      expect(await tabs.restore(), isEmpty);
      expect(tabs.isEmpty, isTrue);
    });

    test(
      'a stale last-used id pointing at a deleted server is ignored',
      () async {
        final (store, _) = await storeWith([('a', SavedConnection.hermes)]);
        await store.setLastUsed('deleted-long-ago');

        final tabs = AgentTabs(store: store, buildFor: factory());
        addTearDown(tabs.dispose);

        expect(await tabs.restore(), isEmpty);
        expect(tabs.isEmpty, isTrue);
      },
    );
  });

  group('persisting', () {
    test(
      'what is open and which is in front survives to the next launch',
      () async {
        final (store, saved) = await storeWith([
          ('a', SavedConnection.hermes),
          ('b', SavedConnection.hermes),
        ]);
        final tabs = AgentTabs(store: store, buildFor: factory());
        addTearDown(tabs.dispose);

        await tabs.open(saved['a']!);
        await tabs.open(saved['b']!);
        tabs.setActive(0);
        await tabs.persist();

        final stored = await store.openTabs();
        expect(stored.ids, [saved['a']!.id, saved['b']!.id]);
        expect(stored.active, 0);
      },
    );

    test('a closed tab stops being restored', () async {
      final (store, saved) = await storeWith([
        ('a', SavedConnection.hermes),
        ('b', SavedConnection.hermes),
      ]);
      final tabs = AgentTabs(store: store, buildFor: factory());
      addTearDown(tabs.dispose);

      await tabs.open(saved['a']!);
      await tabs.open(saved['b']!);
      await tabs.close(saved['a']!.id);
      await tabs.persist();

      expect((await store.openTabs()).ids, [saved['b']!.id]);
    });

    test(
      'a persisted active index out of range is clamped, not crashed',
      () async {
        // Written by a launch with more tabs than this one can reopen.
        final (store, saved) = await storeWith([('a', SavedConnection.hermes)]);
        await store.setOpenTabs([saved['a']!.id], 7);

        final tabs = AgentTabs(store: store, buildFor: factory());
        addTearDown(tabs.dispose);

        await tabs.restore();
        expect(tabs.activeIndex, 0);
        expect(tabs.active!.connection.label, 'a');
      },
    );
  });

  group('adopting a connection that is already open', () {
    test('disposes the duplicate rather than leaking it', () async {
      // The + button pushed a connect screen that reconnected the last-used
      // server — the tab you already had — and handed it back. `adopt` saw a
      // duplicate and returned silently, so the whole second agent was
      // dropped on the floor: a live socket, its timers, and on OpenClaw a
      // second device pairing. Once per press.
      final (store, saved) = await storeWith([('a', SavedConnection.openclaw)]);
      final tabs = AgentTabs(store: store, buildFor: factory());
      addTearDown(tabs.dispose);

      await tabs.open(saved['a']!);
      final first = built[saved['a']!.id]!;

      // A second, independently built agent for the same saved server.
      final duplicate = _FakeBackend('openclaw');
      final adopted = await tabs.adopt(
        connection: saved['a']!,
        workspace: Workspace.forBackend(duplicate),
        backend: duplicate,
      );

      expect(adopted, isFalse);
      expect(tabs.length, 1);
      expect(
        duplicate.disposes,
        1,
        reason:
            'the duplicate must be closed here — a caller that has to '
            'remember is a caller that will forget, which is what happened',
      );
      expect(first.disposes, 0, reason: 'the tab you have stays up');
    });

    test('and focuses the tab that was already there', () async {
      final (store, saved) = await storeWith([
        ('a', SavedConnection.hermes),
        ('b', SavedConnection.hermes),
      ]);
      final tabs = AgentTabs(store: store, buildFor: factory());
      addTearDown(tabs.dispose);

      await tabs.open(saved['a']!);
      await tabs.open(saved['b']!);
      expect(tabs.active!.connection.label, 'b');

      final duplicate = _FakeBackend('hermes');
      await tabs.adopt(
        connection: saved['a']!,
        workspace: Workspace.forBackend(duplicate),
        backend: duplicate,
      );

      expect(tabs.active!.connection.label, 'a');
    });

    test('a genuinely new agent is adopted and reported as such', () async {
      final (store, saved) = await storeWith([('a', SavedConnection.hermes)]);
      final tabs = AgentTabs(store: store, buildFor: factory());
      addTearDown(tabs.dispose);

      final fresh = _FakeBackend('hermes');
      final adopted = await tabs.adopt(
        connection: saved['a']!,
        workspace: Workspace.forBackend(fresh),
        backend: fresh,
      );

      expect(adopted, isTrue);
      expect(tabs.length, 1);
      expect(fresh.disposes, 0);
    });
  });
}
