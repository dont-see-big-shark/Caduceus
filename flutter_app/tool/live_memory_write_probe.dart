/// Live refusal-path check for the memory write rules on OpenClaw.
///
/// `MEMORY_BRIDGE.md` R5 asserts that a device without `operator.admin`
/// refuses a memory write *and emits no RPC*. That is pinned by unit tests
/// against a fake transport; this tool re-checks it against the real gateway:
/// it connects with the paired device, attempts one memory change, and shows
/// whether the write was refused with no method sent.
///
/// This is deliberately a refusal test, not a write: the paired device is
/// scoped read/write/approvals, so a real splice/persona verification needs
/// `operator.admin` and the human pairing gate that grants it.
///
///   CLAW_URL=`url` CLAW_TOKEN=`token` \
///     dart run tool/live_memory_write_probe.dart
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
    scopes: ClawGateway.chatScopes,
    connector: (e) async {
      recorded = _RecordingTransport(
        await WebSocketClawTransport.connect(e.url, headers: e.headers),
      );
      return recorded;
    },
  );
  final backend = ClawBackend(gateway);

  try {
    await backend.connect();
    stdout.writeln('state: ${backend.connectionState.status}');
    stdout.writeln('memoryWrite: ${backend.supports(Capability.memoryWrite)}');
    final sentBefore = recorded.sent.length;

    final result = await backend.applyMemory([
      MemoryChange(
        MemoryOp.add,
        const MemoryEntry(
          id: 'probe:live',
          kind: MemoryKind.fact,
          title: 'Live probe',
          text: 'must be refused without operator.admin',
          tags: {},
          origin: MemoryOrigin(backendId: 'openclaw', nativeId: 'probe:live'),
        ),
      ),
    ]);

    final outcome = result.outcomes.single;
    final sentAfter = recorded.sent.length;
    stdout.writeln(
      'applyMemory -> ${outcome.applied ? 'APPLIED' : 'refused'} '
      '(${outcome.refusal?.name})',
    );
    stdout.writeln('  detail: ${outcome.detail}');
    stdout.writeln(
      'rpc frames sent by this call: ${sentAfter - sentBefore} '
      '(expected 0)',
    );
    stdout.writeln(
      outcome.applied || sentAfter != sentBefore
          ? 'RESULT: FAIL — a refused write still reached the server'
          : 'RESULT: PASS — refused with no RPC emitted',
    );
  } finally {
    await backend.dispose();
  }
}
