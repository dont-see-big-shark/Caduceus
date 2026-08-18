/// Read-only probe of Hermes' skills surface, for the skills bridge.
///
/// Not a unit test. Asks the live gateway what `skills.manage` serves (list,
/// search, install) and what the learning store reports, so SKILLS_BRIDGE.md
/// is grounded in the real contract rather than a guess.
///
/// Deliberately non-destructive: the install probe passes a *nonexistent*
/// query, so a real install cannot resolve and the response tells us the call
/// is accepted without installing anything.
///
///   HERMES_URL=`url` HERMES_TOKEN=`token` \
///     dart run tool/probe_hermes_skills.dart
library;

import 'dart:io';

import 'package:hermes_protocol/hermes_protocol.dart';

Future<void> main() async {
  final env = Platform.environment;
  final endpoint = HermesEndpoint.parse(
    env['HERMES_URL']!,
    credential: env['HERMES_TOKEN']!,
  );
  final gateway = HermesGateway(endpoint);
  await gateway.connect();

  Future<void> call(
    String label,
    String method,
    Map<String, dynamic> params,
  ) async {
    try {
      final result = await gateway.call(method, params);
      final text = '$result';
      stdout.writeln(
        '$label -> OK (${text.length} chars): '
        '${text.length > 160 ? text.substring(0, 160) : text}',
      );
    } on GatewayRpcException catch (e) {
      final data = e.data == null ? '' : ' data=${e.data}';
      stdout.writeln('$label -> ${e.code} "${e.message}"$data');
    }
  }

  await call('skills.manage list', 'skills.manage', const {'action': 'list'});
  await call(
    'skills.manage search',
    'skills.manage',
    const {'action': 'search', 'query': 'browser automation'},
  );
  // A query that cannot resolve: proves the install call is accepted without
  // installing anything.
  await call(
    'skills.manage install (nonexistent)',
    'skills.manage',
    const {'action': 'install', 'query': 'caduceus-no-such-skill'},
  );
  await call('learning.add', 'learning.add', const {});

  final journey = await gateway.learningJourney();
  var skills = 0;
  for (final bucket in journey.buckets) {
    for (final node in bucket.nodes) {
      if (node.isSkill) skills++;
    }
  }
  stdout.writeln('learning.frames: $skills skill nodes');

  await gateway.dispose();
}
