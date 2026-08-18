/// Verifies reconnect against a real gateway that actually goes away.
///
/// The unit tests drive reconnect through a fake transport, which proves the
/// backoff state machine but not that a real dropped socket is detected, or
/// that the client recovers when the server returns. This kills and restarts a
/// throwaway local gateway.
///
///   HERMES_TOKEN=... dart run example/reconnect_probe.dart <url>
library;

import 'dart:async';
import 'dart:io';

import 'package:hermes_protocol/hermes_protocol.dart';

Future<void> main(List<String> args) async {
  final token = Platform.environment['HERMES_TOKEN'];
  if (token == null || args.isEmpty) {
    stderr.writeln('usage: HERMES_TOKEN=... dart run example/reconnect_probe.dart <url>');
    exit(2);
  }

  final gateway = HermesGateway(
    HermesEndpoint.parse(args.first, credential: token),
    baseBackoff: const Duration(milliseconds: 300),
    maxReconnectAttempts: 20,
  );

  final transitions = <String>[];
  gateway.connectionState.listen((s) {
    final label = s.attempt > 0 ? '${s.status.name}(${s.attempt})' : s.status.name;
    if (transitions.isEmpty || transitions.last != label) {
      transitions.add(label);
      stdout.writeln('  state: $label');
    }
  });

  stdout.writeln('1. connect');
  await gateway.connect();
  final before = await gateway.sessionList();
  stdout.writeln('   session.list ok (${before.keys})');

  stdout.writeln('\n2. killing the gateway');
  await Process.run('pkill', ['-f', 'hermes.*serve']);
  await Future<void>.delayed(const Duration(seconds: 4));

  stdout.writeln('   in-flight call while down:');
  try {
    await gateway.sessionList().timeout(const Duration(seconds: 6));
    stdout.writeln('   UNEXPECTED: call succeeded with the server down');
  } catch (e) {
    stdout.writeln('   failed cleanly: ${e.runtimeType}');
  }

  stdout.writeln('\n3. restarting the gateway');
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

  stdout.writeln('   waiting for the client to recover…');
  final recovered = Completer<void>();
  final sub = gateway.connectionState.listen((s) {
    if (s.isConnected && !recovered.isCompleted) recovered.complete();
  });
  // Already connected again before the listener attached?
  if (gateway.state.isConnected && !recovered.isCompleted) recovered.complete();

  var ok = false;
  try {
    await recovered.future.timeout(const Duration(seconds: 120));
    ok = true;
  } on TimeoutException {
    stdout.writeln('   did NOT recover within 120s');
  }
  await sub.cancel();

  if (ok) {
    stdout.writeln('   reconnected — verifying the socket actually works:');
    try {
      final after = await gateway.sessionList();
      stdout.writeln('   session.list ok after recovery (${after.keys})');
    } on GatewayRpcException catch (e) {
      stdout.writeln('   call after recovery FAILED: ${e.message}');
      ok = false;
    }
  }

  stdout.writeln('\ntransitions: ${transitions.join(" -> ")}');
  stdout.writeln(ok ? 'RECONNECT OK' : 'RECONNECT FAILED');

  await gateway.dispose();
  exit(ok ? 0 : 1);
}
