/// Live verification of the skills and memory bridge adapters, end to end,
/// plus the fleet projection (`AGENT_GRAPH.md`) and the shared-memory
/// detector/write path (`SHARED_MEMORY.md`) on top of the same reads.
///
/// Same approach as the other `tool/live_*.dart` helpers: env-driven, direct
/// adapter construction, real servers. Calls both adapters' `skillLibrary()`
/// and `memory()` on the live gateways and clusters them exactly the way
/// `Workspace.skillView` / `memoryView` do, so the cross-end comparison is
/// verified against reality rather than against a fake that agrees with us.
///
///   HERMES_URL=... HERMES_TOKEN=... CLAW_URL=... CLAW_TOKEN=... \
///     dart run tool/verify_bridge_live.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/claw_backend.dart';
import 'package:caduceus/backends/hermes_backend.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';

Future<void> main() async {
  final env = Platform.environment;
  final hermesUrl = env['HERMES_URL'];
  final hermesToken = env['HERMES_TOKEN'];
  final clawUrl = env['CLAW_URL'];
  final clawToken = env['CLAW_TOKEN'];
  if (hermesUrl == null ||
      hermesToken == null ||
      clawUrl == null ||
      clawToken == null) {
    stderr.writeln('set HERMES_URL HERMES_TOKEN CLAW_URL CLAW_TOKEN');
    exit(2);
  }

  final seedFile = File('${env['HOME']}/.caduceus-claw-seed');
  final identity = await ClawDeviceIdentity.fromSeed(
    base64.decode(seedFile.readAsStringSync().trim()),
  );
  final hermesBackend = HermesBackend(
    HermesGateway(HermesEndpoint.parse(hermesUrl, credential: hermesToken)),
  );
  final clawBackend = ClawBackend(
    ClawGateway(
      ClawEndpoint(url: Uri.parse(clawUrl), token: clawToken),
      identity: identity,
      scopes: ClawGateway.adminScopes,
    ),
  );
  await hermesBackend.connect();
  await clawBackend.connect();
  stdout.writeln('connected: hermes=${hermesBackend.connectionState.status} '
      'openclaw=${clawBackend.connectionState.status}');

  stdout.writeln('\n===== SKILL LIBRARIES, CLUSTERED =====');
  final hermesSkills = await hermesBackend.skillLibrary();
  final clawSkills = await clawBackend.skillLibrary();
  stdout.writeln('hermes: ${hermesSkills.length} skills, '
      'openclaw: ${clawSkills.length} skills');
  final skillClusters = clusterSkills([...hermesSkills, ...clawSkills]);
  final skillBackends = {'hermes', 'openclaw'};
  final divergent = [
    for (final c in skillClusters)
      if (c.missingFrom(skillBackends).isNotEmpty) c,
  ];
  stdout.writeln('clusters: ${skillClusters.length}  divergent: ${divergent.length}');
  for (final cluster in skillClusters.take(14)) {
    final missing = cluster.missingFrom(skillBackends);
    stdout.writeln(
      '  ${cluster.key.padRight(34)} '
      '${cluster.backends.join("+").padRight(18)} '
      '${missing.isEmpty ? "shared" : "not in ${missing.join(",")}"}'
      '${cluster.entries.any((e) => e.content != null) ? "  [content]" : ""}',
    );
  }

  stdout.writeln('\n===== MEMORY, CLUSTERED =====');
  final hermesMemory = await hermesBackend.memory();
  final clawMemory = await clawBackend.memory();
  stdout.writeln('hermes: ${hermesMemory.length} entries, '
      'openclaw: ${clawMemory.length} entries');
  final memoryClusters = clusterMemories([...hermesMemory, ...clawMemory]);
  for (final cluster in memoryClusters.take(12)) {
    final missing = cluster.missingFrom(skillBackends);
    stdout.writeln(
      '  [${cluster.best.kind.name.padRight(9)}] '
      '${cluster.best.label.padRight(30)} '
      '${cluster.backends.join("+").padRight(18)} '
      '${missing.isEmpty ? "shared" : "not in ${missing.join(",")}"}',
    );
  }

  stdout.writeln('\n===== FLEET GRAPH =====');
  final graph = buildAgentGraph(
    savedLabels: {'hermes': 'hermes', 'openclaw': 'openclaw'},
    currentBackendId: 'hermes',
    currentBackendLabel: 'Hermes',
    backendLabels: {'hermes': 'Hermes', 'openclaw': 'OpenClaw'},
    memory: memoryClusters,
    skills: skillClusters,
    liveBackends: skillBackends,
    unreachable: const {},
  );
  for (final node in graph.nodes) {
    stdout.writeln(
      '  ${node.label.padRight(16)} ${node.presence.name.padRight(12)} '
      '${node.memoryEntryCount} memories · ${node.skillCount} skills · '
      '${node.uniqueMemory} unique memories · ${node.uniqueSkills} unique '
      'skills · missing ${node.missingMemoryCount} / ${node.missingSkillsCount}'
      '${node.isLone ? "  [lone]" : ""}',
    );
  }
  for (final link in graph.links) {
    stdout.writeln(
      '  ${link.a} ↔ ${link.b}: shared ${link.sharedMemory} memories / '
      '${link.sharedSkills} skills; only ${link.a}: ${link.aOnlyMemory} / '
      '${link.aOnlySkills}; only ${link.b}: ${link.bOnlyMemory} / '
      '${link.bOnlySkills}',
    );
  }

  stdout.writeln('\n===== SHARED MEMORY DETECTOR + WRITE =====');
  final tag = 'caduceus-live-probe-${DateTime.now().millisecondsSinceEpoch}';
  final sharedFact = SharedFact(
    id: 'live-probe',
    kind: MemoryKind.fact,
    text: '$tag — temporary live probe, safe to delete.',
    updatedAt: DateTime.now(),
  );
  final before = detectFactStates(
    fact: sharedFact,
    clusters: memoryClusters,
    knownBackends: skillBackends,
    unreachable: const {},
    anchors: const {},
  );
  for (final entry in before.byBackend.entries) {
    stdout.writeln('  before: ${entry.key} → ${entry.value.status.name}');
  }

  stdout.writeln('  syncing to openclaw via applyMemory…');
  final write = await clawBackend.applyMemory([
    MemoryChange(
      MemoryOp.add,
      MemoryEntry(
        id: 'shared:live-probe',
        kind: MemoryKind.fact,
        text: sharedFact.text,
        origin: const MemoryOrigin(backendId: 'openclaw', nativeId: ''),
      ),
    ),
  ]);
  stdout.writeln(
    '  write: ${write.applied.length} applied, ${write.refused.length} refused'
    '${write.refused.isNotEmpty ? ' — ${write.refused.first.detail}' : ''}',
  );

  if (write.applied.isNotEmpty) {
    final clawAgain = await clawBackend.memory();
    final after = detectFactStates(
      fact: sharedFact,
      clusters: clusterMemories([...hermesMemory, ...clawAgain]),
      knownBackends: skillBackends,
      unreachable: const {},
      anchors: const {},
    );
    for (final entry in after.byBackend.entries) {
      stdout.writeln(
        '  after: ${entry.key} → ${entry.value.status.name}'
        '${entry.value.nativeId == null ? '' : ' @ ${entry.value.nativeId}'}',
      );
    }
    // Clean up the probe entry from OpenClaw's block.
    final native = after.byBackend['openclaw']?.nativeId ?? '';
    if (native.isNotEmpty) {
      final removal = await clawBackend.applyMemory([
        MemoryChange(
          MemoryOp.remove,
          MemoryEntry(
            id: 'shared:live-probe',
            kind: MemoryKind.fact,
            text: sharedFact.text,
            origin: MemoryOrigin(backendId: 'openclaw', nativeId: native),
          ),
        ),
      ]);
      stdout.writeln(
        '  cleanup: ${removal.applied.length} applied'
        '${removal.refused.isNotEmpty ? ' — ${removal.refused.first.detail}' : ''}',
      );
    }
  }

  await clawBackend.dispose();
}
