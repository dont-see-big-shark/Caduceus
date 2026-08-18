/// The fleet — `AGENT_GRAPH.md`'s relationship layer, as a panel.
///
/// Widget-level claims: the roster shows every agent with what it holds, what
/// it alone has, and what it is missing; the three depths navigate inside the
/// sheet (no stacked routes on a phone); an unreachable server is shown, not
/// dropped; and the push that closes a gap goes through the same
/// `MemoryOp.add` path the memory panel uses.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/fleet_panel.dart';
import 'package:caduceus/widgets/panel_frame.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

MemoryEntry _memory(String backend, String native, String text) => MemoryEntry(
  id: '$backend:$native',
  kind: MemoryKind.fact,
  text: text,
  origin: MemoryOrigin(backendId: backend, nativeId: native),
);

SkillEntry _skill(String key, String backend) =>
    SkillEntry(key: key, title: key, backendId: backend, nativeId: key);

class _FakeBackend implements AgentBackend {
  _FakeBackend({
    this.id = 'hermes',
    this.displayName = 'Hermes',
    this.memoryThrows,
    this.skillThrows,
    List<MemoryEntry>? memory,
    List<SkillEntry>? skills,
    this.canWrite = false,
  }) : _memory = memory ?? [],
       _skills = skills ?? [];

  @override
  final String id;
  @override
  final String displayName;
  final Object? memoryThrows;
  final Object? skillThrows;
  final bool canWrite;
  final List<MemoryEntry> _memory;
  final List<SkillEntry> _skills;

  final List<MemoryChange> applied = [];

  @override
  bool supports(Capability capability) => switch (capability) {
    Capability.memoryRead || Capability.skills => true,
    Capability.memoryWrite => canWrite,
    _ => false,
  };

  @override
  Set<MemoryOp> get supportedMemoryOps =>
      canWrite ? MemoryOp.values.toSet() : const {};

  @override
  Future<List<MemoryEntry>> memory() async {
    final error = memoryThrows;
    if (error != null) throw error;
    return List.of(_memory);
  }

  @override
  Future<List<SkillEntry>> skillLibrary() async {
    final error = skillThrows;
    if (error != null) throw error;
    return List.of(_skills);
  }

  @override
  Future<MemoryWriteResult> applyMemory(List<MemoryChange> changes) async {
    applied.addAll(changes);
    return MemoryWriteResult([
      for (final change in changes) MemoryChangeOutcome.applied(change),
    ]);
  }

