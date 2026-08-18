/// The shared knowledge base's pure core — `SHARED_MEMORY.md` §3–§4.
///
/// Five states, the anchor rule, and the "never guess" rule: a fact's copy is
/// identified by the anchor the sync left, or by fingerprint search when there
/// is none, and an unreachable agent is never reported as missing.
library;

import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

SharedFact _fact(String text, {String id = 'f1'}) => SharedFact(
  id: id,
  kind: MemoryKind.fact,
  text: text,
  updatedAt: DateTime(2026, 8, 9),
);

MemoryEntry _entry(String backend, String native, String text) => MemoryEntry(
  id: '$backend:$native',
  kind: MemoryKind.fact,
  text: text,
  origin: MemoryOrigin(backendId: backend, nativeId: native),
);

SyncAnchor _anchor(String factId, String backend, String native, String text) =>
    SyncAnchor(
      factId: factId,
      backendId: backend,
      nativeId: native,
      fingerprint: MemoryFingerprint.of(text).value,
      syncedAt: DateTime(2026, 8, 9),
    );

Map<String, AgentFactState> _detect({
  required SharedFact fact,
  List<MemoryEntry> entries = const [],
  Set<String> knownBackends = const {'hermes', 'openclaw'},
  Map<String, String> unreachable = const {},
  Map<String, SyncAnchor> anchors = const {},
}) => detectFactStates(
  fact: fact,
  clusters: clusterMemories(entries),
  knownBackends: knownBackends,
  unreachable: unreachable,
  anchors: anchors,
).byBackend;

void main() {
  test('an anchored entry that matches is synced', () {
    final states = _detect(
      fact: _fact('the user likes tea'),
      entries: [_entry('openclaw', 'MEMORY.md#likes-tea', 'the user likes tea')],
      anchors: {'openclaw': _anchor('f1', 'openclaw', 'MEMORY.md#likes-tea', 'the user likes tea')},
    );

    expect(states['openclaw']!.status, AgentFactStatus.synced);
    expect(states['openclaw']!.nativeId, 'MEMORY.md#likes-tea');
  });

  test('an anchored entry whose content moved is drifted, with both sides', () {
    final states = _detect(
      fact: _fact('the user likes tea'),
      entries: [_entry('openclaw', 'MEMORY.md#likes-tea', 'the user dislikes tea')],
      anchors: {'openclaw': _anchor('f1', 'openclaw', 'MEMORY.md#likes-tea', 'the user likes tea')},
    );

    expect(states['openclaw']!.status, AgentFactStatus.drifted);
    expect(states['openclaw']!.localText, 'the user dislikes tea');
    expect(states['openclaw']!.nativeId, 'MEMORY.md#likes-tea');
  });

  test('a fact edited since sync reads as drifted on an un-updated copy', () {
    // The canonical fact was rewritten; the agent still holds the old wording.
    final states = _detect(
      fact: _fact('the user likes green tea'),
      entries: [_entry('openclaw', 'MEMORY.md#likes-tea', 'the user likes tea')],
      anchors: {'openclaw': _anchor('f1', 'openclaw', 'MEMORY.md#likes-tea', 'the user likes tea')},
    );

    expect(states['openclaw']!.status, AgentFactStatus.drifted);
  });

  test('an anchor whose entry vanished falls back to fingerprint search', () {
    final states = _detect(
      fact: _fact('the user likes tea'),
      entries: [_entry('openclaw', 'MEMORY.md#some-other-slug', 'the user likes tea')],
      // The anchored slug no longer exists.
      anchors: {'openclaw': _anchor('f1', 'openclaw', 'MEMORY.md#old-slug', 'the user likes tea')},
    );

    // Found by fingerprint, so it is synced — and the state carries the new id.
    expect(states['openclaw']!.status, AgentFactStatus.synced);
    expect(states['openclaw']!.nativeId, 'MEMORY.md#some-other-slug');
  });

  test('no anchor and no fingerprint match is missing', () {
    final states = _detect(
      fact: _fact('the user likes tea'),
      entries: [_entry('openclaw', 'MEMORY.md#x', 'the user prefers coffee')],
    );

    expect(states['openclaw']!.status, AgentFactStatus.missing);
    expect(states['openclaw']!.nativeId, isNull);
  });

  test('unreachable is unverifiable, never missing', () {
    final states = _detect(
      fact: _fact('the user likes tea'),
      unreachable: {'hermes': 'read failed'},
    );

    expect(states['hermes']!.status, AgentFactStatus.unverifiable);
    expect(states['hermes']!.detail, 'read failed');
  });

  test('an unrelated entry is never taken for the copy', () {
    // Anchor points at a nativeId that still exists but holds a different,
    // un-anchored fact — the drifted verdict must come from the anchor, not
    // from a fingerprint guess that this entry used to be the shared one.
    final states = _detect(
      fact: _fact('the user likes tea'),
      entries: [_entry('openclaw', 'MEMORY.md#coffee', 'the user prefers coffee')],
      anchors: {'openclaw': _anchor('f1', 'openclaw', 'MEMORY.md#coffee', 'the user likes tea')},
    );

    // Same nativeId, different content: drifted (anchor says this was the copy).
    expect(states['openclaw']!.status, AgentFactStatus.drifted);
    expect(states['openclaw']!.localText, 'the user prefers coffee');
  });

  test('missing folds into needs-attention; fully synced does not', () {
    final missing = detectFactStates(
      fact: _fact('x'),
      clusters: const [],
      knownBackends: {'hermes'},
      unreachable: const {},
      anchors: const {},
    );
    expect(missing.anyNeedsAttention, isTrue);

    final synced = detectFactStates(
      fact: _fact('the user likes tea'),
      clusters: clusterMemories([_entry('hermes', 'n1', 'the user likes tea')]),
      knownBackends: {'hermes'},
      unreachable: const {},
      anchors: const {},
    );
    expect(synced.anyNeedsAttention, isFalse);
  });

  test('persona facts are rejected by construction', () {
    expect(
      () => SharedFact(id: 'p', kind: MemoryKind.persona, text: 'x', updatedAt: DateTime(2026)),
      throwsA(anything),
    );
  });

  test('round trips through json', () {
    final fact = _fact('the user likes tea', id: 'f9');
    final restored = SharedFact.fromJson(fact.toJson());
    expect(restored.id, 'f9');
    expect(restored.text, 'the user likes tea');
    expect(restored.kind, MemoryKind.fact);

    final anchor = _anchor('f9', 'openclaw', 'MEMORY.md#t', 'the user likes tea');
    final anchorRestored = SyncAnchor.fromJson(anchor.toJson());
    expect(anchorRestored.factId, 'f9');
    expect(anchorRestored.nativeId, 'MEMORY.md#t');
  });
}
