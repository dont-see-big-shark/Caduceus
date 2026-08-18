/// Deciding that two agents remember the same thing.
///
/// The bridge's whole premise is one memory seen from two sides, and this is
/// the only place that decides which entries are two views of one fact. It is
/// pure — no store, no gateway — because the cost of getting it wrong is a
/// user's memories being silently merged or silently duplicated, and that is
/// found by feeding it awkward pairs rather than by mocking a connection.
///
/// See `MEMORY_BRIDGE.md` §11, which asked this question and deferred it.
library;

import 'package:meta/meta.dart';

import 'memory.dart';

/// A text fingerprint two entries share when they say the same thing.
///
/// Deliberately conservative. Normalisation that is too eager merges memories
/// that contradict each other, and there is no worse outcome available here:
/// a duplicate is visible and annoying, while a wrong merge silently discards
/// one of two facts the user believed were both recorded.
///
/// So this collapses only what is *never* meaning-bearing:
///
///  * case, because agents capitalise inconsistently;
///  * runs of whitespace, because markdown reflows;
///  * markdown emphasis and list bullets, because one backend stores prose and
///    the other stores list items;
///  * trailing punctuation, because a full stop is not a fact.
///
/// It does **not** stem, drop stop-words, or strip negation. `likes tea` and
/// `dislikes tea` are different memories and must stay that way, which is the
/// property [MemoryFingerprint] exists to guarantee and the first thing its
/// tests check.
@immutable
class MemoryFingerprint {
  const MemoryFingerprint._(this.value);

  /// The normalised text. Empty when there was nothing to normalise, which
  /// never matches anything — see [matches].
  final String value;

