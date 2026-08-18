/// The ledger, which is what makes a two-agent view possible at all.
///
/// `Workspace` holds one `AgentBackend`, so both backends are never connected
/// at once and "what does Hermes know that OpenClaw does not" cannot be
/// answered from live reads. It is answered from snapshots taken when each was
/// connected — which is the whole reason this class exists rather than being a
/// cache someone added for speed.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/memory_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MemoryEntry _entry(
  String text, {
  required String backend,
  String? native,
  MemoryKind kind = MemoryKind.fact,
}) => MemoryEntry(
  id: '$backend:${native ?? text}',
  kind: kind,
  text: text,
  origin: MemoryOrigin(backendId: backend, nativeId: native ?? text),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('snapshots', () {
    test(
      'a recorded snapshot survives a new ledger over the same store',
      () async {
        // The whole point: the app is restarted, or the server is unreachable,
        // and its memory is still visible.
        await MemoryLedger().record('hermes', [
          _entry('Drinks coffee black', backend: 'hermes'),
        ]);

        final reloaded = await MemoryLedger().snapshots();
        expect(reloaded.keys, ['hermes']);
        expect(reloaded['hermes']!.entries.single.text, 'Drinks coffee black');
        expect(reloaded['hermes']!.entries.single.origin.backendId, 'hermes');
      },
    );

    test('recording replaces rather than merges', () async {
      // A memory the agent deleted must disappear from the ledger too. A
      // merge would keep it forever with no way to tell it had gone.
      final ledger = MemoryLedger();
      await ledger.record('hermes', [
        _entry('Old fact here', backend: 'hermes'),
        _entry('Kept fact here', backend: 'hermes'),
      ]);
      await ledger.record('hermes', [
        _entry('Kept fact here', backend: 'hermes'),
      ]);

      final entries = (await ledger.snapshots())['hermes']!.entries;
      expect(entries.map((e) => e.text), ['Kept fact here']);
    });

    test('two backends are kept side by side, not overwritten', () async {
      final ledger = MemoryLedger();
      await ledger.record('hermes', [_entry('H fact', backend: 'hermes')]);
      await ledger.record('openclaw', [_entry('O fact', backend: 'openclaw')]);

      expect(
        (await ledger.snapshots()).keys,
        containsAll(['hermes', 'openclaw']),
      );
    });

    test('forgetting one leaves the other alone', () async {
      final ledger = MemoryLedger();
      await ledger.record('hermes', [_entry('H fact', backend: 'hermes')]);
      await ledger.record('openclaw', [_entry('O fact', backend: 'openclaw')]);

      await ledger.forget('hermes');
      expect((await ledger.snapshots()).keys, ['openclaw']);
    });

    test('a corrupt store loses the cache, not the app', () async {
      SharedPreferences.setMockInitialValues({
        'memory.snapshots.v1': 'not json at all',
      });
      // The backends are still the source of truth and the next connection
      // refills it, so this must be survivable rather than fatal.
      await expectLater(MemoryLedger().snapshots(), completion(isEmpty));
    });

    test('every field of an entry round-trips', () async {
      final at = DateTime(2026, 8, 6, 12, 30);
      await MemoryLedger().record('openclaw', [
        MemoryEntry(
          id: 'openclaw:MEMORY.md#coffee',
          kind: MemoryKind.persona,
          title: 'USER.md',
          text: 'Builds a Flutter client.',
          tags: const {'work', '工作'},
          updatedAt: at,
          origin: const MemoryOrigin(
            backendId: 'openclaw',
            nativeId: 'USER.md',
          ),
        ),
      ]);

      final restored =
          (await MemoryLedger().snapshots())['openclaw']!.entries.single;
      expect(restored.id, 'openclaw:MEMORY.md#coffee');
      expect(restored.kind, MemoryKind.persona);
      expect(restored.title, 'USER.md');
      expect(restored.text, 'Builds a Flutter client.');
      expect(restored.tags, {'work', '工作'});
      expect(restored.updatedAt, at);
      expect(restored.origin.nativeId, 'USER.md');
    });

    test(
      'an unknown kind reads as a fact rather than losing the entry',
      () async {
        // Written by a newer build. Losing the category is a small cost; losing
        // the memory is not.
        SharedPreferences.setMockInitialValues({
          'memory.snapshots.v1':
              '[{"backend":"hermes","readAt":"2026-08-06T00:00:00.000",'
              '"entries":[{"id":"x","kind":"somethingNew","text":"a fact",'
              '"origin":{"backend":"hermes","native":"n"}}]}]',
        });

        final entries = (await MemoryLedger().snapshots())['hermes']!.entries;
        expect(entries.single.text, 'a fact');
        expect(entries.single.kind, MemoryKind.fact);
      },
    );
  });

  group('the unified view', () {
    test('shows a disconnected backend from its snapshot', () async {
      // The central claim. OpenClaw is connected; Hermes is not, and has not
      // been since the snapshot — and its memory is still on screen.
      final ledger = MemoryLedger();
      await ledger.record('hermes', [
        _entry('Only Hermes knows this', backend: 'hermes'),
      ]);

      final view = await ledger.view(
        liveEntries: {
          'openclaw': [_entry('Only OpenClaw knows this', backend: 'openclaw')],
        },
      );

      expect(view.backends, {'hermes', 'openclaw'});
      expect(view.clusters, hasLength(2));
    });

    test('the live read wins over that backend\'s own snapshot', () async {
      // Otherwise the connected server — the one we can actually see — would
      // be shown as it was yesterday.
      final ledger = MemoryLedger();
      await ledger.record('openclaw', [
        _entry('Stale wording here', backend: 'openclaw', native: 'n1'),
      ]);

      final view = await ledger.view(
        liveEntries: {
          'openclaw': [
            _entry('Fresh wording here', backend: 'openclaw', native: 'n1'),
          ],
        },
      );

      final texts = [
        for (final c in view.clusters)
          for (final e in c.entries) e.text,
      ];
      expect(texts, ['Fresh wording here']);
      expect(texts, isNot(contains('Stale wording here')));
    });

    test('divergent names exactly what one side is missing', () async {
      final ledger = MemoryLedger();
      await ledger.record('hermes', [
        _entry('Shared fact here', backend: 'hermes'),
        _entry('Hermes only fact', backend: 'hermes'),
      ]);

      final view = await ledger.view(
        liveEntries: {
          'openclaw': [_entry('shared fact here.', backend: 'openclaw')],
        },
      );

      expect(view.clusters, hasLength(2));
      expect(view.divergent, hasLength(1));
      expect(view.divergent.single.best.text, 'Hermes only fact');
      expect(view.divergent.single.missingFrom(view.backends), {'openclaw'});
    });

    test('a snapshot carries when it was taken', () async {
      // Three weeks old and one minute old are different claims, and a view
      // that hides the difference invites acting on stale memory.
      final ledger = MemoryLedger();
      await ledger.record('hermes', [_entry('A fact', backend: 'hermes')]);

      final view = await ledger.view(liveEntries: const {'openclaw': []});
      expect(
        view.sources['hermes'],
        isNotNull,
        reason: 'a cached backend reports when it was read',
      );
      expect(
        view.sources['openclaw'],
        isNull,
        reason: 'null means "right now" — this one is connected',
      );
    });

    test('with nothing connected the view is still the cache', () async {
      final ledger = MemoryLedger();
      await ledger.record('hermes', [_entry('A fact', backend: 'hermes')]);

      final view = await ledger.view();
      expect(view.clusters, hasLength(1));
      expect(view.liveBackendIds, isEmpty);
    });

    test('an empty ledger is empty, not one blank cluster', () async {
      final view = await MemoryLedger().view();
      expect(view.isEmpty, isTrue);
      expect(view.backends, isEmpty);
    });
  });

  group('rulings', () {
    test('survive a restart and change the clustering', () async {
      await MemoryLedger().record('hermes', [
        _entry('Drinks coffee black', backend: 'hermes', native: 'h1'),
      ]);
      const h = MemoryOrigin(backendId: 'hermes', nativeId: 'h1');
      const o = MemoryOrigin(backendId: 'openclaw', nativeId: 'o1');

      // Two wordings no fingerprint would join.
      final before = await MemoryLedger().view(
        liveEntries: {
          'openclaw': [
            _entry(
              'Takes coffee without milk',
              backend: 'openclaw',
              native: 'o1',
            ),
          ],
        },
      );
      expect(before.clusters, hasLength(2));

      await MemoryLedger().rule(const MemoryVerdict(a: h, b: o, same: true));

      final after = await MemoryLedger().view(
        liveEntries: {
          'openclaw': [
            _entry(
              'Takes coffee without milk',
              backend: 'openclaw',
              native: 'o1',
            ),
          ],
        },
      );
      expect(
        after.clusters,
        hasLength(1),
        reason: 'a ruling made once must not have to be made again',
      );
    });

    test('ruling again on the same pair replaces the earlier answer', () async {
      const a = MemoryOrigin(backendId: 'hermes', nativeId: 'h1');
      const b = MemoryOrigin(backendId: 'openclaw', nativeId: 'o1');
      final ledger = MemoryLedger();

      await ledger.rule(const MemoryVerdict(a: a, b: b, same: true));
      await ledger.rule(const MemoryVerdict(a: b, b: a, same: false));

      final stored = await ledger.verdicts();
      expect(
        stored,
        hasLength(1),
        reason: 'two answers for one pair would contradict each other',
      );
      expect(stored.single.same, isFalse);
    });

    test(
      'a corrupt verdict store loses the rulings, not the memories',
      () async {
        SharedPreferences.setMockInitialValues({
          'memory.verdicts.v1': '{{{',
          'memory.snapshots.v1':
              '[{"backend":"hermes","readAt":"2026-08-06T00:00:00.000",'
              '"entries":[{"id":"x","kind":"fact","text":"a real memory",'
              '"origin":{"backend":"hermes","native":"n"}}]}]',
        });

        final view = await MemoryLedger().view();
        expect(view.clusters, hasLength(1));
        expect(view.clusters.single.best.text, 'a real memory');
      },
    );
  });

  group('several live backends at once', () {
    test(
      'two live reads are compared directly, no snapshot involved',
      () async {
        // What holding more than one AgentBackend buys: the comparison is
        // between two servers as they are *now*, not one live and one recalled.
        final view = await MemoryLedger().view(
          liveEntries: {
            'hermes': [_entry('Drinks coffee black', backend: 'hermes')],
            'openclaw': [_entry('Prefers short answers', backend: 'openclaw')],
          },
        );

        expect(view.liveBackendIds, {'hermes', 'openclaw'});
        expect(
          view.sources.values,
          everyElement(isNull),
          reason: 'null means live; neither of these came from a snapshot',
        );
        expect(view.divergent, hasLength(2));
      },
    );

    test(
      'a live read replaces that backend\'s snapshot, others keep theirs',
      () async {
        final ledger = MemoryLedger();
        await ledger.record('hermes', [_entry('Stale H', backend: 'hermes')]);
        await ledger.record('openclaw', [
          _entry('Cached O', backend: 'openclaw'),
        ]);

        final view = await ledger.view(
          liveEntries: {
            'hermes': [_entry('Fresh H', backend: 'hermes')],
          },
        );

        final texts = [
          for (final c in view.clusters)
            for (final e in c.entries) e.text,
        ];
        expect(texts, containsAll(['Fresh H', 'Cached O']));
        expect(texts, isNot(contains('Stale H')));
        expect(view.sources['hermes'], isNull);
        expect(view.sources['openclaw'], isNotNull);
      },
    );

    test(
      'an unreachable server is named rather than quietly omitted',
      () async {
        // "Hermes does not have this" and "Hermes could not be asked" are
        // opposite claims about the same row.
        final view = await MemoryLedger().view(
          liveEntries: {
            'openclaw': [_entry('A fact', backend: 'openclaw')],
          },
          unreachable: const {'hermes': 'no route to host'},
        );

        expect(view.unreachable, hasLength(1));
        expect(view.unreachable['hermes'], 'no route to host');
      },
    );
  });
}
