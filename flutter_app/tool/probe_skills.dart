/// Read-only probe of the OpenClaw skills surface, for the skills bridge.
///
/// Not a unit test. Asks the live gateway what `skills.*` serves and what
/// `agents.files.*` will and will not reach, so SKILLS_BRIDGE.md is grounded
/// in the real contract rather than a guess. Sends no writes.
///
///   CLAW_URL=`url` CLAW_TOKEN=`token` dart run tool/probe_skills.dart
library;

import 'dart:convert';
import 'dart:io';

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
  await gateway.connect();
  stdout.writeln('connected');

  final status = await gateway.call('skills.status', const {});
  stdout.writeln('== skills.status ==');
  for (final skill in (status as Map)['skills'] as List) {
    final s = skill as Map;
    stdout.writeln(
      '  ${s['name']} eligible=${s['eligible']} source=${s['source']} '
      'file=${s['filePath']}',
    );
  }

  for (final slug in const ['trim-cli', 'tavily', 'github', 'agent-browser']) {
    try {
      final raw = await gateway.call('skills.detail', {'slug': slug}) as Map;
      final skill = raw['skill'] as Map? ?? const {};
      final desc = skill['description'] as String? ?? '';
      stdout.writeln(
        'skills.detail $slug -> displayName=${skill['displayName']} '
        'description=${desc.length} chars',
      );
    } on ClawRpcException catch (e) {
      final msg = e.message.replaceAll('\n', ' ');
      final clipped = msg.length > 90 ? '${msg.substring(0, 90)}…' : msg;
      stdout.writeln('skills.detail $slug -> ${e.code} $clipped');
    }
  }

  for (final method in const ['skills.get', 'skills.list', 'skills.read']) {
    try {
      await gateway.call(method, const {});
      stdout.writeln('$method -> ACCEPTED (unexpected at chat scope)');
    } on ClawRpcException catch (e) {
      stdout.writeln('$method -> ${e.code}');
    }
  }

  try {
    final raw = await gateway.call('agents.files.list', {'agentId': 'main'});
    stdout.writeln('== agents.files.list ==');
    for (final f in ((raw as Map)['files'] as List).take(20)) {
      final m = f as Map;
      stdout.writeln('  ${m['name']} size=${m['size']}');
    }
  } on ClawRpcException catch (e) {
    stdout.writeln('agents.files.list -> ${e.code} ${e.message}');
  }

  try {
    await gateway.call('agents.files.get', {
      'agentId': 'main',
      'name': 'skills/tavily/SKILL.md',
    });
    stdout.writeln('agents.files.get skills/... -> ACCEPTED (unexpected)');
  } on ClawRpcException catch (e) {
    stdout.writeln('agents.files.get skills/... -> ${e.code} ${e.message}');
  }

  await gateway.dispose();
}