  factory MemoryFingerprint.of(String text) {
    var normalised = text.toLowerCase();
    // Markdown decoration, which differs by backend rather than by meaning.
    normalised = normalised
        .replaceAll(RegExp(r'^[\s>]*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'[*_`]'), '');
    // Whitespace, including the newlines that make one backend's paragraph
    // another's single line.
    normalised = normalised.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Trailing punctuation only. Interior punctuation can carry meaning —
    // "no, really" is not "no really" — so it stays.
    normalised = normalised.replaceAll(RegExp(r'[.,;:!?、。，；：！？]+$'), '');
    return MemoryFingerprint._(normalised);
  }

  /// Whether this is specific enough to identify anything.
  ///
  /// A blank entry, or one whose whole text was decoration, would otherwise
  /// match every other blank entry and collapse them into one cluster.
  bool get isUsable => value.length >= 3;

  bool matches(MemoryFingerprint other) =>
      isUsable && other.isUsable && value == other.value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryFingerprint && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MemoryFingerprint("$value")';
}

/// One fact, and every backend's copy of it.
///
/// The unit the bridge's UI is built from: a row that says *this is known*,
/// and *these agents know it*. "What does Hermes know that OpenClaw does not"
/// is then [missingFrom], not a separate query.
@immutable
class MemoryCluster {
  const MemoryCluster({required this.id, required this.entries});

  /// Stable across reads as long as the entries are. Derived from the
  /// fingerprint where there is one so that re-reading both backends produces
  /// the same clusters in the same order, which is what makes a diff screen
  /// stable enough to act on.
  final String id;

  /// Every backend's copy, in the order the backends were read.
  final List<MemoryEntry> entries;

  /// The entry to show. The longest text wins: when two agents record the
  /// same fact with different detail, the fuller one is the one worth
  /// reading, and the shorter is visible by expanding.
  MemoryEntry get best => entries.reduce(
    (a, b) => b.text.trim().length > a.text.trim().length ? b : a,
  );

  Set<String> get backends => {for (final e in entries) e.origin.backendId};

  /// Which of [connected] have no copy of this.
  ///
  /// Takes the connected set rather than assuming two backends: a user with
  /// one server connected must not be told every memory is "missing from"
  /// a server that is not there.
  Set<String> missingFrom(Set<String> connected) =>
      connected.difference(backends);

  bool get isShared => backends.length > 1;

  @override
  String toString() =>
      'MemoryCluster($id, ${entries.length} entries, ${backends.join("+")})';
}

/// A pair a person has ruled on, so the ruling survives the next read.
///
/// Both directions matter and they are not symmetric in effect. A `same`
/// verdict joins two entries the fingerprint could not see were one — the
/// usual case, since two agents rarely word a fact identically. A `different`
/// verdict keeps apart two that the fingerprint *did* match, which is the
/// safety valve for the cases this file's conservatism does not catch.
@immutable
class MemoryVerdict {
  const MemoryVerdict({
    required this.a,
    required this.b,
    required this.same,
  });

  final MemoryOrigin a;
  final MemoryOrigin b;
  final bool same;

  /// Order-independent, because "A is the same as B" is not a different fact
  /// from "B is the same as A" and storing both would let them disagree.
  String get key {
    final ends = [a.toString(), b.toString()]..sort();
    return ends.join('|');
  }

  static String keyFor(MemoryOrigin a, MemoryOrigin b) =>
      MemoryVerdict(a: a, b: b, same: true).key;

  Map<String, dynamic> toJson() => {
    'a': {'backend': a.backendId, 'native': a.nativeId},
    'b': {'backend': b.backendId, 'native': b.nativeId},
    'same': same,
  };

  factory MemoryVerdict.fromJson(Map<String, dynamic> json) {
    MemoryOrigin origin(Object? raw) {
      final map = raw is Map ? raw : const {};
      return MemoryOrigin(
        backendId: '${map['backend'] ?? ''}',
        nativeId: '${map['native'] ?? ''}',
      );
    }

    return MemoryVerdict(
      a: origin(json['a']),
      b: origin(json['b']),
      same: json['same'] == true,
    );
  }

  @override
  String toString() => 'MemoryVerdict($a ${same ? '==' : '!='} $b)';
}

/// Groups [entries] into one cluster per fact.
///
/// Two entries join when their fingerprints match *or* a person said they are
/// the same; they stay apart when a person said they are different, whatever
/// the fingerprints say. A person's ruling always wins — that is the entire
/// reason [MemoryVerdict] is persisted, and a heuristic that could override it
/// would make the ruling pointless.
///
/// Persona documents never auto-join. `SOUL.md` on one agent and a persona
/// document on another are whole files from different systems that happen to
/// describe the same person; merging them on text would produce a cluster
/// whose [MemoryCluster.best] is one file arbitrarily hiding the other. They
/// join only when a person says so.
List<MemoryCluster> clusterMemories(
  List<MemoryEntry> entries, {
  Iterable<MemoryVerdict> verdicts = const [],
}) {
  final ruling = {for (final v in verdicts) v.key: v.same};

  // Union-find over entry indices. Small enough that the naive form is
  // clearer than the clever one, and clarity is worth more here.
  final parent = List<int>.generate(entries.length, (i) => i);
  int find(int i) => parent[i] == i ? i : parent[i] = find(parent[i]);
  void union(int a, int b) {
    final (ra, rb) = (find(a), find(b));
    if (ra != rb) parent[rb] = ra;
  }

  final prints = [for (final e in entries) MemoryFingerprint.of(e.text)];

  for (var i = 0; i < entries.length; i++) {
    for (var j = i + 1; j < entries.length; j++) {
      final verdict = ruling[MemoryVerdict.keyFor(
        entries[i].origin,
        entries[j].origin,
      )];
      if (verdict == false) continue;
      if (verdict == true) {
        union(i, j);
        continue;
      }
      // No ruling: fall back to the fingerprint, except for persona
      // documents, which never join on text alone.
      if (entries[i].kind == MemoryKind.persona ||
          entries[j].kind == MemoryKind.persona) {
        continue;
      }
      if (prints[i].matches(prints[j])) union(i, j);
    }
  }

  final grouped = <int, List<MemoryEntry>>{};
  for (var i = 0; i < entries.length; i++) {
    grouped.putIfAbsent(find(i), () => []).add(entries[i]);
  }

  return [
    for (final root in grouped.keys.toList()..sort())
      MemoryCluster(
        // The fingerprint where one is usable, so the same two reads produce
        // the same ids; the origin otherwise, which is at least stable for
        // that one backend.
        id: prints[root].isUsable
            ? 'fp:${prints[root].value}'
            : 'origin:${entries[root].origin}',
        entries: grouped[root]!,
      ),
  ];
}
