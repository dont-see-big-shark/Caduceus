/// Projecting both bridges into a fleet graph.
///
/// The relationship layer (`AGENT_GRAPH.md`) is pure by construction — it is
/// derived from the same clusters the memory and skills bridges already
/// produce — so every rule it has is testable by feeding it cluster pairs and
/// checking the counts, the presence, and the edges.
library;

import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

MemoryEntry _memory(String backend, String native, String text) => MemoryEntry(
  id: '$backend:$native',
  kind: MemoryKind.fact,
  text: text,
  origin: MemoryOrigin(backendId: backend, nativeId: native),
);

SkillEntry _skill(String key, String backend) =>
    SkillEntry(key: key, title: key, backendId: backend, nativeId: key);

AgentGraph _graph({
  List<MemoryEntry> memory = const [],
  List<SkillEntry> skills = const [],
  Map<String, String> savedLabels = const {},
  String currentBackendId = 'hermes',
  String currentBackendLabel = 'Hermes',
  Set<String> liveBackends = const {'hermes'},
  Map<String, String> unreachable = const {},
}) => buildAgentGraph(
  savedLabels: savedLabels,
  currentBackendId: currentBackendId,
  currentBackendLabel: currentBackendLabel,
  memory: clusterMemories(memory),
  skills: clusterSkills(skills),
  liveBackends: liveBackends,
  unreachable: unreachable,
);

void main() {
  test('one node per backend id, current backend always present', () {
    final graph = _graph(savedLabels: {'openclaw': 'fnos-nas'});

    expect(graph.nodes, hasLength(2));
    expect(graph.node('hermes')!.label, 'Hermes');
    expect(graph.node('openclaw')!.label, 'fnos-nas');
  });

  test('saved label wins over the backend name for the current backend', () {
    final graph = _graph(savedLabels: {'hermes': 'tencent-box'});

    expect(graph.node('hermes')!.label, 'tencent-box');
  });

  test('presence: live, unreachable, and never-asked saved', () {
    final graph = _graph(
      liveBackends: {'hermes'},
      unreachable: {'openclaw': 'read failed'},
      savedLabels: {'openclaw': 'nas', 'pi': 'the pi'},
    );

    expect(graph.node('hermes')!.presence, AgentPresence.live);
    expect(graph.node('openclaw')!.presence, AgentPresence.unreachable);
    // A server nobody asked this time is offline, never live.
    expect(graph.node('pi')!.presence, AgentPresence.saved);
    expect(graph.unreachable['openclaw'], 'read failed');
  });

  test('entry counts are per-agent, divergence is per-cluster', () {
    final graph = _graph(
      memory: [
        _memory('hermes', 'a1', 'likes tea'),
        _memory('hermes', 'a2', 'prefers short answers'),
        _memory('openclaw', 'b1', 'likes tea'),
      ],
      skills: [_skill('tavily', 'hermes'), _skill('tavily', 'openclaw')],
      savedLabels: {'openclaw': 'nas'},
      liveBackends: {'hermes', 'openclaw'},
    );

    final hermes = graph.node('hermes')!;
    final openclaw = graph.node('openclaw')!;
    // Two entries, but one of them shares a cluster with OpenClaw.
    expect(hermes.memoryEntryCount, 2);
    expect(hermes.uniqueMemory, 1);
    expect(openclaw.memoryEntryCount, 1);
    expect(openclaw.uniqueMemory, 0);
    expect(hermes.missingMemoryCount, 0);
    // OpenClaw is missing the "prefers short answers" cluster Hermes has.
    expect(openclaw.missingMemoryCount, 1);
    expect(openclaw.missingMemory.single.best.text, 'prefers short answers');

    // Shared skill clusters join, so neither side is "missing" tavily.
    expect(hermes.skillCount, 1);
    expect(hermes.uniqueSkills, 0);
    expect(hermes.missingSkillsCount, 0);
  });

  test('missing counts the other side has and this side does not', () {
    final graph = _graph(
      memory: [_memory('hermes', 'a1', 'the user is a designer')],
      skills: [_skill('tavily', 'hermes'), _skill('github', 'openclaw')],
      savedLabels: {'openclaw': 'nas'},
      liveBackends: {'hermes', 'openclaw'},
    );

    final openclaw = graph.node('openclaw')!;
    expect(openclaw.missingMemoryCount, 1);
    expect(openclaw.missingSkillsCount, 1);
    expect(openclaw.missingSkills.single.key, 'tavily');
    expect(graph.node('hermes')!.missingSkillsCount, 1);
  });

  test('links count shared and per-side divergence', () {
    final graph = _graph(
      memory: [
        _memory('hermes', 'a1', 'likes tea'),
        _memory('openclaw', 'b1', 'likes tea'),
        _memory('hermes', 'a2', 'prefers short answers'),
      ],
      skills: [
        _skill('tavily', 'hermes'),
        _skill('tavily', 'openclaw'),
        _skill('github', 'hermes'),
      ],
      savedLabels: {'openclaw': 'nas'},
      liveBackends: {'hermes', 'openclaw'},
    );

    final link = graph.linkBetween('hermes', 'openclaw')!;
    expect(link.sharedMemory, 1);
    expect(link.aOnlyMemory, 1);
    expect(link.bOnlyMemory, 0);
    expect(link.sharedSkills, 1);
    expect(link.aOnlySkills, 1);
    expect(link.bOnlySkills, 0);
  });

  test('link lookup is order-independent', () {
    final graph = _graph(savedLabels: {'openclaw': 'nas'});

    expect(graph.linkBetween('openclaw', 'hermes'), isNotNull);
    expect(graph.linkBetween('hermes', 'openclaw'), isNotNull);
  });

  test('the lone marker flags an information island', () {
    final island = _graph(
      skills: [_skill('tavily', 'hermes')],
      savedLabels: {'openclaw': 'nas'},
      liveBackends: {'hermes', 'openclaw'},
    );
    expect(island.node('hermes')!.isLone, isTrue);
    expect(island.node('openclaw')!.isLone, isFalse);

    final sharedOnly = _graph(
      memory: [
        _memory('hermes', 'a1', 'likes tea'),
        _memory('openclaw', 'b1', 'likes tea'),
      ],
      savedLabels: {'openclaw': 'nas'},
      liveBackends: {'hermes', 'openclaw'},
    );
    expect(sharedOnly.node('hermes')!.isLone, isFalse);
  });

  test('a single agent yields nodes and no links', () {
    final graph = _graph();

    expect(graph.nodes, hasLength(1));
    expect(graph.links, isEmpty);
  });

  test('no saved servers still shows the current backend, with no links', () {
    final graph = buildAgentGraph(
      savedLabels: const {},
      currentBackendId: 'hermes',
      currentBackendLabel: 'Hermes',
      memory: const [],
      skills: const [],
      liveBackends: const {'hermes'},
      unreachable: const {},
    );

    expect(graph.nodes, hasLength(1));
    expect(graph.links, isEmpty);
    expect(graph.node('hermes')!.presence, AgentPresence.live);
  });

  test('unreachable is surfaced, not dropped', () {
    final graph = _graph(
      unreachable: {'openclaw': 'handshake failed'},
      savedLabels: {'openclaw': 'nas'},
    );

    expect(graph.unreachable, {'openclaw': 'handshake failed'});
    expect(graph.node('openclaw')!.presence, AgentPresence.unreachable);
  });
}
