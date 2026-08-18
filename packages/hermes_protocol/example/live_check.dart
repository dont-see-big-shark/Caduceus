/// Drives a real Hermes control plane with this client.
///
/// The unit tests use a fake transport, which proves the correlation and
/// reconnect logic but not that the wire format is right. This connects to an
/// actual gateway.
///
///   HERMES_TOKEN=<session token> dart run example/live_check.dart [port]
///
/// Start one first:
///   HERMES_DASHBOARD_SESSION_TOKEN=<token> hermes serve --isolated --port 9219
library;

import 'dart:async';
import 'dart:io';

import 'package:hermes_protocol/hermes_protocol.dart';

Future<void> main(List<String> args) async {
  final token = Platform.environment['HERMES_TOKEN'];
  if (token == null || token.isEmpty) {
    stderr.writeln('set HERMES_TOKEN to the gateway session token');
    exit(2);
  }

  // Accept either a full URL (reverse proxy, subpath mount) or a bare port.
  final target = args.isEmpty ? '9219' : args.first;
  final endpoint = int.tryParse(target) != null
      ? HermesEndpoint.tunnelled(token: token, port: int.parse(target))
      : HermesEndpoint.parse(target, credential: token);
  print('connecting to $endpoint');

  final gateway = HermesGateway(endpoint);
  final pushed = <String>[];
  gateway.events.listen((e) => pushed.add(e.type));
  gateway.connectionState.listen((s) => print('  state: $s'));

  try {
    await gateway.connect();
  } on TransportUpgradeException catch (e) {
    print('\nupgrade refused: $e');
    print('diagnosing rather than showing a bare 403...\n');
    final diagnosis = await GatewayDiagnostics().diagnose(endpoint);
    print(diagnosis);
    await gateway.dispose();
    exit(1);
  }

  // Server pushes gateway.ready unprompted; give it a moment to land.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  print('\nserver-pushed before any request: $pushed');

  print('\ncalling control-plane methods:');
  for (final method in ['session.list', 'agents.list', 'commands.catalog']) {
    try {
      final result = await gateway.call(method);
      print('  $method -> ${'$result'.length} chars');
    } on GatewayRpcException catch (e) {
      print('  $method -> ERROR ${e.message}');
    }
  }

  // Unknown methods must fail cleanly without disturbing the connection.
  try {
    await gateway.call('definitely.not.a.method');
    print('\n  unexpected: unknown method succeeded');
  } on GatewayRpcException catch (e) {
    print('\n  unknown method rejected cleanly: isUnknownMethod=${e.isUnknownMethod}');
  }

  final stillWorks = await gateway.call('session.list');
  print('  connection healthy after error: ${stillWorks != null}');

  await gateway.dispose();
  print('\nOK');
}