  @override
  AgentConnection get connectionState => AgentConnection.disconnected;
  @override
  Stream<AgentConnection> get connection => const Stream.empty();
  @override
  Stream<AgentSession> get sessionUpdates => const Stream.empty();
  @override
  Future<void> connect() async {}
  @override
  Future<void> dispose() async {}

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<Workspace> _workspace(AgentBackend backend) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return Workspace.forBackend(backend);
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required Workspace workspace,
  MemoryPeers peers = MemoryPeers.none,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showPanel<void>(
                  context,
                  (_) => FleetPanel(workspace: workspace, peers: peers),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('the roster shows both agents, the edge, and the lone marker', (
    tester,
  ) async {
    final hermes = _FakeBackend(
      id: 'hermes',
      displayName: 'Hermes',
      memory: [
        _memory('hermes', 'a1', 'likes tea'),
        _memory('hermes', 'a2', 'prefers short answers'),
      ],
      skills: [_skill('tavily', 'hermes'), _skill('github', 'hermes')],
    );
    final openclaw = _FakeBackend(
      id: 'openclaw',
      displayName: 'OpenClaw',
      memory: [_memory('openclaw', 'b1', 'likes tea')],
      skills: [_skill('tavily', 'openclaw')],
    );
    final ws = await _workspace(hermes);

    await _pumpPanel(
      tester,
      workspace: ws,
      peers: MemoryPeers(backends: {openclaw.id: openclaw}),
    );

    expect(find.text('Fleet'), findsOneWidget);
    expect(find.text('Hermes'), findsWidgets);
    expect(find.text('OpenClaw'), findsWidgets);
    // The edge row: one shared fact, one shared skill.
    expect(find.textContaining('1 facts shared'), findsOneWidget);
    expect(find.textContaining('1 skills shared'), findsOneWidget);
    // Hermes alone knows "prefers short answers" and can do github.
    expect(
      find.textContaining('only here · 1 memories · 1 skills'),
      findsOneWidget,
    );
    // The lone marker — it holds something nobody else does.
    expect(find.byIcon(Icons.waves_rounded), findsWidgets);
    // OpenClaw is missing that memory and that skill.
    expect(
      find.textContaining('missing · 1 memories · 1 skills'),
      findsOneWidget,
    );
  });

  testWidgets('an unreachable server is shown, not dropped', (tester) async {
    final hermes = _FakeBackend(displayName: 'Hermes');
    final openclaw = _FakeBackend(
      id: 'openclaw',
      displayName: 'OpenClaw',
      memoryThrows: StateError('boom'),
      skillThrows: StateError('boom'),
    );
    final ws = await _workspace(hermes);

    await _pumpPanel(
      tester,
      workspace: ws,
      peers: MemoryPeers(backends: {openclaw.id: openclaw}),
    );

    expect(find.textContaining('Could not reach openclaw'), findsOneWidget);
    // The node still exists, greyed with its state rather than vanished.
    expect(find.textContaining('OpenClaw · unreachable'), findsOneWidget);
  });

  testWidgets('an agent detail lists what it is missing and offers the push', (
    tester,
  ) async {
    final hermes = _FakeBackend(
      id: 'hermes',
      displayName: 'Hermes',
      memory: [
        _memory('hermes', 'a1', 'likes tea'),
        _memory('hermes', 'a2', 'prefers short answers'),
      ],
      skills: [_skill('tavily', 'hermes')],
    );
    // OpenClaw can take new memories — the push button depends on it.
    final openclaw = _FakeBackend(
      id: 'openclaw',
      displayName: 'OpenClaw',
      canWrite: true,
      memory: [_memory('openclaw', 'b1', 'likes tea')],
      skills: [_skill('tavily', 'openclaw')],
    );
    final ws = await _workspace(hermes);

    await _pumpPanel(
      tester,
      workspace: ws,
      peers: MemoryPeers(backends: {openclaw.id: openclaw}),
    );

    // Open into OpenClaw's detail.
    await tester.tap(find.text('OpenClaw').last);
    await tester.pumpAndSettle();

    expect(find.text('Missing · 1'), findsOneWidget);
    expect(find.text('prefers short answers'), findsOneWidget);
    expect(find.text('known to hermes'), findsOneWidget);
    // It can receive a memory, so the push is offered.
    expect(find.text('Teach'), findsOneWidget);
    // It shares the one fact, so the knows section shows it.
    expect(find.textContaining('likes tea'), findsWidgets);
  });

  testWidgets('the push goes through applyMemory and reports refusals inline', (
    tester,
  ) async {
    final hermes = _FakeBackend(
      id: 'hermes',
      displayName: 'Hermes',
      memory: [
        _memory('hermes', 'a1', 'likes tea'),
        _memory('hermes', 'a2', 'prefers short answers'),
      ],
    );
    final openclaw = _FakeBackend(
      id: 'openclaw',
      displayName: 'OpenClaw',
      canWrite: true,
      memory: [_memory('openclaw', 'b1', 'likes tea')],
      skills: [_skill('tavily', 'openclaw')],
    );
    final ws = await _workspace(hermes);

    await _pumpPanel(
      tester,
      workspace: ws,
      peers: MemoryPeers(backends: {openclaw.id: openclaw}),
    );

    await tester.tap(find.text('OpenClaw').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teach'));
    await tester.pumpAndSettle();

    // The confirmation names the target and the memory.
    expect(find.text('Teach OpenClaw this memory?'), findsOneWidget);
    expect(find.text('+ prefers short answers'), findsOneWidget);
    await tester.tap(find.text('Teach it'));
    await tester.pumpAndSettle();

    expect(openclaw.applied, hasLength(1));
    expect(openclaw.applied.single.op, MemoryOp.add);
    expect(openclaw.applied.single.entry.text, 'prefers short answers');
  });

  testWidgets('a target that cannot receive a memory offers no push', (
    tester,
  ) async {
    // Hermes cannot add memories — there is no learning.add.
    final hermes = _FakeBackend(
      id: 'hermes',
      displayName: 'Hermes',
      canWrite: true,
      memory: [
        _memory('hermes', 'a1', 'likes tea'),
        _memory('hermes', 'a2', 'prefers short answers'),
      ],
    );
    // OpenClaw has no add either in this world (e.g. no operator.admin).
    final openclaw = _FakeBackend(
      id: 'openclaw',
      displayName: 'OpenClaw',
      memory: [_memory('openclaw', 'b1', 'likes tea')],
    );
    final ws = await _workspace(hermes);

    await _pumpPanel(
      tester,
      workspace: ws,
      peers: MemoryPeers(backends: {openclaw.id: openclaw}),
    );

    await tester.tap(find.text('OpenClaw').last);
    await tester.pumpAndSettle();

    // The memory is listed as missing, but there is no Teach control.
    expect(find.text('prefers short answers'), findsOneWidget);
    expect(find.text('Teach'), findsNothing);
  });

  testWidgets('the cross view says who has it and who does not', (
    tester,
  ) async {
    final hermes = _FakeBackend(
      id: 'hermes',
      displayName: 'Hermes',
      memory: [
        _memory('hermes', 'a1', 'likes tea'),
        _memory('hermes', 'a2', 'prefers short answers'),
      ],
    );
    final openclaw = _FakeBackend(
      id: 'openclaw',
      displayName: 'OpenClaw',
      canWrite: true,
      memory: [_memory('openclaw', 'b1', 'likes tea')],
    );
    final ws = await _workspace(hermes);

    await _pumpPanel(
      tester,
      workspace: ws,
      peers: MemoryPeers(backends: {openclaw.id: openclaw}),
    );

    await tester.tap(find.text('OpenClaw').last);
    await tester.pumpAndSettle();
    // Open the missing memory into the cross view.
    await tester.tap(find.text('prefers short answers'));
    await tester.pumpAndSettle();

    expect(find.text('Has it'), findsOneWidget);
    expect(find.text('Does not have it'), findsOneWidget);
    expect(find.text('Teach OpenClaw'), findsOneWidget);

    // Back returns to the detail, not to the roster.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Missing · 1'), findsOneWidget);
  });

  testWidgets('skills are read-only: missing skill shows guidance, no button', (
    tester,
  ) async {
    final hermes = _FakeBackend(
      id: 'hermes',
      displayName: 'Hermes',
      skills: [_skill('github', 'hermes')],
    );
    final openclaw = _FakeBackend(id: 'openclaw', displayName: 'OpenClaw');
    final ws = await _workspace(hermes);

    await _pumpPanel(
      tester,
      workspace: ws,
      peers: MemoryPeers(backends: {openclaw.id: openclaw}),
    );

    await tester.tap(find.text('OpenClaw').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('OpenClaw installs from ClawHub'),
      findsOneWidget,
    );
    expect(find.text('Teach'), findsNothing);
  });
}
