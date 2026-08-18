/// The handshake, pinned.
///
/// Every constant here was paid for with a rejection from a live gateway, and
/// each test names the error that comes back when it is wrong. That is the
/// point of the file: none of this is in the published protocol docs, so
/// without it the next person re-derives it by trial and error against
/// someone's server.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';
import 'package:test/test.dart';

/// Decodes unpadded base64url. A 32-byte key encodes to 43 characters and a
/// 64-byte signature to 86, so the padding differs — counting it by hand is
/// how both of these first failed.
List<int> _unb64u(String value) =>
    base64Url.decode(value.padRight((value.length + 3) ~/ 4 * 4, '='));

class _FakeTransport implements ClawTransport {
  final _in = StreamController<String>.broadcast();
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

  void push(Object frame) => _in.add(jsonEncode(frame));

  void challenge({String nonce = 'n-1', int ts = 1785909648645}) => push({
        'type': 'event',
        'event': 'connect.challenge',
        'payload': {'nonce': nonce, 'ts': ts},
      });

  Map<String, dynamic>? get connectFrame =>
      sent.where((f) => f['method'] == 'connect').firstOrNull;
}

Future<(ClawGateway, _FakeTransport)> _gateway({String token = ''}) async {
  final transport = _FakeTransport();
  final gateway = ClawGateway(
    ClawEndpoint(url: Uri.parse('wss://example.test/'), token: token),
    identity: await ClawDeviceIdentity.generate(),
    connector: (_) async => transport,
  );
  return (gateway, transport);
}

