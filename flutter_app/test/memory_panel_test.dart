/// The memory bridge's ruling controls — merge, split, remove.
///
/// The design (`MEMORY_BRIDGE.md`) says the person is the merge resolver, but
/// until these tests the only way to make a ruling was in code: `rule()` had
/// no UI call site and `remove` was never issued by the app. Each of these
/// pins one of the controls that closes that loop.
library;

import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/memory_ledger.dart';
import 'package:caduceus/memory_panel.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackend implements AgentBackend {
  _FakeBackend({
    this.id = 'hermes',
    this.displayName = 'Hermes',
    Set<Capability>? capabilities,
    this.memoryOps = const {MemoryOp.update, MemoryOp.remove},
    this.refuseWith,
    List<MemoryEntry>? entries,
  }) : capabilities =
           capabilities ?? {Capability.memoryRead, Capability.memoryWrite},
       _entries = entries ?? [];

  @override
  final String id;
  @override
  final String displayName;
  final Set<Capability> capabilities;
  final Set<MemoryOp> memoryOps;
  final List<MemoryEntry> _entries;

  /// When set, every write comes back refused — for pinning that a refusal
  /// is shown inline instead of blanking the panel.
  final String? refuseWith;
  final applied = <MemoryChange>[];

  @override
  bool supports(Capability capability) => capabilities.contains(capability);

  @override
  Set<MemoryOp> get supportedMemoryOps => memoryOps;

  @override
  Future<List<MemoryEntry>> memory() async => List.of(_entries);

  @override
  Future<MemoryWriteResult> applyMemory(List<MemoryChange> changes) async {
    applied.addAll(changes);
    final refusal = refuseWith;
    if (refusal != null) {
      return MemoryWriteResult([
        for (final change in changes)
          MemoryChangeOutcome.refused(
            change,
            refusal: MemoryWriteRefusal.notOurs,
            detail: refusal,
          ),
      ]);
    }
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

MemoryEntry _entry({
  required String native,
  required String text,
  String title = 'Coffee',
  String backend = 'hermes',
}) => MemoryEntry(
  id: '$backend:$native',
  kind: MemoryKind.fact,
  title: title,
  text: text,
  origin: MemoryOrigin(backendId: backend, nativeId: native),
);

Future<void> _pump(WidgetTester tester, Workspace workspace) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: caduceusTheme(Brightness.light),
      home: MemoryPanel(workspace: workspace),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('two wordings of one fact can be merged, and the ruling sticks', (
    tester,
  ) async {
    final backend = _FakeBackend(
      entries: [
        _entry(native: 'memory:1', text: 'Likes black coffee.'),
        _entry(
          native: 'memory:2',
          title: 'Coffee habit',
          text: 'Prefers black coffee, never after 3pm.',
        ),
      ],
    );
    await _pump(tester, Workspace.forBackend(backend));

    // Two clusters: the fingerprint is conservative and these differ.
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Coffee habit'), findsOneWidget);

    await tester.tap(find.byTooltip('Actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge with another…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coffee habit — hermes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('They are the same'));
    await tester.pumpAndSettle();

    // One cluster now, and the ruling outlives the reload.
    expect(find.text('Coffee habit'), findsOneWidget);
    expect(find.text('Coffee'), findsNothing);
    final verdicts = await MemoryLedger().verdicts();
    expect(verdicts, hasLength(1));
    expect(verdicts.single.same, isTrue);
    expect(
      MemoryVerdict.keyFor(verdicts.single.a, verdicts.single.b),
      MemoryVerdict.keyFor(
        _entry(native: 'memory:1', text: '').origin,
        _entry(native: 'memory:2', text: '').origin,
      ),
    );
  });

  testWidgets('a memory this backend owns can be removed', (tester) async {
    final backend = _FakeBackend(
      entries: [_entry(native: 'memory:1', text: 'Likes black coffee.')],
    );
    await _pump(tester, Workspace.forBackend(backend));

    await tester.tap(find.byTooltip('Actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Delete memory?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.applied, hasLength(1));
    expect(backend.applied.single.op, MemoryOp.remove);
    expect(backend.applied.single.entry.origin.nativeId, 'memory:1');
  });

  testWidgets('a cluster that joined by text can be kept separate', (
    tester,
  ) async {
    // Seed the ledger with an OpenClaw copy of the same fact, so the view has
    // two backends and the cluster the fingerprint joined can be un-joined.
    final openclaw = _entry(
      native: 'MEMORY.md#coffee',
      text: 'Likes black coffee.',
      backend: 'openclaw',
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'memory.snapshots.v1': jsonEncode([
        MemorySnapshot(
          backendId: 'openclaw',
          entries: [openclaw],
          readAt: DateTime.now(),
        ).toJson(),
      ]),
    });

    final backend = _FakeBackend(
      entries: [_entry(native: 'memory:1', text: 'Likes black coffee.')],
    );
    await _pump(tester, Workspace.forBackend(backend));

    // One shared cluster before the ruling.
    expect(find.text('Coffee'), findsOneWidget);

    await tester.tap(find.byTooltip('Actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep separate'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Keep separate'));
    await tester.pumpAndSettle();

    // Two clusters now, and the ruling is persisted.
    expect(find.text('Coffee'), findsNWidgets(2));
    final verdicts = await MemoryLedger().verdicts();
    expect(verdicts, hasLength(1));
    expect(verdicts.single.same, isFalse);
  });

  testWidgets('a refused write is shown inline and the list stays', (
    tester,
  ) async {
    final backend = _FakeBackend(
      refuseWith: 'Only memories this app wrote can be removed.',
      entries: [_entry(native: 'memory:1', text: 'Likes black coffee.')],
    );
    await _pump(tester, Workspace.forBackend(backend));

    await tester.tap(find.byTooltip('Actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // The refusal is a banner, not a blank screen: the row is still there.
    expect(find.textContaining('Only memories this app wrote'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('an OpenClaw copy outside the app block offers no remove', (
    tester,
  ) async {
    // A hand-written entry (no managed tag) is not this app's to delete —
    // R2 is enforced by the adapter, and the menu should not offer the button
    // that would be refused.
    final backend = _FakeBackend(
      id: 'openclaw',
      displayName: 'OpenClaw',
      memoryOps: const {MemoryOp.add, MemoryOp.update, MemoryOp.remove},
      entries: [
        _entry(native: 'MEMORY.md#hand-written', text: 'Hand written note.'),
      ],
    );
    await _pump(tester, Workspace.forBackend(backend));

    final menu = find.byTooltip('Actions');
    expect(menu, findsNothing);
  });
}
