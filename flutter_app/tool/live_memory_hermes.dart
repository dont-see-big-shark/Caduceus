/// Hermes twin of `live_memory.dart` — reads and probes a real Hermes.
///
/// Not a unit test. This is the tool MEMORY_BRIDGE.md §10 asks for before
/// phase 4 writes anything back: it proves the `learning.*` mapping is
/// accepted by a real gateway rather than by a fake that agrees with it.
///
/// Everything here is deliberately non-destructive:
///   * `learning.frames` is read through the real adapter.
///   * `learning.add` is probed with structurally invalid params, so an
///     existing method answers a validation error and a missing one answers
///     "unknown method" — either way nothing is created.
///   * `learning.edit` is exercised as a no-op (same content, no change).
///   * `learning.delete` is exercised against an id that does not exist.
///
///   HERMES_URL=`url` HERMES_TOKEN=`token` \
///     dart run tool/live_memory_hermes.dart
library;

import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/hermes_backend.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

Future<void> main() async {
  final env = Platform.environment;
  final url = env['HERMES_URL'];
  final token = env['HERMES_TOKEN'];
  if (url == null || url.isEmpty || token == null || token.isEmpty) {
    stderr.writeln('set HERMES_URL and HERMES_TOKEN');
    exit(2);
  }

  final endpoint = HermesEndpoint.parse(url, credential: token);
  final gateway = HermesGateway(endpoint);
  final backend = HermesBackend(gateway);

  try {
    await backend.connect();
    stdout.writeln('state: ${backend.connectionState.status}');
    stdout.writeln('memoryRead: ${backend.supports(Capability.memoryRead)}');
    stdout.writeln('memoryWrite: ${backend.supports(Capability.memoryWrite)}');
    stdout.writeln('ops: ${backend.supportedMemoryOps}');

    final entries = await backend.memory();
    stdout.writeln('\n${entries.length} entr(ies):');
    for (final e in entries.take(8)) {
      final preview = e.text.replaceAll('\n', ' ');
      stdout.writeln('  [${e.kind.name}] ${e.title}');
      stdout.writeln('      from ${e.origin}  updated=${e.updatedAt}');
      stdout.writeln(
        '      ${preview.length > 90 ? '${preview.substring(0, 90)}…' : preview}',
      );
    }
    if (entries.length > 8) {
      stdout.writeln('  … and ${entries.length - 8} more');
    }

    stdout.writeln('\nprobing learning.add (must not create anything):');
    try {
      final result = await gateway.call('learning.add', const {
        // Structurally invalid on purpose: a real method must reject this.
      });
      stdout.writeln('  learning.add -> ACCEPTED (unexpected): $result');
    } on GatewayRpcException catch (e) {
      stdout.writeln(
        '  learning.add -> ${e.code} "${e.message}"'
        '${e.data == null ? '' : ' data=${e.data}'}',
      );
    }

    stdout.writeln('\nprobing learning.edit (no-op, same content):');
    MemoryEntry? node;
    for (final e in entries) {
      if (e.origin.nativeId.isNotEmpty) {
        node = e;
        break;
      }
    }
    if (node == null) {
      stdout.writeln('  no node to exercise — nothing written');
    } else {
      try {
        final result = await gateway.call('learning.edit', {
          // The server's address for the node, not the ledger id: the latter
          // carries a `hermes:` prefix this gateway does not understand.
          'id': node.origin.nativeId,
          'content': node.text,
        });
        stdout.writeln('  learning.edit ${node.origin.nativeId} -> ok: $result');
      } on GatewayRpcException catch (e) {
        stdout.writeln(
          '  learning.edit ${node.origin.nativeId} -> ${e.code} "${e.message}"'
          '${e.data == null ? '' : ' data=${e.data}'}',
        );
      }
    }

    stdout.writeln('\nprobing learning.delete (nonexistent id, must not delete):');
    try {
      final result = await gateway.call(
        'learning.delete',
        const {'id': 'caduceus-live-probe-no-such-node'},
      );
      stdout.writeln('  learning.delete -> ok: $result');
    } on GatewayRpcException catch (e) {
      stdout.writeln(
        '  learning.delete -> ${e.code} "${e.message}"'
        '${e.data == null ? '' : ' data=${e.data}'}',
      );
    }
  } finally {
    await backend.dispose();
  }
}
