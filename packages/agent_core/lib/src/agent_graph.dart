/// The fleet — every agent, and the edges between them.
///
/// The relationship layer above the two bridges. `MEMORY_BRIDGE.md` and
/// `SKILLS_BRIDGE.md` each answer "what does one agent have" one cluster at a
/// time; this projects the same clusters back into a view organised by
/// *agent*, so "who knows whom, and who is missing what" is answerable in one
/// glance. See `AGENT_GRAPH.md`.
///
/// Pure — no store, no gateway — because it is derived entirely from the
/// cluster types the bridges already produce. Anything it can get wrong is
/// found by feeding it awkward cluster pairs, which is why it lives beside
/// the matching code rather than in a widget.
library;

import 'package:meta/meta.dart';

import 'memory_match.dart';
import 'skill.dart';

/// Whether a node was actually asked this time.
enum AgentPresence {
  /// Answered just now — the connected tab, or a server reached out to.
  live,

  /// Asked and could not answer. Why is in [AgentGraph.unreachable].
  unreachable,

  /// In the saved list, not asked this time. Shown as offline, never as live.
  saved,
}

/// One agent in the fleet.
@immutable
class AgentNode {
  const AgentNode({
    required this.backendId,
    required this.label,
    required this.presence,
    required this.memoryEntryCount,
    required this.skillCount,
    required this.uniqueMemory,
    required this.uniqueSkills,
    required this.missingMemoryCount,
    required this.missingSkillsCount,
    required this.missingMemory,
    required this.missingSkills,
    required this.memory,
    required this.skills,
  });

  /// Matches [AgentBackend.id] — `hermes`, `openclaw`.
  final String backendId;

  /// What to call it: the saved server's display label where there is one,
  /// else the backend's own name.
  final String label;

  final AgentPresence presence;

  /// How many [MemoryEntry]s this agent holds. What a person means by "how
  /// much does it know".
  final int memoryEntryCount;

  /// How many [SkillEntry]s this agent holds. What a person means by "what
  /// can it do"; eligibility is shown in the detail pane, not folded away
  /// here, so the number agrees with the skills panel's.
  final int skillCount;

  /// Clusters whose every copy lives on this agent alone.
  final int uniqueMemory;
  final int uniqueSkills;

  /// Clusters another agent has and this one does not. The "missing" list the
  /// graph exists to surface, and the count is what a card shows without
  /// expanding it.
  final int missingMemoryCount;
  final int missingSkillsCount;
  final List<MemoryCluster> missingMemory;
  final List<SkillCluster> missingSkills;

  /// The agent's own clusters, for the detail pane.
  final List<MemoryCluster> memory;
  final List<SkillCluster> skills;

  /// An agent is a **lone** node when it holds something nobody else does.
  ///
  /// The graph's "information island" marker. Deliberately simple — one
  /// unique skill, or more unique memory than shared memory — and calibrated
  /// in `AGENT_GRAPH.md` §9 against the real fleet before it becomes a badge
  /// with pretensions.
  bool get isLone =>
      uniqueSkills > 0 || uniqueMemory > sharedMemoryCount;

  int get sharedMemoryCount => memoryEntryCount - uniqueMemory;

  @override
  String toString() => 'AgentNode($backendId, $label, ${presence.name})';
}

/// The edge between two agents: how much they agree, per side.
@immutable
class AgentLink {
  const AgentLink({
    required this.a,
    required this.b,
    required this.sharedMemory,
    required this.sharedSkills,
    required this.aOnlyMemory,
    required this.bOnlyMemory,
    required this.aOnlySkills,
    required this.bOnlySkills,
  });

  final String a;
  final String b;

  /// Clusters present on both — the two agents agree about these.
  final int sharedMemory;
  final int sharedSkills;

  /// Clusters only [a] has, and only [b] has.
  final int aOnlyMemory;
  final int bOnlyMemory;
  final int aOnlySkills;
  final int bOnlySkills;

  int onlyMemory(String backendId) =>
      backendId == a ? aOnlyMemory : bOnlyMemory;

  int onlySkills(String backendId) =>
      backendId == a ? aOnlySkills : bOnlySkills;

  @override
  String toString() => 'AgentLink($a ↔ $b)';
}

/// The whole fleet, projected from one read of each bridge.
@immutable
class AgentGraph {
  const AgentGraph({required this.nodes, required this.links, this.unreachable = const {}});

  /// One node per known backend id. Order is stable: the order the ids were
  /// first seen in the inputs, which is the order the caller read them.
  final List<AgentNode> nodes;

  /// One edge per pair of nodes. Empty with fewer than two nodes.
  final List<AgentLink> links;

  /// Servers that were asked and could not answer, in the bridges' own
  /// vocabulary. Shown, never swallowed.
  final Map<String, String> unreachable;

  AgentNode? node(String backendId) {
    for (final n in nodes) {
      if (n.backendId == backendId) return n;
    }
    return null;
  }

  AgentLink? linkBetween(String a, String b) {
    for (final link in links) {
      if ((link.a == a && link.b == b) || (link.a == b && link.b == a)) {
        return link;
      }
    }
    return null;
  }

  bool get isEmpty => nodes.isEmpty;

  @override
  String toString() =>
      'AgentGraph(${nodes.length} nodes, ${links.length} links)';
}

