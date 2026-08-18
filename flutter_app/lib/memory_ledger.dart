/// The app's own copy of what every agent remembers.
///
/// Phase 2 of `MEMORY_BRIDGE.md`, and the piece that makes the bridge possible
/// at all. **The app connects to one backend at a time** — `Workspace` holds a
/// single `AgentBackend` — so "what does Hermes know that OpenClaw does not"
/// cannot be answered by reading both live. It is answered by reading each one
/// when it *is* connected and keeping the snapshot.
///
/// That is what "the app is the ledger" means concretely. Without it the
/// unified view would need two simultaneous connections, which is a much
/// larger change and would still leave the question unanswerable while either
/// server was down.
library;

import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One backend's memory, as it was the last time the app could see it.
class MemorySnapshot {
  const MemorySnapshot({
    required this.backendId,
    required this.entries,
    required this.readAt,
  });

  final String backendId;
  final List<MemoryEntry> entries;

  /// When the app last read it. Shown, because a snapshot from three weeks ago
  /// is a different claim from one taken a minute ago, and a view that hides
  /// the difference invites acting on stale memory.
  final DateTime readAt;

  Map<String, dynamic> toJson() => {
    'backend': backendId,
    'readAt': readAt.toIso8601String(),
    'entries': [for (final e in entries) e.toJson()],
  };

  factory MemorySnapshot.fromJson(Map<String, dynamic> json) => MemorySnapshot(
    backendId: '${json['backend'] ?? ''}',
    readAt: DateTime.tryParse('${json['readAt'] ?? ''}') ?? DateTime(1970),
    entries: [
      for (final raw in (json['entries'] as List?) ?? const [])
        if (raw is Map<String, dynamic>) MemoryEntry.fromJson(raw),
    ],
  );

  @override
  String toString() =>
      'MemorySnapshot($backendId, ${entries.length} entries, $readAt)';
}

/// Snapshots and rulings, on this device.
///
/// **Stored in the clear.** These are notes about a person, not credentials,
/// and they live in SharedPreferences alongside the server list — which on
/// macOS is a plain plist in the app's container. The Keychain is the wrong
/// home for kilobytes of markdown, and pretending otherwise by encrypting with
/// a key stored beside the data would be theatre. Said plainly here so the
/// tradeoff is visible rather than assumed.
class MemoryLedger {
  MemoryLedger({this.prefs});

  static const _snapshotsKey = 'memory.snapshots.v1';
  static const _verdictsKey = 'memory.verdicts.v1';
  static const _overwritesKey = 'memory.overwrites.v1';

  SharedPreferences? prefs;

  Future<SharedPreferences> get _p async =>
      prefs ??= await SharedPreferences.getInstance();

