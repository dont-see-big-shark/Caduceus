/// The shared knowledge base — facts the person wants every agent to know.
///
/// See `SHARED_MEMORY.md`. One canonical store on the device (the future
/// cloud-sync source) plus verified local copies in each agent's own memory;
/// this file is the pure core — the fact, the per-agent state, the sync
/// anchor, and the detector that says whether a copy is current, missing,
/// drifted, or unverifiable. No store, no gateway: everything here is
/// derived from cluster data the bridge already reads.
library;

import 'package:meta/meta.dart';

import 'memory.dart';
import 'memory_match.dart';

/// One fact the person wants every agent to know.
///
/// [kind] is never [MemoryKind.persona] — who an agent is stays per-agent
/// (`SHARED_MEMORY.md` §2). [text] is the canonical wording; the per-agent
/// copies are measured against it by fingerprint.
@immutable
class SharedFact {
  const SharedFact({
    required this.id,
    required this.kind,
    required this.text,
    this.title = '',
    required this.updatedAt,
  }) : assert(
    kind != MemoryKind.persona,
    'Who an agent is stays per-agent; the shared base holds facts.',
  );

  /// Stable across edits and round trips.
  final String id;

  final MemoryKind kind;

  /// The canonical wording every agent's copy is measured against.
  final String text;

  /// A short heading when the text needs one.
  final String title;

  final DateTime updatedAt;

  /// What a row shows: a real title, else the first line of the text.
  String get label {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final firstLine = text.trim().split('\n').first.trim();
    return firstLine.isEmpty ? id : firstLine;
  }

  SharedFact copyWith({
    MemoryKind? kind,
    String? text,
    String? title,
    DateTime? updatedAt,
  }) => SharedFact(
    id: id,
    kind: kind ?? this.kind,
    text: text ?? this.text,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'text': text,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SharedFact.fromJson(Map<String, dynamic> json) => SharedFact(
    id: '${json['id'] ?? ''}',
    kind: MemoryKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => MemoryKind.fact,
    ),
    text: '${json['text'] ?? ''}',
    title: '${json['title'] ?? ''}',
    updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  String toString() => 'SharedFact($id, ${kind.name}, "$label")';
}

/// What one agent's copy of a shared fact looks like right now.
enum AgentFactStatus {
  /// The anchored entry matches the shared fact's fingerprint.
  synced,

  /// The agent has nothing matching. Syncable where the backend can receive
  /// an add — OpenClaw always, Hermes only through its agent (§2).
  missing,

  /// An anchored entry exists but its content moved away from the shared
  /// fact — either the agent changed it or the fact was edited since sync.
  drifted,

  /// The agent was asked and could not answer; never reported as "missing",
  /// which is an opposite claim.
  unverifiable,
}

/// One fact × one agent, as the detector sees it.
@immutable
class AgentFactState {
  const AgentFactState({
    required this.backendId,
    required this.status,
    this.nativeId,
    this.localText,
    this.detail = '',
  });

  /// Matches [AgentBackend.id].
  final String backendId;

  final AgentFactStatus status;

  /// The agent's address for its copy, when one exists — a Hermes learning
  /// node id (`memory:memory:N`) or an OpenClaw `MEMORY.md#<slug>`.
  final String? nativeId;

  /// The drifted local wording, for the side-by-side in the panel.
  final String? localText;

  /// Why, when [status] is [AgentFactStatus.unverifiable].
  final String detail;

  @override
  String toString() => 'AgentFactState($backendId, ${status.name})';
}

/// Where the sync left one fact on one agent — the drift detector's memory.
///
/// [nativeId] is the agent's own address for the copy and [fingerprint] is
/// what was actually written there (for Hermes, whatever the agent landed,
/// read back after the prompt — not necessarily the exact requested text).
@immutable
class SyncAnchor {
  const SyncAnchor({
    required this.factId,
    required this.backendId,
    required this.nativeId,
    required this.fingerprint,
    required this.syncedAt,
  });

  final String factId;
  final String backendId;
  final String nativeId;
  final String fingerprint;
  final DateTime syncedAt;

