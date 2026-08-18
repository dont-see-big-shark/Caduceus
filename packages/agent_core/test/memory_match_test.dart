/// Deciding that two agents remember the same thing.
///
/// The asymmetry that shapes every test here: a **duplicate is visible and
/// annoying**, while a **wrong merge silently discards** one of two facts the
/// user believed were both recorded. So the matcher is deliberately timid, and
/// most of these tests are about what it must *refuse* to merge.
library;

import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

MemoryEntry _entry(
  String text, {
  String backend = 'hermes',
  String? native,
  MemoryKind kind = MemoryKind.fact,
  String title = '',
}) => MemoryEntry(
  id: '$backend:${native ?? text}',
  kind: kind,
  title: title,
  text: text,
  origin: MemoryOrigin(backendId: backend, nativeId: native ?? text),
);

void main() {
  group('fingerprint — what it collapses', () {
    void same(String a, String b, String why) {
      test(why, () {
        expect(
          MemoryFingerprint.of(a).matches(MemoryFingerprint.of(b)),
          isTrue,
          reason: why,
        );
      });
    }

    same('Drinks coffee black', 'drinks coffee black', 'case is not meaning');
    same(
      'Drinks   coffee\n  black',
      'Drinks coffee black',
      'whitespace reflows between markdown renderers',
    );
    same(
      '- Drinks coffee black',
      'Drinks coffee black',
      'one backend stores list items and the other stores prose',
    );
    same(
      '**Drinks** coffee `black`',
      'Drinks coffee black',
      'emphasis is decoration',
    );
    same(
      'Drinks coffee black.',
      'Drinks coffee black',
      'a full stop is not a fact',
    );
    same(
      '## Coffee\nDrinks it black',
      'Coffee\nDrinks it black',
      'a heading marker is structure, not content',
    );
  });

  group('fingerprint — what it must never collapse', () {
    void different(String a, String b, String why) {
      test(why, () {
        expect(
          MemoryFingerprint.of(a).matches(MemoryFingerprint.of(b)),
          isFalse,
          reason: why,
        );
      });
    }

    different(
      'Likes tea',
      'Dislikes tea',
      'negation is the whole meaning — merging these loses a fact',
    );
    different(
      'Deploys on Friday',
      'Never deploys on Friday',
      'a negated policy is the opposite policy',
    );
    different(
      'Prefers Dart',
      'Prefers Rust',
      'different objects are different facts',
    );
    different(
      'no, really',
      'no really',
      'interior punctuation can carry meaning and is left alone',
    );
    different(
      'Timezone is Asia/Shanghai',
      'Timezone is Europe/London',
      'the detail is the point',
    );

    test('two blank entries do not become one', () {
      // Anything that normalises to nothing would otherwise match everything
      // else that normalises to nothing.
      expect(MemoryFingerprint.of('').isUsable, isFalse);
      expect(MemoryFingerprint.of('   \n**  **  ').isUsable, isFalse);
      expect(
        MemoryFingerprint.of('  ').matches(MemoryFingerprint.of('')),
        isFalse,
      );
    });

    test('a one-word entry is too short to identify anything', () {
      expect(MemoryFingerprint.of('no').isUsable, isFalse);
    });
  });

  group('clustering', () {
    test('the same fact from two agents becomes one cluster', () {
      final clusters = clusterMemories([
        _entry('Drinks coffee black', backend: 'hermes'),
        _entry('- drinks coffee black.', backend: 'openclaw'),
      ]);

      expect(clusters, hasLength(1));
      expect(clusters.single.backends, {'hermes', 'openclaw'});
      expect(clusters.single.isShared, isTrue);
    });

    test('different facts stay separate', () {
      final clusters = clusterMemories([
        _entry('Likes tea', backend: 'hermes'),
        _entry('Dislikes tea', backend: 'openclaw'),
      ]);
      expect(clusters, hasLength(2));
    });

    test('a cluster names the agents that do not have it', () {
      final clusters = clusterMemories([
        _entry('Only Hermes knows this', backend: 'hermes'),
      ]);

      expect(
        clusters.single.missingFrom({'hermes', 'openclaw'}),
        {'openclaw'},
        reason: '"what does one know that the other does not" is this, not a '
            'separate query',
      );
    });

    test('nothing is missing from a backend that is not connected', () {
      // A user with one server must not be told every memory is absent from
      // a server they have not set up.
      final clusters = clusterMemories([_entry('A fact', backend: 'hermes')]);
      expect(clusters.single.missingFrom({'hermes'}), isEmpty);
    });

    test('the fuller wording is the one shown', () {
      final clusters = clusterMemories([
        _entry('Drinks coffee black', backend: 'hermes'),
        _entry('drinks coffee black', backend: 'openclaw'),
      ]);
      // Same fingerprint, different length: the longer text is the one worth
      // reading, and the other stays reachable in `entries`.
      expect(clusters.single.entries, hasLength(2));
      expect(clusters.single.best.text.length, greaterThanOrEqualTo(19));
    });

    test('cluster ids are stable across two identical reads', () {
      // A diff screen that renumbers its rows on every refresh cannot be
      // acted on.
      List<String> ids() => clusterMemories([
        _entry('Drinks coffee black', backend: 'hermes'),
        _entry('Prefers short answers', backend: 'openclaw'),
      ]).map((c) => c.id).toList();

      expect(ids(), ids());
    });

    test('three agents with one fact make one cluster, not three', () {
      final clusters = clusterMemories([
        _entry('Shared fact here', backend: 'hermes'),
        _entry('shared fact here', backend: 'openclaw'),
        _entry('Shared fact here.', backend: 'pi'),
      ]);
      expect(clusters, hasLength(1));
      expect(clusters.single.backends, hasLength(3));
    });

    test('an empty read produces no clusters, not one empty one', () {
      expect(clusterMemories(const []), isEmpty);
    });
  });

  group('persona documents', () {
    test('two whole documents never join on text alone', () {
      // Even identical text: these are whole files from different systems,
      // and merging them would hide one behind the other with no way to see
      // that it happened.
      const text = '# SOUL.md\n\nDry, direct, allergic to filler.';
      final clusters = clusterMemories([
        _entry(text, backend: 'hermes', kind: MemoryKind.persona),
        _entry(text, backend: 'openclaw', kind: MemoryKind.persona),
      ]);

      expect(
        clusters,
        hasLength(2),
        reason: 'a persona document joins only when a person says so',
      );
    });

    test('but a person can still join them', () {
      const text = '# SOUL.md\n\nDry, direct.';
      final a = _entry(text, backend: 'hermes', kind: MemoryKind.persona);
      final b = _entry(text, backend: 'openclaw', kind: MemoryKind.persona);

      final clusters = clusterMemories(
        [a, b],
        verdicts: [MemoryVerdict(a: a.origin, b: b.origin, same: true)],
      );
      expect(clusters, hasLength(1));
    });
  });

  group("a person's ruling", () {
    test('joins two entries the fingerprint could not see were one', () {
      // The usual case. Two agents rarely word a fact identically, so this is
      // how most cross-backend links will actually be made.
      final a = _entry('Drinks coffee black', backend: 'hermes');
      final b = _entry('Takes coffee without milk', backend: 'openclaw');

      expect(clusterMemories([a, b]), hasLength(2));
      expect(
        clusterMemories(
          [a, b],
          verdicts: [MemoryVerdict(a: a.origin, b: b.origin, same: true)],
        ),
        hasLength(1),
      );
    });

    test('keeps apart two the fingerprint did match', () {
      // The safety valve for whatever this file's conservatism fails to
      // catch. Without it, a wrong merge would be unfixable from the UI.
      final a = _entry('Runs the deploy', backend: 'hermes');
      final b = _entry('runs the deploy', backend: 'openclaw');

      expect(clusterMemories([a, b]), hasLength(1));
      expect(
        clusterMemories(
          [a, b],
          verdicts: [MemoryVerdict(a: a.origin, b: b.origin, same: false)],
        ),
        hasLength(2),
        reason: 'a ruling always beats the heuristic, or it is pointless',
      );
    });

    test('is order-independent', () {
      final a = _entry('One wording', backend: 'hermes');
      final b = _entry('Another wording entirely', backend: 'openclaw');

      final forward = MemoryVerdict(a: a.origin, b: b.origin, same: true);
      final backward = MemoryVerdict(a: b.origin, b: a.origin, same: true);

      expect(
        forward.key,
        backward.key,
        reason: 'two keys for one ruling would let them disagree',
      );
      expect(clusterMemories([a, b], verdicts: [backward]), hasLength(1));
    });

    test('survives a round trip through JSON', () {
      // It has to outlive the read it was made during, or the user re-rules
      // on every refresh.
      final original = MemoryVerdict(
        a: const MemoryOrigin(backendId: 'hermes', nativeId: 'n-1'),
        b: const MemoryOrigin(backendId: 'openclaw', nativeId: 'MEMORY.md#x'),
        same: false,
      );
      final restored = MemoryVerdict.fromJson(original.toJson());

      expect(restored.key, original.key);
      expect(restored.same, isFalse);
      expect(restored.a, original.a);
      expect(restored.b, original.b);
    });

    test('a ruling about one pair does not leak to another', () {
      final a = _entry('Fact one here', backend: 'hermes');
      final b = _entry('Fact two here', backend: 'openclaw');
      final c = _entry('Fact three here', backend: 'openclaw');

      final clusters = clusterMemories(
        [a, b, c],
        verdicts: [MemoryVerdict(a: a.origin, b: b.origin, same: true)],
      );
      expect(clusters, hasLength(2));
      expect(
        clusters.firstWhere((cl) => cl.entries.length == 2).backends,
        {'hermes', 'openclaw'},
      );
    });

    test('joining is transitive, so a chain becomes one cluster', () {
      // A said to be B, and B said to be C, means all three are one fact —
      // otherwise the user has to rule on every pair in a group.
      final a = _entry('Wording alpha', backend: 'hermes');
      final b = _entry('Wording beta', backend: 'openclaw');
      final c = _entry('Wording gamma', backend: 'pi');

      final clusters = clusterMemories(
        [a, b, c],
        verdicts: [
          MemoryVerdict(a: a.origin, b: b.origin, same: true),
          MemoryVerdict(a: b.origin, b: c.origin, same: true),
        ],
      );
      expect(clusters, hasLength(1));
      expect(clusters.single.backends, hasLength(3));
    });
  });
}