  /// Every backend's last-seen memory, keyed by backend id.
  Future<Map<String, MemorySnapshot>> snapshots() async {
    final raw = (await _p).getString(_snapshotsKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      final result = <String, MemorySnapshot>{};
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        final snapshot = MemorySnapshot.fromJson(entry);
        if (snapshot.backendId.isNotEmpty) {
          result[snapshot.backendId] = snapshot;
        }
      }
      return result;
    } on FormatException {
      // A corrupt store loses the cache, not the app. The backends are still
      // the source of truth and the next connection refills it.
      return const {};
    }
  }

  /// Records what [backendId] currently remembers.
  ///
  /// Replaces that backend's snapshot wholesale rather than merging into it:
  /// a memory the agent deleted must disappear from the ledger too, and a
  /// merge would keep it forever with no way to tell it had gone.
  Future<void> record(String backendId, List<MemoryEntry> entries) async {
    final all = Map<String, MemorySnapshot>.from(await snapshots());
    all[backendId] = MemorySnapshot(
      backendId: backendId,
      entries: entries,
      readAt: DateTime.now(),
    );
    await (await _p).setString(
      _snapshotsKey,
      jsonEncode([for (final s in all.values) s.toJson()]),
    );
  }

  /// Forgets one backend's snapshot — for when a server is removed.
  Future<void> forget(String backendId) async {
    final all = Map<String, MemorySnapshot>.from(await snapshots());
    if (all.remove(backendId) == null) return;
    await (await _p).setString(
      _snapshotsKey,
      jsonEncode([for (final s in all.values) s.toJson()]),
    );
  }

  Future<List<MemoryVerdict>> verdicts() async {
    final raw = (await _p).getString(_verdictsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map<String, dynamic>) MemoryVerdict.fromJson(entry),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Records that two entries are, or are not, the same fact.
  ///
  /// Keyed by the unordered pair, so ruling again on the same two replaces the
  /// earlier answer rather than stacking a contradiction behind it.
  Future<void> rule(MemoryVerdict verdict) async {
    final existing = await verdicts();
    final kept = [
      for (final v in existing)
        if (v.key != verdict.key) v,
    ];
    await (await _p).setString(
      _verdictsKey,
      jsonEncode([...kept.map((v) => v.toJson()), verdict.toJson()]),
    );
  }

  /// What a persona document held before this app replaced it.
  ///
  /// Phase 5 writes whole files — `SOUL.md` is prose, not a list, so there is
  /// no block to splice and a push genuinely overwrites what was there. That
  /// makes it the one destructive operation in the bridge, so the thing it
  /// destroys is kept: a backup here turns an irreversible act into a
  /// reversible one, which is the difference between a feature someone will
  /// try and one they will not.
  ///
  /// Keyed by backend and file. Only the most recent is kept — this is an
  /// undo, not a history, and a person who has pushed twice wants the version
  /// they had before they started, which the first backup still is only until
  /// they accept the first push.
  Future<void> recordOverwrite(
    String backendId,
    String name,
    String previous,
  ) async {
    final all = Map<String, String>.from(await overwrites());
    all['$backendId/$name'] = previous;
    await (await _p).setString(_overwritesKey, jsonEncode(all));
  }

  Future<Map<String, String>> overwrites() async {
    final raw = (await _p).getString(_overwritesKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries) '${entry.key}': '${entry.value}',
      };
    } on FormatException {
      return const {};
    }
  }

  /// What [name] held on [backendId] before the app last wrote it, if
  /// anything. Null when the app has never overwritten it.
  Future<String?> overwriteFor(String backendId, String name) async =>
      (await overwrites())['$backendId/$name'];

  Future<void> clearOverwrite(String backendId, String name) async {
    final all = Map<String, String>.from(await overwrites());
    if (all.remove('$backendId/$name') == null) return;
    await (await _p).setString(_overwritesKey, jsonEncode(all));
  }

  // -- shared knowledge base --------------------------------------------------

  static const _sharedFactsKey = 'memory.sharedFacts.v1';
  static const _sharedAnchorsKey = 'memory.sharedAnchors.v1';

  /// Every shared fact the person curated, in insertion order.
  ///
  /// This store is the physical copy — the canonical one Caduceus holds and
  /// the thing a future cloud sync would replicate. Kept flat and versioned
  /// so that migration is a plain read.
  Future<List<SharedFact>> sharedFacts() async {
    final raw = (await _p).getString(_sharedFactsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map<String, dynamic>) SharedFact.fromJson(entry),
      ];
    } on FormatException {
      // A corrupt store loses the base, never the app.
      return const [];
    }
  }

  Future<void> _writeSharedFacts(List<SharedFact> facts) async {
    await (await _p).setString(
      _sharedFactsKey,
      jsonEncode([for (final f in facts) f.toJson()]),
    );
  }

  /// Adds or replaces [fact] (matched by id).
  Future<void> saveSharedFact(SharedFact fact) async {
    final facts = List<SharedFact>.from(await sharedFacts());
    facts.removeWhere((f) => f.id == fact.id);
    facts.add(fact);
    await _writeSharedFacts(facts);
  }

  /// Removes [id] from the base.
  Future<void> removeSharedFact(String id) async {
    final facts = List<SharedFact>.from(await sharedFacts());
    facts.removeWhere((f) => f.id == id);
    await _writeSharedFacts(facts);
    // The anchors are bookkeeping for a fact that no longer exists.
    final anchors = Map<String, SyncAnchor>.from(await sharedAnchors());
    anchors.removeWhere((key, _) => key.startsWith('$id\u0000'));
    await _writeSharedAnchors(anchors);
  }

  /// Every sync anchor, keyed `factId\u0000backendId`.
  Future<Map<String, SyncAnchor>> sharedAnchors() async {
    final raw = (await _p).getString(_sharedAnchorsKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map<String, dynamic>)
            '${entry.key}': SyncAnchor.fromJson(
              entry.value as Map<String, dynamic>,
            ),
      };
    } on FormatException {
      return const {};
    }
  }

  Future<void> _writeSharedAnchors(Map<String, SyncAnchor> anchors) async {
    await (await _p).setString(
      _sharedAnchorsKey,
      jsonEncode({for (final e in anchors.entries) e.key: e.value.toJson()}),
    );
  }

  static String _anchorKey(String factId, String backendId) =>
      '$factId\u0000$backendId';

  /// Records where [factId] landed on [backendId].
  Future<void> recordAnchor(SyncAnchor anchor) async {
    final anchors = Map<String, SyncAnchor>.from(await sharedAnchors());
    anchors[_anchorKey(anchor.factId, anchor.backendId)] = anchor;
    await _writeSharedAnchors(anchors);
  }

  /// Forgets where [factId] landed on [backendId] — for when a copy is
  /// deliberately removed or a server is dropped.
  Future<void> clearAnchor(String factId, String backendId) async {
    final anchors = Map<String, SyncAnchor>.from(await sharedAnchors());
    if (anchors.remove(_anchorKey(factId, backendId)) == null) return;
    await _writeSharedAnchors(anchors);
  }

  /// Every anchor for [factId], keyed by backend id.
  Future<Map<String, SyncAnchor>> anchorsFor(String factId) async {
    final all = await sharedAnchors();
    return {
      for (final entry in all.entries)
        if (entry.key.startsWith('$factId\u0000'))
          entry.key.substring(factId.length + 1): entry.value,
    };
  }

  /// Everything known, as one fact per cluster.
  ///
  /// [liveEntries] is what each *currently reachable* backend just said,
  /// keyed by backend id. Everything else comes from the cache, which is the
  /// point: a memory stays visible whether or not the server holding it can
  /// be reached right now.
  ///
  /// [unreachable] names the servers that were tried and could not answer, so
  /// the screen can say so. A bridge that silently omits a server lies about
  /// what it compared — "Hermes does not have this" and "Hermes could not be
  /// asked" are opposite claims and must not render the same.
  Future<MemoryView> view({
    Map<String, List<MemoryEntry>> liveEntries = const {},
    Map<String, String> unreachable = const {},
  }) async {
    final cached = await snapshots();
    final entries = <MemoryEntry>[];
    final sources = <String, DateTime?>{};

    for (final live in liveEntries.entries) {
      entries.addAll(live.value);
      sources[live.key] = null;
    }
    for (final snapshot in cached.values) {
      if (liveEntries.containsKey(snapshot.backendId)) continue;
      entries.addAll(snapshot.entries);
      sources[snapshot.backendId] = snapshot.readAt;
    }

    return MemoryView(
      clusters: clusterMemories(entries, verdicts: await verdicts()),
      sources: sources,
      liveBackendIds: liveEntries.keys.toSet(),
      unreachable: unreachable,
    );
  }
}