/// Projects one read of both bridges into a fleet graph.
///
/// [savedLabels] is every saved server's display label by backend id — the
/// fleet's membership. [currentBackendId]/[currentBackendLabel] name the
/// workspace the graph was opened from, which is always a node even when it
/// was never saved (the bench, the tests). [liveBackends] is who answered,
/// [unreachable] who was asked and did not.
///
/// Nodes are keyed by backend id rather than by saved connection: the two
/// bridges aggregate by `AgentBackend.id`, so a graph keyed finer than its
/// data would assert per-server counts it cannot back. One Hermes and one
/// OpenClaw is the fleet this client actually holds today.
AgentGraph buildAgentGraph({
  required Map<String, String> savedLabels,
  required String currentBackendId,
  required String currentBackendLabel,
  Map<String, String> backendLabels = const {},
  required List<MemoryCluster> memory,
  required List<SkillCluster> skills,
  required Set<String> liveBackends,
  required Map<String, String> unreachable,
}) {
  // Anyone who answered or was asked is a node, whether or not it was saved
  // or is the current backend — an open tab the bridges asked is part of the
  // fleet even before it has a saved record. Saved-but-unasked servers join
  // from [savedLabels] as offline nodes.
  final ids = <String>{
    ...savedLabels.keys,
    currentBackendId,
    ...liveBackends,
    ...unreachable.keys,
  };

  final memoryCount = <String, int>{};
  for (final cluster in memory) {
    for (final entry in cluster.entries) {
      final id = entry.origin.backendId;
      memoryCount[id] = (memoryCount[id] ?? 0) + 1;
    }
  }

  final skillCount = <String, int>{};
  for (final cluster in skills) {
    for (final entry in cluster.entries) {
      skillCount[entry.backendId] = (skillCount[entry.backendId] ?? 0) + 1;
    }
  }

  final uniqueMemory = <String, int>{};
  final missingMemoryCount = <String, int>{};
  for (final cluster in memory) {
    if (cluster.backends.length == 1) {
      final id = cluster.backends.single;
      uniqueMemory[id] = (uniqueMemory[id] ?? 0) + 1;
    }
    for (final id in ids) {
      if (cluster.backends.isNotEmpty && !cluster.backends.contains(id)) {
        missingMemoryCount[id] = (missingMemoryCount[id] ?? 0) + 1;
      }
    }
  }

  final uniqueSkills = <String, int>{};
  final missingSkillsCount = <String, int>{};
  for (final cluster in skills) {
    if (cluster.backends.length == 1) {
      final id = cluster.backends.single;
      uniqueSkills[id] = (uniqueSkills[id] ?? 0) + 1;
    }
    for (final id in ids) {
      if (cluster.backends.isNotEmpty && !cluster.backends.contains(id)) {
        missingSkillsCount[id] = (missingSkillsCount[id] ?? 0) + 1;
      }
    }
  }

  final nodes = [
    for (final id in ids)
      AgentNode(
        backendId: id,
        label: savedLabels[id] ??
            backendLabels[id] ??
            (id == currentBackendId ? currentBackendLabel : id),
        // A backend that answered *anything* is live: the two bridges read
        // independently, so one failing must not grey out a node whose other
        // half answered. The failed half still shows in [AgentGraph.unreachable].
        presence: !liveBackends.contains(id) && unreachable.containsKey(id)
            ? AgentPresence.unreachable
            : (id == currentBackendId || liveBackends.contains(id))
            ? AgentPresence.live
            : AgentPresence.saved,
        memoryEntryCount: memoryCount[id] ?? 0,
        skillCount: skillCount[id] ?? 0,
        uniqueMemory: uniqueMemory[id] ?? 0,
        uniqueSkills: uniqueSkills[id] ?? 0,
        missingMemoryCount: missingMemoryCount[id] ?? 0,
        missingSkillsCount: missingSkillsCount[id] ?? 0,
        memory: [
          for (final cluster in memory)
            if (cluster.backends.contains(id)) cluster,
        ],
        skills: [
          for (final cluster in skills)
            if (cluster.backends.contains(id)) cluster,
        ],
        missingMemory: [
          for (final cluster in memory)
            if (cluster.backends.isNotEmpty &&
                !cluster.backends.contains(id))
              cluster,
        ],
        missingSkills: [
          for (final cluster in skills)
            if (cluster.backends.isNotEmpty &&
                !cluster.backends.contains(id))
              cluster,
        ],
      ),
  ];

  final sortedIds = ids.toList()..sort();
  final links = <AgentLink>[];
  for (var i = 0; i < sortedIds.length; i++) {
    for (var j = i + 1; j < sortedIds.length; j++) {
      final a = sortedIds[i];
      final b = sortedIds[j];
      var sharedMemory = 0;
      var sharedSkills = 0;
      var aOnlyMemory = 0;
      var bOnlyMemory = 0;
      var aOnlySkills = 0;
      var bOnlySkills = 0;
      for (final cluster in memory) {
        final backends = cluster.backends;
        if (backends.contains(a) && backends.contains(b)) {
          sharedMemory++;
        } else if (backends.contains(a)) {
          aOnlyMemory++;
        } else if (backends.contains(b)) {
          bOnlyMemory++;
        }
      }
      for (final cluster in skills) {
        final backends = cluster.backends;
        if (backends.contains(a) && backends.contains(b)) {
          sharedSkills++;
        } else if (backends.contains(a)) {
          aOnlySkills++;
        } else if (backends.contains(b)) {
          bOnlySkills++;
        }
      }
      links.add(
        AgentLink(
          a: a,
          b: b,
          sharedMemory: sharedMemory,
          sharedSkills: sharedSkills,
          aOnlyMemory: aOnlyMemory,
          bOnlyMemory: bOnlyMemory,
          aOnlySkills: aOnlySkills,
          bOnlySkills: bOnlySkills,
        ),
      );
    }
  }

  return AgentGraph(
    nodes: nodes,
    links: links,
    unreachable: Map.unmodifiable(unreachable),
  );
}
