/// The skills bridge panel — both agents' libraries, side by side.
///
/// Read-only on purpose (SKILLS_BRIDGE.md v1): neither backend can be given
/// arbitrary skill content from here, so the panel compares and shows, and
/// nothing writes. These pin the comparison, the divergence filter, the
/// content viewer and the unreachable banner.
library;

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/skills_panel.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackend implements AgentBackend {
  _FakeBackend({
    this.id = 'hermes',
    this.displayName = 'Hermes',
    List<SkillEntry>? entries,
    this.libraryThrows,
  }) : _entries = entries ?? [];

  @override
  final String id;
  @override
  final String displayName;
  final Object? libraryThrows;
  final List<SkillEntry> _entries;

  @override
  bool supports(Capability capability) => capability == Capability.skills;

  @override
  Future<List<SkillEntry>> skillLibrary() async {
    final error = libraryThrows;
    if (error != null) throw error;
    return List.of(_entries);
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

SkillEntry _skill(
  String key,
  String backend, {
  bool eligible = true,
  String? content,
  String detail = '',
}) => SkillEntry(
  key: key,
  title: key,
  backendId: backend,
  nativeId: key,
  description: '$key does something',
  eligible: eligible,
  detail: detail,
  content: content,
);

Future<void> _pump(
  WidgetTester tester,
  Workspace workspace, {
  MemoryPeers peers = MemoryPeers.none,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: caduceusTheme(Brightness.light),
      home: SkillsPanel(workspace: workspace, peers: peers),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'one skill on both agents is one row; a one-sided skill diverges',
    (tester) async {
      final hermes = _FakeBackend(
        entries: [
          _skill(
            'tavily',
            'hermes',
            content: '---\nname: tavily\n---\n\nBody.',
          ),
          _skill('trim-cli', 'hermes'),
        ],
      );
      final openclaw = _FakeBackend(
        id: 'openclaw',
        displayName: 'OpenClaw',
        entries: [
          _skill(
            'tavily',
            'openclaw',
            eligible: false,
            detail: 'missing bin: gh',
          ),
        ],
      );
      await _pump(
        tester,
        Workspace.forBackend(hermes),
        peers: MemoryPeers(backends: {openclaw.id: openclaw}),
      );

      // Connected alone: both skills, nothing to diverge from yet.
      expect(find.text('tavily'), findsOneWidget);
      expect(find.text('trim-cli'), findsOneWidget);
      expect(find.text('Ask every agent'), findsOneWidget);

      // Reach out: now OpenClaw is in the comparison.
      await tester.tap(find.text('Ask every agent'));
      await tester.pumpAndSettle();

      // tavily is shared → one row; trim-cli is Hermes-only → divergent.
      expect(find.text('tavily'), findsOneWidget);
      expect(find.textContaining('both: hermes, openclaw'), findsOneWidget);
      expect(find.textContaining('not in openclaw'), findsOneWidget);
      expect(
        find.text('1 skill is known to one agent and not the other'),
        findsOneWidget,
      );

      // The divergence filter narrows to the one-sided skill.
      await tester.tap(find.text('Show only these'));
      await tester.pumpAndSettle();
      expect(find.text('trim-cli'), findsOneWidget);
      expect(find.text('tavily'), findsNothing);
    },
  );

  testWidgets('expanding a shared skill shows both copies and the content', (
    tester,
  ) async {
    final hermes = _FakeBackend(
      entries: [
        _skill(
          'tavily',
          'hermes',
          content: '---\nname: tavily\n---\n\nHermes body.',
        ),
      ],
    );
    final openclaw = _FakeBackend(
      id: 'openclaw',
      displayName: 'OpenClaw',
      entries: [
        _skill(
          'tavily',
          'openclaw',
          eligible: false,
          detail: 'missing bin: gh',
        ),
      ],
    );
    await _pump(
      tester,
      Workspace.forBackend(hermes),
      peers: MemoryPeers(backends: {openclaw.id: openclaw}),
    );
    await tester.tap(find.text('Ask every agent'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('tavily'));
    await tester.pumpAndSettle();

    expect(find.text('hermes'), findsOneWidget);
    expect(find.text('openclaw'), findsOneWidget);
    expect(find.text('off · missing bin: gh'), findsOneWidget);
    expect(find.textContaining('Hermes body.'), findsOneWidget);
  });

  testWidgets('a peer that cannot answer is named, not silently dropped', (
    tester,
  ) async {
    final hermes = _FakeBackend(entries: [_skill('tavily', 'hermes')]);
    final openclaw = _FakeBackend(
      id: 'openclaw',
      displayName: 'OpenClaw',
      libraryThrows: StateError('boom'),
    );
    await _pump(
      tester,
      Workspace.forBackend(hermes),
      peers: MemoryPeers(backends: {openclaw.id: openclaw}),
    );
    await tester.tap(find.text('Ask every agent'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach openclaw'), findsOneWidget);
    // Hermes' library is still there.
    expect(find.text('tavily'), findsOneWidget);
  });
}
