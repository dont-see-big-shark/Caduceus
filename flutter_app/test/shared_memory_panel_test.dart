/// The shared knowledge base panel — `SHARED_MEMORY.md` §5.
///
/// Widget-level claims: the roster shows every fact with each agent's verdict;
/// a fact detail offers the sync that closes a missing gap and the
/// side-by-side + Restore / Keep-local that resolves a drift (Keep local is
/// per-reading); drop asks about the copies; compose adds to the physical
/// store. The sheet navigates inside itself on a phone.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_backend.dart';
import 'package:caduceus/shared_memory_panel.dart';
import 'package:caduceus/widgets/panel_frame.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Hermes whose agent "remembers" what it is asked, so the sync round-trips.
class _RememberingHermes extends HermesBackend {
  _RememberingHermes()
    : super(
        HermesGateway(
          HermesEndpoint.parse('https://hermes.example', credential: 't'),
          connector: (uri) async => throw UnimplementedError(),
        ),
      );

  final List<String> asked = [];
  List<MemoryEntry> entries = [];

  @override
  Future<({String? nativeId, String? landedText, String detail})>
  syncMemoryViaAgent(String text) async {
    asked.add(text);
    entries = [
      MemoryEntry(
        id: 'hermes:memory:memory:9',
        kind: MemoryKind.fact,
        text: text,
        origin: const MemoryOrigin(
          backendId: 'hermes',
          nativeId: 'memory:memory:9',
        ),
      ),
    ];
    return (nativeId: 'memory:memory:9', landedText: text, detail: '');
  }

  @override
  Future<List<MemoryEntry>> memory() async => List.of(entries);
}

Future<Workspace> _workspace(AgentBackend backend) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return Workspace.forBackend(backend);
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required Workspace workspace,
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
                  (_) => SharedMemoryPanel(workspace: workspace),
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

  testWidgets('the roster shows the fact and a missing verdict', (
    tester,
  ) async {
    final hermes = _RememberingHermes();
    final ws = await _workspace(hermes);
    await ws.ledger.saveSharedFact(
      SharedFact(
        id: 'f1',
        kind: MemoryKind.fact,
        text: 'the user likes tea',
        updatedAt: DateTime(2026, 8, 9),
      ),
    );

    await _pumpPanel(tester, workspace: ws);

    expect(find.text('Shared memory'), findsOneWidget);
    expect(find.text('the user likes tea'), findsWidgets);
    expect(find.textContaining('hermes · missing'), findsOneWidget);
  });

  testWidgets('sync asks the agent and the verdict becomes synced', (
    tester,
  ) async {
    final hermes = _RememberingHermes();
    final ws = await _workspace(hermes);
    await ws.ledger.saveSharedFact(
      SharedFact(
        id: 'f1',
        kind: MemoryKind.fact,
        text: 'the user likes tea',
        updatedAt: DateTime(2026, 8, 9),
      ),
    );

    await _pumpPanel(tester, workspace: ws);
    await tester.tap(find.text('the user likes tea').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Sync to Hermes'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Sync to Hermes'));
    await tester.tap(find.textContaining('Sync to Hermes'));
    await tester.pumpAndSettle();

    expect(hermes.asked, hasLength(1));
    expect(hermes.asked.single, contains('the user likes tea'));
    expect(find.text('synced'), findsOneWidget);
  });

  testWidgets(
    'a drift shows both wordings; Keep local folds it for this reading',
    (tester) async {
      final hermes = _RememberingHermes();
      // The agent holds the fact under the anchored id but with old wording.
      hermes.entries = [
        MemoryEntry(
          id: 'hermes:memory:memory:1',
          kind: MemoryKind.fact,
          text: 'the user likes green tea',
          origin: const MemoryOrigin(
            backendId: 'hermes',
            nativeId: 'memory:memory:1',
          ),
        ),
      ];
      final ws = await _workspace(hermes);
      final fact = SharedFact(
        id: 'f1',
        kind: MemoryKind.fact,
        text: 'the user likes tea',
        updatedAt: DateTime(2026, 8, 9),
      );
      await ws.ledger.saveSharedFact(fact);
      await ws.ledger.recordAnchor(
        SyncAnchor(
          factId: fact.id,
          backendId: 'hermes',
          nativeId: 'memory:memory:1',
          fingerprint: MemoryFingerprint.of('the user likes tea').value,
          syncedAt: DateTime(2026, 8, 9),
        ),
      );

      await _pumpPanel(tester, workspace: ws);
      await tester.tap(find.text('the user likes tea').first);
      await tester.pumpAndSettle();

      expect(find.text('drifted'), findsOneWidget);
      expect(find.text('shared'), findsOneWidget);
      expect(find.text('local'), findsOneWidget);
      expect(find.text('Restore shared'), findsOneWidget);

      // Keep local folds the drift for this reading.
      await tester.tap(find.text('Keep local'));
      await tester.pumpAndSettle();
      expect(find.textContaining('kept · this reading'), findsOneWidget);
      expect(find.text('Restore shared'), findsNothing);
    },
  );

  testWidgets('drop asks about the copies, then removes the fact', (
    tester,
  ) async {
    final hermes = _RememberingHermes();
    final ws = await _workspace(hermes);
    final fact = SharedFact(
      id: 'f1',
      kind: MemoryKind.fact,
      text: 'the user likes tea',
      updatedAt: DateTime(2026, 8, 9),
    );
    await ws.ledger.saveSharedFact(fact);

    await _pumpPanel(tester, workspace: ws);
    await tester.tap(find.text('the user likes tea').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Remove "the user likes tea"'), findsOneWidget);
    expect(find.textContaining('Also remove the copies'), findsOneWidget);

    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();

    expect(await ws.ledger.sharedFacts(), isEmpty);
    expect(find.textContaining('Nothing is shared yet'), findsOneWidget);
  });

  testWidgets('compose adds a fact to the physical store', (tester) async {
    final hermes = _RememberingHermes();
    final ws = await _workspace(hermes);

    await _pumpPanel(tester, workspace: ws);
    await tester.tap(find.text('New fact'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'the user prefers short answers',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await ws.ledger.sharedFacts(), hasLength(1));
    expect(
      (await ws.ledger.sharedFacts()).single.text,
      'the user prefers short answers',
    );
    expect(find.text('the user prefers short answers'), findsWidgets);
  });
}
