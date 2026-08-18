/// Does a resumed session still work after the server restarts?
///
/// Reconnecting the socket is not enough: the gateway only tracks sessions live
/// in its own process, so a session resumed against the old process is unknown
/// to the new one. This measures the difference between reconnecting and
/// re-resuming.
///
///   HERMES_TOKEN=... dart run example/session_survival_probe.dart <url>
library;

import 'dart:async';
import 'dart:io';

import 'package:hermes_protocol/hermes_protocol.dart';

Future<void> main(List<String> args) async {
  final token = Platform.environment['HERMES_TOKEN'];
  if (token == null || args.isEmpty) exit(2);

  final gateway = HermesGateway(
    HermesEndpoint.parse(args.first, credential: token),
    baseBackoff: const Duration(milliseconds: 300),
    maxReconnectAttempts: 30,
  );

  await gateway.connect();
  // Must be a *persisted* session. A freshly created one with no messages was
  // never written to the database, so after a restart there is nothing to
  // resume — that tests the wrong thing.
  final listed = await gateway.sessions(limit: 5);
  if (listed.isEmpty) {
    stdout.writeln('no persisted sessions on this gateway; cannot test');
    exit(2);
  }
  final sessionId = listed.first.id;
  stdout.writeln('using persisted session: $sessionId '
      '(${listed.first.messageCount} messages)');
  await gateway.sessionResume(sessionId);
  stdout.writeln('resumed against the current process');

  await Process.run('pkill', ['-f', 'hermes.*serve']);
  stdout.writeln('gateway killed');
  await Future<void>.delayed(const Duration(seconds: 3));

  final home = Platform.environment['HOME']!;
  await Process.start(
    '$home/.local/bin/hermes',
    ['serve', '--isolated', '--port', '9219', '--skip-build'],
    environment: {
      ...Platform.environment,
      'HERMES_PROFILE': 'caduceusspike',
      'HERMES_DASHBOARD_SESSION_TOKEN': token,
    },
    mode: ProcessStartMode.detached,
  );

  final back = Completer<void>();
  final sub = gateway.connectionState.listen((s) {
    if (s.isConnected && !back.isCompleted) back.complete();
  });
  await back.future.timeout(const Duration(seconds: 120));
  await sub.cancel();
  stdout.writeln('socket reconnected');

  // Without re-resuming: is the old session still addressable?
  stdout.writeln('\nA. use the session WITHOUT re-resuming:');
  var worksWithout = false;
  try {
    // Canary must (a) require a live session and (b) be harmless.
    // session.history / usage / context_breakdown all answer 4001 even on a
    // healthy connection, so they cannot distinguish "dead" from "broken".
    // session.title routes through _sess and is idempotent when re-set to the
    // value it already has.
    await gateway.sessionTitle(sessionId, listed.first.title);
    worksWithout = true;
    stdout.writeln('   works');
  } on GatewayRpcException catch (e) {
    stdout.writeln('   fails: ${e.message} (${e.code})');
  }

  stdout.writeln('\nB. re-resume, then use it:');
  var worksAfter = false;
  try {
    await gateway.sessionResume(sessionId);
    await gateway.sessionTitle(sessionId, listed.first.title);
    worksAfter = true;
    stdout.writeln('   works');
  } on GatewayRpcException catch (e) {
    stdout.writeln('   fails: ${e.message} (${e.code})');
  }

  stdout.writeln('\nreconnect alone sufficient: $worksWithout');
  stdout.writeln('re-resume needed          : ${!worksWithout && worksAfter}');
  await gateway.dispose();
}
