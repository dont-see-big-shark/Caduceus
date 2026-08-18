/// The shared knowledge base, workspace layer — `SHARED_MEMORY.md` §4–§6.
///
/// The view assembles facts from the physical store and states from the same
/// detector the bridge feeds; the sync writes through the backend the way the
/// design says (Hermes via its agent with read-back verification, OpenClaw
/// through the block with a read-back anchor) and records what actually
/// landed.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/claw_backend.dart';
import 'package:caduceus/backends/hermes_backend.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Hermes that records the asks instead of contacting a real agent.
class _RecordingHermes extends HermesBackend {
  _RecordingHermes()
    : super(
        HermesGateway(
          HermesEndpoint.parse('https://hermes.example', credential: 't'),
          connector: (uri) async => throw UnimplementedError(),
        ),
      );

  final List<String> asked = [];
  final List<(String, String)> restored = [];
  final List<String> removed = [];

  /// What [memory] answers on read-back.
  List<MemoryEntry> entries = [];

  @override
  Future<({String? nativeId, String? landedText, String detail})>
  syncMemoryViaAgent(String text) async {
    asked.add(text);
    return (nativeId: 'memory:memory:9', landedText: text, detail: '');
  }

  @override
  Future<List<MemoryEntry>> memory() async => List.of(entries);

  @override
  Future<String?> restoreMemoryNode(String nativeId, String text) async {
    restored.add((nativeId, text));
    return null;
  }

  @override
  Future<String?> removeMemoryNode(String nativeId) async {
    removed.add(nativeId);
    return null;
  }
}

/// An OpenClaw that records writes and answers read-back from [entries].
class _RecordingClaw extends ClawBackend {
  _RecordingClaw(ClawDeviceIdentity identity)
    : super(
        ClawGateway(
          ClawEndpoint(url: Uri.parse('wss://claw.example'), token: 't'),
          identity: identity,
          connector: (e) async => throw UnimplementedError(),
        ),
      );

  final List<MemoryChange> applied = [];

  /// What [memory] answers on read-back.
  List<MemoryEntry> entries = [];

  @override
  Future<MemoryWriteResult> applyMemory(List<MemoryChange> changes) async {
    applied.addAll(changes);
    return MemoryWriteResult([
      for (final change in changes) MemoryChangeOutcome.applied(change),
    ]);
  }

  @override
  Future<List<MemoryEntry>> memory() async => List.of(entries);
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('sharedMemoryView assembles facts and per-agent states', () async {
    final hermes = _RecordingHermes()
      ..entries = [_entry('hermes', 'memory:memory:1', 'the user likes tea')];
    final ws = Workspace.forBackend(hermes);
    await ws.ledger.saveSharedFact(_fact('the user likes tea'));

    final view = await ws.sharedMemoryView();

    expect(view.facts, hasLength(1));
    final states = view.statesFor('f1')!.byBackend;
    // The connected agent holds the fact verbatim → synced.
    expect(states['hermes']!.status, AgentFactStatus.synced);
    expect(states['hermes']!.nativeId, 'memory:memory:1');
  });

  test('a fact missing on the connected agent reads as missing', () async {
    final hermes = _RecordingHermes();
    final ws = Workspace.forBackend(hermes);
    await ws.ledger.saveSharedFact(_fact('the user likes tea'));

    final view = await ws.sharedMemoryView();

    expect(view.needsAttention, hasLength(1));
    expect(
      view.statesFor('f1')!.byBackend['hermes']!.status,
      AgentFactStatus.missing,
    );
  });

  test('sync to Hermes asks its agent and anchors the landed node', () async {
    final hermes = _RecordingHermes();
    final ws = Workspace.forBackend(hermes);
    final fact = _fact('the user likes tea');
    await ws.ledger.saveSharedFact(fact);

    final result = await ws.syncSharedFact(fact, hermes);

    expect(result.ok, isTrue);
    expect(result.nativeId, 'memory:memory:9');
    expect(hermes.asked, hasLength(1));
    expect(hermes.asked.single, contains('the user likes tea'));

    final anchors = await ws.ledger.anchorsFor(fact.id);
    expect(anchors['hermes']!.nativeId, 'memory:memory:9');
  });

  test(
    'sync to OpenClaw writes the block and anchors the read-back entry',
    () async {
      final claw = _RecordingClaw(await ClawDeviceIdentity.generate())
        ..entries = [
          _entry('openclaw', 'MEMORY.md#likes-tea', 'the user likes tea'),
        ];
      final ws = Workspace.forBackend(claw);
      final fact = _fact('the user likes tea');
      await ws.ledger.saveSharedFact(fact);

      final result = await ws.syncSharedFact(fact, claw);

      expect(result.ok, isTrue);
      expect(claw.applied.single.op, MemoryOp.add);
      final anchors = await ws.ledger.anchorsFor(fact.id);
      expect(anchors['openclaw']!.nativeId, 'MEMORY.md#likes-tea');
    },
  );

  test('restore rewrites the drifted copy and re-anchors', () async {
    final hermes = _RecordingHermes();
    final ws = Workspace.forBackend(hermes);
    final fact = _fact('the user likes tea');
    await ws.ledger.saveSharedFact(fact);
    await ws.ledger.recordAnchor(
      SyncAnchor(
        factId: fact.id,
        backendId: 'hermes',
        nativeId: 'memory:memory:3',
        fingerprint: MemoryFingerprint.of('the user likes tea').value,
        syncedAt: DateTime(2026, 8, 9),
      ),
    );
    final anchor = (await ws.ledger.anchorsFor(fact.id))['hermes']!;

    final result = await ws.restoreSharedFact(fact, hermes, anchor);

    expect(result.ok, isTrue);
    expect(hermes.restored, [(('memory:memory:3', 'the user likes tea'))]);
  });

  test('drop removes the fact and, when asked, the app-owned copies', () async {
    final hermes = _RecordingHermes();
    final ws = Workspace.forBackend(hermes);
    final fact = _fact('the user likes tea', id: 'f9');
    await ws.ledger.saveSharedFact(fact);
    await ws.ledger.recordAnchor(
      SyncAnchor(
        factId: fact.id,
        backendId: 'hermes',
        nativeId: 'memory:memory:5',
        fingerprint: MemoryFingerprint.of(fact.text).value,
        syncedAt: DateTime(2026, 8, 9),
      ),
    );

    final notes = await ws.dropSharedFact(
      fact.id,
      removeCopies: true,
      targets: [hermes],
    );

    expect(notes, isEmpty);
    expect(hermes.removed, ['memory:memory:5']);
    expect(await ws.ledger.sharedFacts(), isEmpty);
  });

  test('drop without copies leaves the agent memory alone', () async {
    final hermes = _RecordingHermes();
    final ws = Workspace.forBackend(hermes);
    final fact = _fact('the user likes tea', id: 'f10');
    await ws.ledger.saveSharedFact(fact);
    await ws.ledger.recordAnchor(
      SyncAnchor(
        factId: fact.id,
        backendId: 'hermes',
        nativeId: 'memory:memory:6',
        fingerprint: MemoryFingerprint.of(fact.text).value,
        syncedAt: DateTime(2026, 8, 9),
      ),
    );

    await ws.dropSharedFact(fact.id, removeCopies: false, targets: [hermes]);

    expect(hermes.removed, isEmpty);
    expect(await ws.ledger.sharedFacts(), isEmpty);
  });
}
