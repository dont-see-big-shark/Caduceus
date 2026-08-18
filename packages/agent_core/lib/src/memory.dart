/// What an agent knows, in a shape both backends can be projected onto.
///
/// See `MEMORY_BRIDGE.md` for why this is a ledger rather than a synchroniser:
/// Hermes has no method to *create* a memory and reports no timestamp on one,
/// so a two-way merge has neither a way to add nor a second clock to compare
/// against. The person is the merge resolver; these types exist to make that
/// cheap and safe rather than to automate it away.
library;

import 'package:meta/meta.dart';

/// What kind of thing an agent remembered.
///
/// Coarse on purpose. Each backend has finer distinctions of its own — Hermes
/// separates a skill from a memory, OpenClaw separates a heading in
/// `MEMORY.md` from `SOUL.md` — and the ones worth carrying across are the
/// ones that change what a person would *do* with the entry.
enum MemoryKind {
  /// Something true about the world or the work.
  fact,

  /// Something about how the user wants to be worked with.
  preference,

  /// Something scoped to a piece of ongoing work.
  project,

  /// A learned capability. Hermes archives these on delete rather than
  /// removing them, which is why they are not just facts.
  skill,

  /// Who the agent is, or who it understands the user to be. Whole documents
  /// rather than lines — `SOUL.md`, `IDENTITY.md`, `USER.md`.
  persona,
}

/// Where an entry came from, kept for the life of the entry.
///
/// The reason a memory pushed from Hermes to OpenClaw and read back is
/// recognised rather than duplicated. Dropping this is how a bridge turns one
/// fact into four over a month.
@immutable
class MemoryOrigin {
  const MemoryOrigin({required this.backendId, required this.nativeId});

  /// The ledger's own entries, authored in the app rather than read from a
  /// backend.
  static const ledger = 'caduceus';

  /// `hermes`, `openclaw`, or [ledger]. Matches [AgentBackend.id].
  final String backendId;

  /// How that backend addresses it — a `learning.*` node id, or
  /// `MEMORY.md#<slug>`. Opaque to everything but the adapter that made it.
  final String nativeId;

  bool get isLedger => backendId == ledger;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemoryOrigin &&
          other.backendId == backendId &&
          other.nativeId == nativeId;

  @override
  int get hashCode => Object.hash(backendId, nativeId);

  @override
  String toString() => '$backendId:$nativeId';
}

/// One thing an agent knows.
@immutable
class MemoryEntry {
  const MemoryEntry({
    required this.id,
    required this.kind,
    required this.text,
    required this.origin,
    this.title = '',
    this.tags = const {},
    this.updatedAt,
  });

  /// The ledger's id, stable across round trips. Distinct from
  /// [MemoryOrigin.nativeId], which is one backend's address for it and
  /// changes when the same fact is written somewhere else.
  final String id;

  final MemoryKind kind;

  /// A heading, or the file name for a [MemoryKind.persona] document.
  final String title;

  /// The content. For a persona document this is the whole file.
  final String text;

  final Set<String> tags;

  /// When the backend last changed it, where the backend says. Null on
  /// Hermes, which reports nothing of the kind — see
  /// [MemoryWriteRefusal.staleRead] for what that costs.
  final DateTime? updatedAt;

  final MemoryOrigin origin;

  /// What a row shows: a real title, else the first line of the text.
  String get label {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final firstLine = text.trim().split('\n').first.trim();
    return firstLine.isEmpty ? id : firstLine;
  }

  /// Round-trips through the ledger's store.
  ///
  /// [MemoryKind] and the origin are written by name rather than by index, so
  /// adding a kind in the middle of the enum does not silently reinterpret
  /// every stored entry as the wrong one.
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'text': text,
    if (tags.isNotEmpty) 'tags': tags.toList(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    'origin': {'backend': origin.backendId, 'native': origin.nativeId},
  };

  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    final originJson = json['origin'] is Map
        ? json['origin'] as Map
        : const <String, dynamic>{};
    return MemoryEntry(
      id: '${json['id'] ?? ''}',
      // An unknown kind — written by a newer build — reads as a plain fact
      // rather than throwing away the entry. Losing the category is a small
      // cost; losing the memory is not.
      kind: MemoryKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => MemoryKind.fact,
      ),
      title: '${json['title'] ?? ''}',
      text: '${json['text'] ?? ''}',
      tags: {for (final t in (json['tags'] as List?) ?? const []) '$t'},
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
      origin: MemoryOrigin(
        backendId: '${originJson['backend'] ?? ''}',
        nativeId: '${originJson['native'] ?? ''}',
      ),
    );
  }

  MemoryEntry copyWith({
    String? id,
    MemoryKind? kind,
    String? title,
    String? text,
    Set<String>? tags,
    DateTime? updatedAt,
    MemoryOrigin? origin,
  }) => MemoryEntry(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    text: text ?? this.text,
    tags: tags ?? this.tags,
    updatedAt: updatedAt ?? this.updatedAt,
    origin: origin ?? this.origin,
  );

  @override
  String toString() => 'MemoryEntry($id, $kind, "$label", from $origin)';
}

/// What to do to one entry.
enum MemoryOp {
  /// Teach the backend something it does not have. **Hermes cannot do this** —
  /// there is no `learning.add` — which is why a backend declares the ops it
  /// supports rather than being asked to fail at the last moment.
  add,

  /// Rewrite an entry the backend already has.
  update,

  /// Take one away. Only ever applied to an entry whose origin the ledger
  /// recorded; a line a human typed is never removed by this feature.
  remove,
}

@immutable
class MemoryChange {
  const MemoryChange(this.op, this.entry);

  final MemoryOp op;
  final MemoryEntry entry;

  @override
  String toString() => '${op.name} ${entry.id}';
}

/// Why one change did not happen.
enum MemoryWriteRefusal {
  /// The backend has no method for this operation at all.
  unsupported,

  /// The file changed on the server between the read and the write. The agent
  /// writes its own memory, so this is an ordinary event rather than an
  /// error — the person re-reads the diff and decides again.
  staleRead,

  /// The entry was not the ledger's to touch.
  notOurs,

  /// The server refused it, in its own words.
  serverRefused,
}

/// What became of one change.
@immutable
class MemoryChangeOutcome {
  const MemoryChangeOutcome.applied(this.change)
      : refusal = null,
        detail = '';

  const MemoryChangeOutcome.refused(
    this.change, {
    required MemoryWriteRefusal this.refusal,
    this.detail = '',
  });

  final MemoryChange change;

  /// Null when it went through.
  final MemoryWriteRefusal? refusal;

  /// The reason in the backend's own terms, for showing verbatim.
  final String detail;

  bool get applied => refusal == null;

  @override
  String toString() =>
      '$change → ${applied ? 'applied' : 'refused: ${refusal!.name}'}';
}

/// The result of one push.
///
/// A batch does not fail as a batch. Hermes refuses every [MemoryOp.add] and
/// accepts the updates in the same push, and the screen has to be able to say
/// exactly that.
@immutable
class MemoryWriteResult {
  const MemoryWriteResult(this.outcomes);

  final List<MemoryChangeOutcome> outcomes;

  Iterable<MemoryChangeOutcome> get applied =>
      outcomes.where((o) => o.applied);
  Iterable<MemoryChangeOutcome> get refused =>
      outcomes.where((o) => !o.applied);

  bool get allApplied => outcomes.every((o) => o.applied);

  @override
  String toString() =>
      'MemoryWriteResult(${applied.length} applied, ${refused.length} refused)';
}
