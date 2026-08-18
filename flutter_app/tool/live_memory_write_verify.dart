/// Live verification of the OpenClaw memory *write* path — phases 3 and 5 of
/// `MEMORY_BRIDGE.md`, exercised against a real gateway.
///
/// Everything written here is reversible and actually reversed:
///   * one memory entry is added to `MEMORY.md`, read back, checked for the
///     R1 splice invariant, then removed again;
///   * `SOUL.md` is pushed as its own content plus a marker line, the
///     overwrite hook's backup is checked, then the original is restored.
///   * R3 is exercised by moving the file underneath the adapter between a
///     read and a write and checking the write refuses (and emits no RPC).
///
/// Needs a device paired with `operator.admin`:
///
///   CLAW_URL=`url` CLAW_TOKEN=`token` \
///     dart run tool/live_memory_write_verify.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/claw_backend.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';

class _RecordingTransport implements ClawTransport {
  _RecordingTransport(this._inner);

  final ClawTransport _inner;
  final List<String> sent = [];

  @override
  Stream<String> get inbound => _inner.inbound;

  @override
  void send(String data) {
    sent.add(data);
    _inner.send(data);
  }

  @override
  Future<void> close() => _inner.close();
}

Future<void> main() async {
  final env = Platform.environment;
  final seedFile = File('${env['HOME']}/.caduceus-claw-seed');
  final identity = await ClawDeviceIdentity.fromSeed(
    base64.decode(seedFile.readAsStringSync().trim()),
  );
  final endpoint = ClawEndpoint(
    url: Uri.parse(env['CLAW_URL']!),
    token: env['CLAW_TOKEN']!,
  );

  late _RecordingTransport recorded;
  final gateway = ClawGateway(
    endpoint,
    identity: identity,
    // The gateway grants RPC scopes per-request-session, not from the device
    // approval table alone: hello reports the approved set, but a call is
    // authorized against what this connection asked for. Ask for admin or the
    // write is refused even though the device holds it.
    scopes: [...ClawGateway.chatScopes, 'operator.admin'],
    connector: (e) async {
      recorded = _RecordingTransport(
        await WebSocketClawTransport.connect(e.url, headers: e.headers),
      );
      return recorded;
    },
  );
  final backend = ClawBackend(gateway);

  Future<String> defaultAgentId() async {
    final raw = await gateway.call('agents.list', const {});
    final rows = (raw['agents'] as List?) ?? const [];
    for (final row in rows) {
      if (row is Map && '${row['id'] ?? ''}'.isNotEmpty) {
        return '${row['id']}';
      }
    }
    return 'main';
  }

  var pass = true;
  void check(bool ok, String label, [String? detail]) {
    stdout.writeln('  ${ok ? 'PASS' : 'FAIL'}  $label${detail == null ? '' : ' — $detail'}');
    if (!ok) pass = false;
  }

  try {
    await backend.connect();
    stdout.writeln('state: ${backend.connectionState.status}');
    stdout.writeln('memoryWrite: ${backend.supports(Capability.memoryWrite)}');
    check(
      backend.supports(Capability.memoryWrite),
      'device holds operator.admin',
    );
    final agentId = await defaultAgentId();
    stdout.writeln('agentId: $agentId');

    Future<Map<String, dynamic>> filesGet(String name) async {
      final r = await gateway.call(
        'agents.files.get',
        {'agentId': agentId, 'name': name},
      );
      final file = r['file'];
      return file is Map
          ? {for (final e in file.entries) '${e.key}': e.value}
          : const <String, dynamic>{};
    }

    Future<String> readFile(String name) async {
      final f = await filesGet(name);
      return f['missing'] == true ? '' : '${f['content'] ?? ''}';
    }

    // Seed the adapter's staleness stamps exactly as the UI does: read first.
    final before = await backend.memory();
    final originalMemory = await readFile('MEMORY.md');
    final originalSoul = await readFile('SOUL.md');
    stdout.writeln(
      'baseline: ${before.length} memory entries, MEMORY.md ${originalMemory.length} chars, SOUL.md ${originalSoul.length} chars',
    );

    stdout.writeln('\n== phase 3: add a memory, verify splice, remove it ==');
    final probe = MemoryEntry(
      id: 'openclaw:MEMORY.md#caduceus-live-probe',
      kind: MemoryKind.fact,
      title: 'caduceus live probe',
      text: 'Written by tool/live_memory_write_verify.dart; must be removed by the same run.',
      origin: const MemoryOrigin(
        backendId: 'openclaw',
        nativeId: 'MEMORY.md#caduceus-live-probe',
      ),
    );

    recorded.sent.clear();
    final addResult = await backend.applyMemory([MemoryChange(MemoryOp.add, probe)]);
    final addOutcome = addResult.outcomes.single;
    check(addOutcome.applied, 'add applied', addOutcome.detail);
    check(
      recorded.sent.every((f) => f.contains('"method":"agents.files.')),
      'R5: add cycle sent only agents.files.*',
      'frames: ${recorded.sent.length}',
    );

    final afterAdd = await readFile('MEMORY.md');
    final block = MemoryBlock.parse(afterAdd);
    check(
      block.hadMarkers && block.body.contains('caduceus live probe'),
      'probe entry is inside the caduceus block',
    );
    // Same R1 semantics as the repo's own memory_block_test.dart: remove the
    // block from both sides and compare (trimmed), so the block's own format
    // newlines do not count as touching user text.
    check(
      MemoryBlock.clear(afterAdd).trim() == MemoryBlock.clear(originalMemory).trim(),
      'R1: text outside the block survived the add byte for byte',
    );

    recorded.sent.clear();
    final removeResult =
        await backend.applyMemory([MemoryChange(MemoryOp.remove, probe)]);
    final removeOutcome = removeResult.outcomes.single;
    check(removeOutcome.applied, 'remove applied', removeOutcome.detail);
    check(
      recorded.sent.every((f) => f.contains('"method":"agents.files.')),
      'R5: remove cycle sent only agents.files.*',
    );
    final afterRemove = await readFile('MEMORY.md');
    // The empty markers remain — R2's design: a remove takes the entry out of
    // the block this app owns, it does not abandon the block. What must hold
    // is that outside the markers nothing moved and the probe is gone.
    check(
      MemoryBlock.clear(afterRemove).trim() == MemoryBlock.clear(originalMemory).trim(),
      'R1: text outside the block survived the remove byte for byte',
    );
    final afterRemoveBlock = MemoryBlock.parse(afterRemove);
    check(
      !afterRemove.contains('caduceus live probe'),
      'probe entry is gone after remove',
    );
    check(
      afterRemoveBlock.hadMarkers && afterRemoveBlock.body.trim().isEmpty,
      'empty managed block remains (R2: markers belong to the app)',
    );

    stdout.writeln('\n== phase 3: R3 staleness refuses a moved file ==');
    // Move the file underneath the adapter: write through the raw gateway so
    // the adapter's stamp is now stale, then ask the adapter to write.
    await gateway.call('agents.files.set', {
      'agentId': agentId,
      'name': 'MEMORY.md',
      'content': '$originalMemory\n\n<!-- moved by live probe -->\n',
    });
    recorded.sent.clear();
    final staleResult =
        await backend.applyMemory([MemoryChange(MemoryOp.add, probe)]);
    final staleOutcome = staleResult.outcomes.single;
    check(
      !staleOutcome.applied && staleOutcome.refusal == MemoryWriteRefusal.staleRead,
      'R3: write refused after the file moved',
      staleOutcome.detail,
    );
    check(
      recorded.sent.every((f) => !f.contains('"method":"agents.files.set"')),
      'R3: no agents.files.set emitted for the refused write',
    );
    // Restore the baseline so the probe leaves no trace.
    await gateway.call('agents.files.set', {
      'agentId': agentId,
      'name': 'MEMORY.md',
      'content': originalMemory,
    });
    check(
      await readFile('MEMORY.md') == originalMemory,
      'MEMORY.md restored to baseline',
    );

    stdout.writeln('\n== phase 5: persona push, backup, undo ==');
    String? backup;
    backend.onOverwrite = (backendId, name, previous) async {
      backup = previous;
      stdout.writeln('    overwrite hook: $backendId/$name backed up ${previous.length} chars');
    };

    final personaProbe = MemoryEntry(
      id: 'openclaw:SOUL.md',
      kind: MemoryKind.persona,
      title: 'SOUL.md',
      text: '$originalSoul\n\n<!-- caduceus live probe: this line must be undone -->\n',
      origin: const MemoryOrigin(backendId: 'openclaw', nativeId: 'SOUL.md'),
    );
    recorded.sent.clear();
    final pushResult = await backend.applyMemory([
      MemoryChange(MemoryOp.update, personaProbe),
    ]);
    final pushOutcome = pushResult.outcomes.single;
    check(pushOutcome.applied, 'persona push applied', pushOutcome.detail);
    check(
      backup == originalSoul,
      'backup recorded the pre-write SOUL.md',
    );
    check(
      recorded.sent.every((f) => f.contains('"method":"agents.files.')),
      'R5: persona push sent only agents.files.*',
    );

    final pushedSoul = await readFile('SOUL.md');
    check(
      pushedSoul == personaProbe.text,
      'SOUL.md holds the pushed content',
    );

    final undoEntry = MemoryEntry(
      id: 'openclaw:SOUL.md',
      kind: MemoryKind.persona,
      title: 'SOUL.md',
      text: originalSoul,
      origin: const MemoryOrigin(backendId: 'openclaw', nativeId: 'SOUL.md'),
    );
    final undoResult = await backend.applyMemory([
      MemoryChange(MemoryOp.update, undoEntry),
    ]);
    final undoOutcome = undoResult.outcomes.single;
    check(undoOutcome.applied, 'undo applied', undoOutcome.detail);
    check(
      await readFile('SOUL.md') == originalSoul,
      'SOUL.md restored byte-identically',
    );

    // Delete is refused outright, no round trip.
    recorded.sent.clear();
    final delResult = await backend.applyMemory([
      MemoryChange(MemoryOp.remove, undoEntry),
    ]);
    final delOutcome = delResult.outcomes.single;
    check(
      !delOutcome.applied &&
          delOutcome.refusal == MemoryWriteRefusal.unsupported,
      'persona delete refused',
      delOutcome.detail,
    );
    check(
      recorded.sent.isEmpty,
      'persona delete cost no round trip',
    );

    stdout.writeln('\n${pass ? 'ALL PASS' : 'SOME FAILED'}');
    exit(pass ? 0 : 1);
  } finally {
    await backend.dispose();
  }
}