  Map<String, dynamic> toJson() => {
    'fact': factId,
    'backend': backendId,
    'native': nativeId,
    'fingerprint': fingerprint,
    'syncedAt': syncedAt.toIso8601String(),
  };

  factory SyncAnchor.fromJson(Map<String, dynamic> json) => SyncAnchor(
    factId: '${json['fact'] ?? ''}',
    backendId: '${json['backend'] ?? ''}',
    nativeId: '${json['native'] ?? ''}',
    fingerprint: '${json['fingerprint'] ?? ''}',
    syncedAt: DateTime.tryParse('${json['syncedAt'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  String toString() => 'SyncAnchor($factId × $backendId @ $nativeId)';
}

/// The state of every agent's copy of one shared fact, keyed by backend id.
class FactStates {
  const FactStates({required this.byBackend});

  final Map<String, AgentFactState> byBackend;

  bool get anyNeedsAttention => byBackend.values.any(
    (s) => s.status == AgentFactStatus.drifted || s.status == AgentFactStatus.missing,
  );

  @override
  String toString() => 'FactStates(${byBackend.length} agents)';
}

/// Detects one shared fact's state on every backend the caller knows about.
///
/// Pure — fed the clusters, the known-backend set and the unreachable map the
/// memory bridge already produces, plus this fact's sync anchors by backend.
/// The rule, per agent, in order:
///
///  1. Unreachable → [AgentFactStatus.unverifiable] (never "missing").
///  2. An anchor names the exact entry that is this fact's copy. When that
///     entry still exists, its fingerprint vs the fact decides synced vs
///     drifted. When it is gone, the agent's entries are searched by the
///     fact's fingerprint.
///  3. No anchor: search by the fact's fingerprint.
///  4. Nothing found → [AgentFactStatus.missing].
///
/// The anchor is what makes "drifted" trustworthy — it says *this exact
/// entry was the shared fact and now says something else* — and the search
/// by fingerprint is what makes "synced" true for a copy that arrived
/// without an anchor (a fact already in the agent's memory before the base
/// existed).
FactStates detectFactStates({
  required SharedFact fact,
  required List<MemoryCluster> clusters,
  required Set<String> knownBackends,
  required Map<String, String> unreachable,
  required Map<String, SyncAnchor> anchors,
}) {
  final factFingerprint = MemoryFingerprint.of(fact.text);

  AgentFactState stateFor(String backendId) {
    final reason = unreachable[backendId];
    if (reason != null) {
      return AgentFactState(
        backendId: backendId,
        status: AgentFactStatus.unverifiable,
        detail: reason,
      );
    }

    // Every entry this agent holds, flattened from the clusters.
    final entries = [
      for (final cluster in clusters)
        for (final entry in cluster.entries)
          if (entry.origin.backendId == backendId) entry,
    ];

    MemoryEntry? anchored;
    final anchor = anchors[backendId];
    if (anchor != null) {
      for (final entry in entries) {
        if (entry.origin.nativeId == anchor.nativeId) {
          anchored = entry;
          break;
        }
      }
    }

    MemoryEntry? candidate = anchored;
    if (candidate == null) {
      // No anchor, or the anchored entry vanished: search by fingerprint so a
      // copy that exists without an anchor is still "synced", never guessed.
      final target = MemoryFingerprint.of(fact.text);
      for (final entry in entries) {
        if (target.matches(MemoryFingerprint.of(entry.text))) {
          candidate = entry;
          break;
        }
      }
    }

    if (candidate == null) {
      return AgentFactState(
        backendId: backendId,
        status: AgentFactStatus.missing,
      );
    }

    final current = MemoryFingerprint.of(candidate.text);
    if (current.isUsable && current.value == factFingerprint.value) {
      return AgentFactState(
        backendId: backendId,
        status: AgentFactStatus.synced,
        nativeId: candidate.origin.nativeId,
      );
    }
    return AgentFactState(
      backendId: backendId,
      status: AgentFactStatus.drifted,
      nativeId: candidate.origin.nativeId,
      localText: candidate.text,
    );
  }

  return FactStates(byBackend: {
    for (final backendId in knownBackends) backendId: stateFor(backendId),
  });
}
