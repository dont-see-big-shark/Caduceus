import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:test/test.dart';

/// Scriptable transport. Lets the reconnect and correlation logic — where the
/// real bugs live — be tested without a server, a network, or a device.
class FakeTransport implements GatewayTransport {
  FakeTransport();

  final _in = StreamController<String>();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  Stream<String> get inbound => _in.stream;

  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, dynamic>);

  @override
  Future<void> close() async {
    closed = true;
    if (!_in.isClosed) await _in.close();
  }

  void emit(Object frame) => _in.add(jsonEncode(frame));
  void emitRaw(String frame) => _in.add(frame);
  void fail(Object error) => _in.addError(error);
  Future<void> drop() async {
    if (!_in.isClosed) await _in.close();
  }

  Map<String, dynamic> get lastSent => sent.last;

  void replyTo(int index, Object? result) =>
      emit({'jsonrpc': '2.0', 'id': sent[index]['id'], 'result': result});

  void errorTo(int index, int code, String message) => emit({
    'jsonrpc': '2.0',
    'id': sent[index]['id'],
    'error': {'code': code, 'message': message},
  });
}

HermesEndpoint get _endpoint =>
    HermesEndpoint.tunnelled(token: 'test-token', port: 9219);

void main() {
  group('URL construction', () {
    test('loopback mode uses ?token=', () {
      final uri = _endpoint.gatewayWsUri;
      expect(uri.scheme, 'ws');
      expect(uri.path, '/api/ws');
      expect(uri.queryParameters['token'], 'test-token');
      expect(uri.queryParameters.containsKey('ticket'), isFalse);
    });

    test('gated mode uses ?ticket= — the server rejects token= outright', () {
      final gated = HermesEndpoint(
        host: 'box.example',
        port: 9119,
        credential: 'tk-123',
        authMode: GatewayAuthMode.gatedTicket,
      );
      expect(gated.gatewayWsUri.queryParameters['ticket'], 'tk-123');
      expect(gated.gatewayWsUri.queryParameters.containsKey('token'), isFalse);
      expect(gated.credentialIsSingleUse, isTrue);
    });

    test('toString never leaks the credential', () {
      expect(_endpoint.toString(), isNot(contains('test-token')));
    });
  });

  group('frame handling', () {
    test('server-pushed notification with no id reaches events', () async {
      final t = FakeTransport();
      final g = HermesGateway(_endpoint, connector: (_) async => t);
      await g.connect();

      final received = <GatewayEvent>[];
      g.events.listen(received.add);

      // gateway.ready arrives before the client has sent anything, wrapped in
      // the "event" envelope every server push uses.
      t.emit({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': 'gateway.ready',
          'session_id': 's-1',
          'payload': {'skin': 'default'},
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.type, 'gateway.ready');
      expect(received.single.sessionId, 's-1');
      await g.dispose();
    });

    test('responses correlate by id, out of order', () async {
      final t = FakeTransport();
      final g = HermesGateway(_endpoint, connector: (_) async => t);
      await g.connect();

      final a = g.call('session.list');
      final b = g.call('agents.list');
      expect(t.sent, hasLength(2));

      t.replyTo(1, {'processes': []}); // second request answered first
      t.replyTo(0, {'sessions': []});

      expect(await b, {'processes': []});
      expect(await a, {'sessions': []});
      await g.dispose();
    });

    test('error response fails only its own call', () async {
      final t = FakeTransport();
      final g = HermesGateway(_endpoint, connector: (_) async => t);
      await g.connect();

      final bad = g.call('nope');
      final good = g.call('session.list');
      t.errorTo(0, -32601, 'unknown method: nope');
      t.replyTo(1, {'sessions': []});

      await expectLater(
        bad,
        throwsA(
          isA<GatewayRpcException>()
              .having((e) => e.isUnknownMethod, 'isUnknownMethod', isTrue)
              .having((e) => e.method, 'method', 'nope'),
        ),
      );
      expect(await good, {'sessions': []});
      await g.dispose();
    });

    test('a malformed frame does not kill the session', () async {
      final t = FakeTransport();
      final g = HermesGateway(_endpoint, connector: (_) async => t);
      await g.connect();

      t.emitRaw('{not json');
      t.emitRaw('[]');
      await Future<void>.delayed(Duration.zero);

      final call = g.call('session.list');
      t.replyTo(0, {'sessions': []});
      expect(await call, {'sessions': []});
      expect(g.state.isConnected, isTrue);
      await g.dispose();
    });
  });

  group('lifecycle — the leaks that sank the prior attempt', () {
    test('completed calls leave nothing pending', () async {
      final t = FakeTransport();
      final g = HermesGateway(_endpoint, connector: (_) async => t);
      await g.connect();

      for (var i = 0; i < 5; i++) {
        final f = g.call('session.list');
        t.replyTo(i, {'n': i});
        await f;
      }
      // dispose() completes every straggler; if any had leaked, the pending
      // map would still hold it and this would hang rather than return.
      await g.dispose().timeout(const Duration(seconds: 2));
    });

    test('disconnect fails in-flight calls instead of hanging them', () async {
      final t = FakeTransport();
      final g = HermesGateway(_endpoint, connector: (_) async => t);
      await g.connect();

      final inflight = g.call('session.list');
      await t.drop();

      await expectLater(inflight, throwsA(isA<GatewayDisconnected>()));
      await g.dispose();
    });

    test('a socket error is handled, not thrown into the void', () async {
      final t = FakeTransport();
      final g = HermesGateway(_endpoint, connector: (_) async => t);
      await g.connect();

      final inflight = g.call('session.list');
      t.fail(const SocketFailure());

      await expectLater(inflight, throwsA(anything));
      expect(g.state.status, isNot(GatewayStatus.connected));
      await g.dispose();
    });

    test('call while disconnected fails fast', () async {
      final g = HermesGateway(
        _endpoint,
        connector: (_) async => FakeTransport(),
      );
      await expectLater(
        g.call('session.list'),
        throwsA(isA<GatewayDisconnected>()),
      );
      await g.dispose();
    });

    test('timeout fails the call and drops the pending entry', () async {
      final sockets = <FakeTransport>[];
      final g = HermesGateway(
        _endpoint,
        connector: (_) async {
          final t = FakeTransport();
          sockets.add(t);
          return t;
        },
        callTimeout: const Duration(milliseconds: 30),
        baseBackoff: const Duration(milliseconds: 5),
        maxBackoff: const Duration(milliseconds: 5),
      );
      await g.connect();

      await expectLater(
        g.call('session.list'),
        throwsA(
          isA<GatewayRpcException>().having(
            (e) => e.message,
            'message',
            contains('timeout'),
          ),
        ),
      );
      // A silent socket is probed once and only then replaced — see
      // dead_socket_test for why the probe exists.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(sockets.first.closed, isTrue);

      // A late reply for an already-timed-out id must be harmless.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      sockets.last.emit({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'sessions': []},
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await g.dispose();
    });
  });

  _credentialRedactionTests();

  group('reconnect', () {
    test(
      'connecting again closes the old transport and fails stale calls',
      () async {
        final transports = <FakeTransport>[];
        final gateway = HermesGateway(
          _endpoint,
          connector: (_) async {
            final transport = FakeTransport();
            transports.add(transport);
            return transport;
          },
        );
        await gateway.connect();

        final staleCall = gateway.call('session.list');
        final staleExpectation = expectLater(
          staleCall,
          throwsA(isA<GatewayDisconnected>()),
        );
        await gateway.connect();
        await staleExpectation;

        expect(transports, hasLength(2));
        expect(transports.first.closed, isTrue);
        expect(transports.last.closed, isFalse);
        await gateway.dispose();
      },
    );

    test(
      'verification treats an unknown-method response as liveness',
      () async {
        final transport = FakeTransport();
        final gateway = HermesGateway(
          _endpoint,
          connector: (_) async => transport,
        );
        await gateway.connect();

        final verification = gateway.verifyConnection();
        await Future<void>.delayed(Duration.zero);
        expect(transport.lastSent['method'], 'caduceus.ping');
        transport.errorTo(0, -32601, 'unknown method');

        await expectLater(verification, completes);
        await gateway.dispose();
      },
    );

    test('a refused upgrade is terminal, not retried forever', () async {
      var attempts = 0;
      final g = HermesGateway(
        _endpoint,
        connector: (_) async {
          attempts++;
          throw TransportUpgradeException(403);
        },
      );

      await expectLater(g.connect(), throwsA(isA<TransportUpgradeException>()));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Retrying a rejected credential burns battery and hides the cause.
      expect(attempts, 1);
      expect(g.state.status, GatewayStatus.fatal);
      await g.dispose();
    });

    test('a dropped socket schedules a reconnect', () async {
      final transports = <FakeTransport>[];
      final g = HermesGateway(
        _endpoint,
        connector: (_) async {
          final t = FakeTransport();
          transports.add(t);
          return t;
        },
        baseBackoff: const Duration(milliseconds: 5),
      );
      await g.connect();
      expect(g.state.isConnected, isTrue);

      await transports.first.drop();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        transports.length,
        greaterThan(1),
        reason: 'should have opened a new transport',
      );
      await g.dispose();
    });

    test('backoff grows, is capped, and is jittered', () {
      final g = HermesGateway(
        _endpoint,
        connector: (_) async => FakeTransport(),
        baseBackoff: const Duration(milliseconds: 100),
        maxBackoff: const Duration(seconds: 2),
        random: Random(1),
      );

      // Full jitter means each value is in [0, cap], so compare ceilings.
      int ceilingFor(int attempt) => [
        for (var i = 0; i < 60; i++) g.backoffFor(attempt).inMilliseconds,
      ].reduce(max);

      expect(ceilingFor(1), lessThanOrEqualTo(100));
      expect(ceilingFor(3), greaterThan(ceilingFor(1)));
      expect(ceilingFor(20), lessThanOrEqualTo(2000));

      final samples = {for (var i = 0; i < 20; i++) g.backoffFor(6)};
      expect(samples.length, greaterThan(1), reason: 'must be jittered');
    });

    test('a single-use ticket is re-minted before each attempt', () async {
      var minted = 0;
      final tickets = <String>[];
      final g = HermesGateway(
        HermesEndpoint(
          host: '127.0.0.1',
          port: 9119,
          credential: 'initial',
          authMode: GatewayAuthMode.gatedTicket,
        ),
        connector: (url) async {
          tickets.add(url.queryParameters['ticket']!);
          return FakeTransport();
        },
        refreshCredential: () async => 'ticket-${++minted}',
        baseBackoff: const Duration(milliseconds: 5),
      );

      await g.connect();
      expect(tickets, [
        'ticket-1',
      ], reason: 'a 30s single-use ticket cannot be reused across connects');
      await g.dispose();
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
}

void _credentialRedactionTests() {
  group('credential redaction', () {
    // dart:io puts the full request URL in its exception message. That message
    // reaches logs and crash reports, so the credential must not survive it.
    test('token is stripped from upgrade errors', () {
      final e = TransportUpgradeException(
        403,
        "WebSocketException: Connection to "
        "'http://127.0.0.1:9219/api/ws?token=super-secret-value#' was not "
        "upgraded to websocket, HTTP status code: 403",
      );
      expect('$e', isNot(contains('super-secret-value')));
      expect('$e', contains('<redacted>'));
      expect('$e', contains('403'));
    });

    test('every credential-bearing parameter is covered', () {
      for (final param in ['token', 'ticket', 'internal', 'api_key']) {
        final redacted = TransportUpgradeException.redactCredentials(
          'ws://h/api/ws?$param=leaky-value&other=keep',
        );
        expect(redacted, isNot(contains('leaky-value')), reason: param);
        expect(redacted, contains('other=keep'), reason: param);
      }
    });
  });
}