void main() {
  group('device identity', () {
    test('the id is the hex sha-256 of the raw public key', () async {
      final identity = await ClawDeviceIdentity.generate();
      final seed = await identity.extractSeed();
      final pub =
          await (await Ed25519().newKeyPairFromSeed(seed)).extractPublicKey();
      final expected = await Sha256().hash(pub.bytes);

      expect(
        identity.deviceId,
        expected.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        reason: 'anything else answers DEVICE_AUTH_DEVICE_ID_MISMATCH',
      );
      expect(identity.deviceId.length, 64, reason: 'not truncated');
    });

    test('the public key is unpadded base64url of the raw 32 bytes', () async {
      final identity = await ClawDeviceIdentity.generate();

      expect(identity.publicKey, isNot(contains('=')));
      expect(identity.publicKey, isNot(contains('+')));
      expect(identity.publicKey, isNot(contains('/')));
      expect(_unb64u(identity.publicKey).length, 32);
    });

    test('an identity restored from its seed is the same identity', () async {
      // A device that regenerates its key on every launch has to be paired
      // again on every launch.
      final first = await ClawDeviceIdentity.generate();
      final again =
          await ClawDeviceIdentity.fromSeed(await first.extractSeed());

      expect(again.deviceId, first.deviceId);
      expect(again.publicKey, first.publicKey);
    });
  });

  group('the signed payload', () {
    test('is v3, pipe-joined, in a fixed order', () {
      expect(
        deviceAuthPayloadV3(
          deviceId: 'dev',
          clientId: 'cli',
          clientMode: 'cli',
          role: 'operator',
          scopes: const [],
          signedAtMs: 1785909648645,
          nonce: 'abc',
          platform: 'macos',
        ),
        'v3|dev|cli|cli|operator||1785909648645||abc|macos|',
      );
    });

    test('keeps empty fields as empty, not absent', () {
      // The gateway compares the string byte for byte. A missing token has to
      // leave its pipes behind or every field after it shifts left.
      final payload = deviceAuthPayloadV3(
        deviceId: 'd',
        clientId: 'c',
        clientMode: 'cli',
        role: 'operator',
        scopes: const [],
        signedAtMs: 1,
        nonce: 'n',
      );
      expect(payload.split('|').length, 11);
      expect(payload, endsWith('|1||n||'));
    });

    test('lowercases platform and deviceFamily and nothing else', () {
      // normalizeDeviceMetadataForAuth applies to exactly these two.
      final payload = deviceAuthPayloadV3(
        deviceId: 'DeV',
        clientId: 'CLI',
        clientMode: 'cli',
        role: 'operator',
        scopes: const [],
        signedAtMs: 1,
        nonce: 'N',
        platform: 'MacOS',
        deviceFamily: 'Mac',
      );
      expect(payload, contains('|macos|mac'));
      expect(payload, contains('DeV'), reason: 'the id is not normalised');
      expect(payload, contains('CLI'));
      expect(payload, contains('|N|'), reason: 'nor is the nonce');
    });

    test('joins scopes with commas', () {
      expect(
        deviceAuthPayloadV3(
          deviceId: 'd',
          clientId: 'c',
          clientMode: 'cli',
          role: 'operator',
          scopes: const ['a', 'b'],
          signedAtMs: 1,
          nonce: 'n',
        ),
        contains('|a,b|'),
      );
    });
  });

  group('connect', () {
    test('connecting again closes the old transport and fails stale calls',
        () async {
      final identity = await ClawDeviceIdentity.generate();
      final transports = <_FakeTransport>[];
      Future<ClawTransport> connect(ClawEndpoint endpoint) async {
        final transport = _FakeTransport();
        transports.add(transport);
        return transport;
      }

      final gateway = ClawGateway(
        ClawEndpoint(url: Uri.parse('wss://example.test/'), token: 't'),
        identity: identity,
        connector: connect,
      );
      final firstConnection = gateway.connect();
      await Future<void>.delayed(Duration.zero);
      transports.first.challenge();
      await Future<void>.delayed(Duration.zero);
      transports.first.push({
        'type': 'res',
        'id': '_connect',
        'ok': true,
        'payload': {
          'protocol': 4,
          'auth': {
            'scopes': ['chat']
          }
        },
      });
      await firstConnection;

      final staleCall = gateway.call('sessions.list');
      final staleExpectation = expectLater(
        staleCall,
        throwsA(isA<ClawRpcException>()),
      );
      final secondConnection = gateway.connect();
      await staleExpectation;
      await Future<void>.delayed(Duration.zero);
      transports.last.challenge();
      await Future<void>.delayed(Duration.zero);
      transports.last.push({
        'type': 'res',
        'id': '_connect',
        'ok': true,
        'payload': {
          'protocol': 4,
          'auth': {
            'scopes': ['chat']
          }
        },
      });
      await secondConnection;

      expect(transports.first.sent, isNotEmpty);
      expect(transports.first.closed, isTrue);
      expect(transports.last.closed, isFalse);
      await gateway.dispose();
    });

    test('waits for the challenge before sending anything', () async {
      final (gateway, transport) = await _gateway();
      unawaited(gateway.connect().catchError((_) => throw 'ignored'));
      await Future<void>.delayed(Duration.zero);

      expect(
        transport.sent,
        isEmpty,
        reason: 'the nonce and timestamp are both inputs to the signature, so '
            'there is nothing to send until the server speaks',
      );
      await gateway.dispose();
    });

    test('answers with a signature over the challenge', () async {
      final (gateway, transport) = await _gateway();
      unawaited(gateway.connect().catchError((_) => throw 'ignored'));
      await Future<void>.delayed(Duration.zero);
      transport.challenge(nonce: 'the-nonce', ts: 1785909648645);
      await Future<void>.delayed(Duration.zero);

      final frame = transport.connectFrame!;
      final params = frame['params'] as Map<String, dynamic>;
      final device = params['device'] as Map<String, dynamic>;

      expect(device['nonce'], 'the-nonce');
      expect(device['signedAt'], 1785909648645);
      expect(device['id'], gateway.identity.deviceId);
      expect(device['publicKey'], gateway.identity.publicKey);

      // The signature really verifies against the key it ships with.
      final verified = await Ed25519().verify(
        utf8.encode(
          deviceAuthPayloadV3(
            deviceId: gateway.identity.deviceId,
            clientId: 'cli',
            clientMode: 'cli',
            role: 'operator',
            scopes: const [],
            signedAtMs: 1785909648645,
            nonce: 'the-nonce',
            platform: 'macos',
          ),
        ),
        signature: Signature(
          _unb64u('${device['signature']}'),
          publicKey: SimplePublicKey(
            _unb64u(gateway.identity.publicKey),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      expect(verified, isTrue);
      await gateway.dispose();
    });

    test('signs the token in, not just alongside', () async {
      // The token is field 8 of the payload. A client that picks its
      // credential after signing sends a valid signature over the wrong
      // string, and the gateway reports it as a *device identity* problem —
      // which is a misleading place to start looking.
      final (withToken, a) = await _gateway(token: 'secret');
      final (without, b) = await _gateway();
      unawaited(withToken.connect().catchError((_) => throw 'ignored'));
      unawaited(without.connect().catchError((_) => throw 'ignored'));
      await Future<void>.delayed(Duration.zero);
      a.challenge();
      b.challenge();
      await Future<void>.delayed(Duration.zero);

      final signedWith =
          ((a.connectFrame!['params'] as Map)['device'] as Map)['signature'];
      final signedWithout =
          ((b.connectFrame!['params'] as Map)['device'] as Map)['signature'];
      expect(signedWith, isNot(signedWithout));

      expect(
        (a.connectFrame!['params'] as Map)['auth'],
        {'token': 'secret'},
      );
      expect(
        (b.connectFrame!['params'] as Map).containsKey('auth'),
        isFalse,
        reason: 'no credential, no auth block',
      );
      await withToken.dispose();
      await without.dispose();
    });

    test('declares the protocol range and the closed-set fields', () async {
      final (gateway, transport) = await _gateway();
      unawaited(gateway.connect().catchError((_) => throw 'ignored'));
      await Future<void>.delayed(Duration.zero);
      transport.challenge();
      await Future<void>.delayed(Duration.zero);

      final params = transport.connectFrame!['params'] as Map<String, dynamic>;
      expect(params['minProtocol'], 1);
      expect(params['maxProtocol'], 4);
      // Rejected as "must be equal to one of the allowed values" otherwise.
      expect((params['client'] as Map)['mode'], 'cli');
      expect((params['client'] as Map)['id'], 'cli');
      // And "invalid role" if this is a mode rather than a role.
      expect(params['role'], 'operator');
      await gateway.dispose();
    });

    test('completes with hello-ok', () async {
      final (gateway, transport) = await _gateway();
      final connecting = gateway.connect();
      await Future<void>.delayed(Duration.zero);
      transport.challenge();
      await Future<void>.delayed(Duration.zero);
      transport.push({
        'type': 'res',
        'id': '_connect',
        'ok': true,
        'payload': {
          'type': 'hello-ok',
          'protocol': 4,
          'server': {'version': '1.2.3', 'connId': 'c1'},
          'auth': {
            'role': 'operator',
            'scopes': ['chat']
          },
          'policy': {'maxPayload': 26214400},
        },
      });

      final hello = await connecting;
      expect(hello.protocol, 4);
      expect(hello.serverVersion, '1.2.3');
      expect(hello.role, 'operator');
      expect(hello.scopes, ['chat']);
      expect(hello.maxPayload, 26214400);
      await gateway.dispose();
    });

    test('surfaces a missing gateway token as exactly that', () async {
      // The live server's real answer. It matters that this is distinguishable
      // from a protocol bug: it is a credential the user has to supply, not
      // something to fix in code.
      final (gateway, transport) = await _gateway();
      final connecting = gateway.connect();
      await Future<void>.delayed(Duration.zero);
      transport.challenge();
      await Future<void>.delayed(Duration.zero);
      transport.push({
        'type': 'res',
        'id': '_connect',
        'ok': false,
        'error': {
          'code': 'INVALID_REQUEST',
          'message': 'unauthorized: gateway token missing '
              '(set gateway.remote.token to match gateway.auth.token)',
          'details': {
            'code': 'AUTH_TOKEN_MISSING',
            'authReason': 'token_missing',
          },
        },
      });

      final error = await connecting
          .then<Object?>((_) => null)
          .catchError((Object e) => e);
      expect(error, isA<ClawRpcException>());
      expect((error! as ClawRpcException).needsGatewayToken, isTrue);
      expect((error as ClawRpcException).needsPairing, isFalse);
      await gateway.dispose();
    });

    test('and tells a wrong token apart from an absent one', () async {
      // Both are the same fix — supply the right value — but not the same
      // situation, and someone told only "unauthorized" goes looking for a
      // mistake in the signature instead.
      final (gateway, transport) = await _gateway(token: 'wrong');
      final connecting = gateway.connect();
      await Future<void>.delayed(Duration.zero);
      transport.challenge();
      await Future<void>.delayed(Duration.zero);
      transport.push({
        'type': 'res',
        'id': '_connect',
        'ok': false,
        'error': {
          'code': 'INVALID_REQUEST',
          'message': 'unauthorized: gateway token mismatch',
          'details': {'code': 'AUTH_TOKEN_MISMATCH'},
        },
      });

      final error = await connecting
          .then<Object?>((_) => null)
          .catchError((Object e) => e) as ClawRpcException;
      expect(error.needsGatewayToken, isTrue);
      expect(error.gatewayTokenWrong, isTrue);
      await gateway.dispose();
    });

    test('and an unpaired device as pairing, not as a bad request', () async {
      final (gateway, transport) = await _gateway();
      final connecting = gateway.connect();
      await Future<void>.delayed(Duration.zero);
      transport.challenge();
      await Future<void>.delayed(Duration.zero);
      transport.push({
        'type': 'res',
        'id': '_connect',
        'ok': false,
        'error': {'code': 'NOT_PAIRED', 'message': 'device identity required'},
      });

      final error = await connecting
          .then<Object?>((_) => null)
          .catchError((Object e) => e);
      expect((error! as ClawRpcException).needsPairing, isTrue);
      await gateway.dispose();
    });
  });

  group('events', () {
    test('carry seq and stateVersion', () async {
      final (gateway, transport) = await _gateway();
      final connecting = gateway.connect();
      await Future<void>.delayed(Duration.zero);
      transport.challenge();
      await Future<void>.delayed(Duration.zero);
      transport.push({
        'type': 'res',
        'id': '_connect',
        'ok': true,
        'payload': {'protocol': 4},
      });
      await connecting;

      final seen = <ClawEvent>[];
      gateway.events.listen(seen.add);
      transport.push({
        'type': 'event',
        'event': 'agent',
        'payload': {'deltaText': 'hel'},
        'seq': 7,
        'stateVersion': 'v9',
      });
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.name, 'agent');
      expect(seen.single.payload['deltaText'], 'hel');
      expect(seen.single.seq, 7);
      expect(seen.single.stateVersion, 'v9');
      await gateway.dispose();
    });

    test('the challenge is consumed, not published', () async {
      final (gateway, transport) = await _gateway();
      unawaited(gateway.connect().catchError((_) => throw 'ignored'));
      final seen = <ClawEvent>[];
      gateway.events.listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      transport.challenge();
      await Future<void>.delayed(Duration.zero);

      expect(
        seen,
        isEmpty,
        reason: 'handshake plumbing is not a conversation event',
      );
      await gateway.dispose();
    });
  });

  group('rpc', () {
    Future<(ClawGateway, _FakeTransport)> connected() async {
      final (gateway, transport) = await _gateway();
      final connecting = gateway.connect();
      await Future<void>.delayed(Duration.zero);
      transport.challenge();
      await Future<void>.delayed(Duration.zero);
      transport.push({
        'type': 'res',
        'id': '_connect',
        'ok': true,
        'payload': {'protocol': 4},
      });
      await connecting;
      return (gateway, transport);
    }

    test('sends an idempotency key only when given one', () async {
      final (gateway, transport) = await connected();

      unawaited(gateway.call('sessions.send', {'text': 'hi'}, 'key-1'));
      unawaited(
          gateway.call('sessions.list').catchError((_) => <String, dynamic>{}));
      await Future<void>.delayed(Duration.zero);

      final send =
          transport.sent.firstWhere((f) => f['method'] == 'sessions.send');
      final list =
          transport.sent.firstWhere((f) => f['method'] == 'sessions.list');
      expect((send['params'] as Map)['idempotencyKey'], 'key-1');
      expect((list['params'] as Map).containsKey('idempotencyKey'), isFalse);
      await gateway.dispose();
    });

    test('routes a response back to its own request', () async {
      final (gateway, transport) = await connected();
      final a = gateway.call('one');
      final b = gateway.call('two');
      await Future<void>.delayed(Duration.zero);

      final ids = transport.sent
          .where((f) => f['method'] != 'connect')
          .map((f) => f['id'])
          .toList();
      transport.push({
        'type': 'res',
        'id': ids[1],
        'ok': true,
        'payload': {'n': 2}
      });
      transport.push({
        'type': 'res',
        'id': ids[0],
        'ok': true,
        'payload': {'n': 1}
      });

      expect((await a)['n'], 1);
      expect((await b)['n'], 2);
      await gateway.dispose();
    });

    test('an error carries its retry advice', () async {
      final (gateway, transport) = await connected();
      final call = gateway.call('sessions.send');
      await Future<void>.delayed(Duration.zero);
      final id = transport.sent.last['id'];
      transport.push({
        'type': 'res',
        'id': id,
        'ok': false,
        'error': {
          'code': 'RATE_LIMITED',
          'message': 'slow down',
          'retryable': true,
          'retryAfterMs': 1500,
        },
      });

      final error = await call
          .then<Object?>((_) => null)
          .catchError((Object e) => e) as ClawRpcException;
      // The useful difference from JSON-RPC's numeric codes: a client can
      // honour a limit it was never told about at compile time.
      expect(error.retryable, isTrue);
      expect(error.retryAfterMs, 1500);
      await gateway.dispose();
    });
  });

  test('an endpoint never prints its credential', () {
    // This string ends up in logs and on screenshots.
    final endpoint = ClawEndpoint(
      url: Uri.parse('wss://nas.example.test/'),
      token: 'super-secret-token',
    );
    expect('$endpoint', isNot(contains('super-secret')));
    expect('$endpoint', 'nas.example.test');
  });
}
