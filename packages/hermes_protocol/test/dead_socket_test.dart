/// A socket that stops answering must not wedge the client.
///
/// The failure this pins down was reported as "sending a message does nothing
/// and then times out": an idle control-plane socket had been dropped by the
/// proxy in front of the server, `send` still succeeded into the dead half of
/// it, and no reply ever came. The client went on reporting `connected`, so
/// every later prompt failed exactly the same way and only a restart helped.
library;

import 'dart:async';
import 'dart:convert';

import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:test/test.dart';

class _Silent implements GatewayTransport {
  final _in = StreamController<String>();
  final sent = <Map<String, dynamic>>[];
  var closed = false;

  @override
  Stream<String> get inbound => _in.stream;

  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, dynamic>);

  @override
  Future<void> close() async {
    closed = true;
    if (!_in.isClosed) await _in.close();
  }
}

void main() {
  test('an RPC timeout tears the socket down and reconnects', () async {
    final sockets = <_Silent>[];
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async {
        final s = _Silent();
        sockets.add(s);
        return s;
      },
      callTimeout: const Duration(milliseconds: 60),
      baseBackoff: const Duration(milliseconds: 10),
      maxBackoff: const Duration(milliseconds: 10),
    );

    final states = <GatewayStatus>[];
    gateway.connectionState.listen((s) => states.add(s.status));
    await gateway.connect();

    await expectLater(
      gateway.call('prompt.submit', {'session_id': 'a', 'text': 'hi'}),
      throwsA(isA<GatewayRpcException>()),
    );

    // The dead socket is gone, not merely ignored — after the liveness probe
    // it triggers also goes unanswered.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(sockets.first.closed, isTrue,
        reason: 'the unresponsive socket must be discarded');
    expect(states, contains(GatewayStatus.reconnecting));
    expect(sockets.length, greaterThan(1),
        reason: 'a replacement connection must be attempted');

    // And the replacement is usable: a call goes out on the new socket.
    final pending = gateway.call('session.list');
    await Future<void>.delayed(Duration.zero);
    final live = sockets.last;
    expect(live.sent, isNotEmpty);
    live._in.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': live.sent.last['id'],
      'result': {'sessions': []},
    }));
    expect(await pending, isA<Map<String, dynamic>>());

    await gateway.dispose();
  });

  test('a hung method on a live socket does not kill the connection', () async {
    // usage.bars on 0.19.x never answers while the socket stays healthy.
    // Recycling on that would drop every other session's stream with it.
    final sockets = <_Silent>[];
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async {
        final s = _Silent();
        sockets.add(s);
        return s;
      },
      callTimeout: const Duration(milliseconds: 120),
      baseBackoff: const Duration(milliseconds: 10),
      maxBackoff: const Duration(milliseconds: 10),
    );
    await gateway.connect();

    // Matcher attached immediately: the call fails during the loop below, and
    // an error future with no listener yet is an unhandled async error.
    final hung = expectLater(
        gateway.call('usage.bars'), throwsA(isA<GatewayRpcException>()));

    // Traffic keeps arriving for something else while that call hangs.
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      sockets.first._in.add(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': 'message.delta', 'session_id': 's', 'payload': {}},
      }));
    }

    await hung;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(sockets.first.closed, isFalse,
        reason: 'the socket was demonstrably alive');
    expect(sockets, hasLength(1), reason: 'no reconnect should be attempted');

    await gateway.dispose();
  });

  test('an unknown-method error counts as proof of life', () async {
    // The probe is a method the server does not implement, so the answer is
    // always an error. Treating that as a failed probe would tear down every
    // healthy connection the first time a call ran long.
    final sockets = <_Silent>[];
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async {
        final s = _Silent();
        sockets.add(s);
        return s;
      },
      callTimeout: const Duration(seconds: 1),
      baseBackoff: const Duration(milliseconds: 10),
      maxBackoff: const Duration(milliseconds: 10),
    );
    await gateway.connect();

    final hung = expectLater(
        gateway.call('usage.bars'), throwsA(isA<GatewayRpcException>()));

    // Answer as soon as the probe appears rather than on a fixed delay: the
    // probe's own budget is a fraction of the call timeout, and racing it
    // makes the test flaky rather than wrong.
    Map<String, dynamic>? probe;
    for (var i = 0; i < 200 && probe == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      probe = sockets.first.sent
          .where((f) => f['method'] == 'caduceus.ping')
          .firstOrNull;
    }
    expect(probe, isNotNull, reason: 'a liveness probe must be sent');
    sockets.first._in.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': probe!['id'],
      'error': {'code': -32601, 'message': 'unknown method: caduceus.ping'},
    }));

    await hung;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(sockets.first.closed, isFalse,
        reason: 'the server answered — the socket is alive');
    expect(sockets, hasLength(1));

    await gateway.dispose();
  });

  test('the real transport enables WebSocket keepalive pings', () {
    // The default has to be on: a client that cannot notice a dead peer is
    // exactly the bug above.
    expect(WebSocketTransport.defaultPingInterval.inSeconds, inInclusiveRange(5, 45));
  });
}