/// What the memory screen shows, and where each part of it came from.
class MemoryView {
  const MemoryView({
    required this.clusters,
    required this.sources,
    this.liveBackendIds = const {},
    this.unreachable = const {},
  });

  final List<MemoryCluster> clusters;

  /// Every backend the ledger knows about, and when it was read. A null value
  /// means *right now* — that backend is the connected one.
  final Map<String, DateTime?> sources;

  /// The backends whose entries in this view came from a live read rather
  /// than a snapshot.
  final Set<String> liveBackendIds;

  /// Servers that were tried and could not answer, and why.
  ///
  /// Shown, never swallowed: "this agent does not have that memory" and "this
  /// agent could not be asked" are opposite claims about the same row.
  final Map<String, String> unreachable;

  Set<String> get backends => sources.keys.toSet();

  bool get isEmpty => clusters.isEmpty;

  /// Clusters missing from at least one backend the ledger knows about.
  ///
  /// The answer to "what does one agent know that the other does not", which
  /// is the question the whole bridge exists to make askable.
  List<MemoryCluster> get divergent => [
    for (final cluster in clusters)
      if (cluster.missingFrom(backends).isNotEmpty) cluster,
  ];

  @override
  String toString() =>
      'MemoryView(${clusters.length} clusters over ${backends.join("+")})';
}
