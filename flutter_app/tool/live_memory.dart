/// Reads memory from the live gateway through the real adapter.
///
/// Not a unit test: this is the only thing that proves the adapter's calls are
/// accepted by a real server rather than by a fake that agrees with them.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/claw_backend.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';

Future<void> main() async {
  final env = Platform.environment;
  final seedFile = File('${env['HOME']}/.caduceus-claw-seed');
  final identity = await ClawDeviceIdentity.fromSeed(
    base64.decode(seedFile.readAsStringSync().trim()),
  );
  final gateway = ClawGateway(
    ClawEndpoint(url: Uri.parse(env['CLAW_URL']!), token: env['CLAW_TOKEN']!),
    identity: identity,
    scopes: ClawGateway.chatScopes,
  );
  final backend = ClawBackend(gateway);
  await backend.connect();
  stdout.writeln('state: ${backend.connectionState.status}');
  stdout.writeln('memoryRead: ${backend.supports(Capability.memoryRead)}');
  stdout.writeln('memoryWrite: ${backend.supports(Capability.memoryWrite)}');

  final entries = await backend.memory();
  stdout.writeln('\n${entries.length} entr(ies):');
  for (final e in entries) {
    final preview = e.text.replaceAll('\n', ' ');
    stdout.writeln('  [${e.kind.name}] ${e.label}');
    stdout.writeln('      from ${e.origin}  updated=${e.updatedAt}');
    stdout.writeln('      ${preview.length > 100 ? '${preview.substring(0, 100)}…' : preview}');
  }
  await backend.dispose();
}
