/// The conversation surface — session listing and a streamed reply.
///
/// The gateway's answers are faked here because a live one is behind the
/// pairing gate; what these pin is the client's *handling* — that the request
/// envelope is right, that a reply assembles from deltaText, and that a turn
/// ends on the terminal signal. The method names and payload shapes are the
/// documented contract, and this is where they get re-verified the day a
/// paired credential exists.
library;

import 'dart:async';
import 'dart:convert';

import 'package:openclaw_protocol/openclaw_protocol.dart';
import 'package:test/test.dart';

class _FakeTransport implements ClawTransport {
  final _in = StreamController<String>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Stream<String> get inbound => _in.stream;
  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, dynamic>);
  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  void push(Object frame) => _in.add(jsonEncode(frame));
  Map<String, dynamic> lastOf(String method) =>
      sent.lastWhere((f) => f['method'] == method);
  void reply(String method, Map<String, dynamic> payload) {
    final id = lastOf(method)['id'];
    push({'type': 'res', 'id': id, 'ok': true, 'payload': payload});
  }
}

Future<(ClawGateway, _FakeTransport)> _connected() async {
  final transport = _FakeTransport();
  final gateway = ClawGateway(
    ClawEndpoint(url: Uri.parse('wss://example.test/')),
    identity: await ClawDeviceIdentity.generate(),
    connector: (_) async => transport,
  );
  final connecting = gateway.connect();
  await Future<void>.delayed(Duration.zero);
  transport.push({
    'type': 'event',
    'event': 'connect.challenge',
    'payload': {'nonce': 'n', 'ts': 1},
  });
  await Future<void>.delayed(Duration.zero);
  transport.push({'type': 'res', 'id': '_connect', 'ok': true, 'payload': {'protocol': 4}});
  await connecting;
  return (gateway, transport);
}

void main() {
  test('sessions() asks sessions.list and parses the rows', () async {
    final (gateway, transport) = await _connected();
    final future = gateway.sessions(limit: 20);
    await Future<void>.delayed(Duration.zero);

    // The two title flags cost a file read per session, so they travel with
    // the limit that bounds them.
    expect(transport.lastOf('sessions.list')['params'], {
      'limit': 20,
      'includeDerivedTitles': true,
      'includeLastMessage': true,
    });
    transport.reply('sessions.list', {
      'sessions': [
        {
          'key': 's1',
          'label': '模型身份确认',
          'derivedTitle': 'first user message',
          'lastMessagePreview': 'pong',
          'origin': {'provider': 'webchat'},
          'model': 'glm-latest',
          'hasActiveRun': true,
        },
        // A row also carries `sessionId`, the transcript file's id. Reading
        // that as the identity produces requests the gateway rejects as a
        // session that does not exist.
        {
          'key': 's2',
          'sessionId': 'not-the-key',
          'derivedTitle': 'Blue Sky',
          'lastChannel': 'telegram',
        },
      ],
    });

    final sessions = await future;
    expect(sessions.map((s) => s.key), ['s1', 's2']);
    // A hand-set label outranks the derived one.
    expect(sessions.first.title, '模型身份确认');
    expect(sessions.first.preview, 'pong');
    expect(sessions.first.source, 'webchat');
    expect(sessions.first.model, 'glm-latest');
    expect(sessions.first.running, isTrue);
    // No label: the gateway's own title from the first message, and never the
    // key, which is a routing address and reads like one.
    expect(sessions[1].title, 'Blue Sky');
    expect(sessions[1].source, 'telegram');
    await gateway.dispose();
  });

  test('send() carries the idempotency key and streams the reply', () async {
    final (gateway, transport) = await _connected();
    final turn = gateway.send('s1', 'what model are you', clientId: 'k1');
    final chunks = <String>[];
    turn.deltas.listen(chunks.add);
    await Future<void>.delayed(Duration.zero);

    final call = transport.lastOf('sessions.send');
    // `key` and `message`. An earlier draft sent `sessionId` and `text`, and
    // the schema is additionalProperties:false, so it would not have been
    // loosely accepted — it would have been rejected whole.
    expect(call['params']['key'], 's1');
    expect(call['params']['message'], 'what model are you');
    expect(call['params']['idempotencyKey'], 'k1',
        reason: 'required by the gateway on side-effecting calls');

    // Reply arrives as deltaText increments, then a final snapshot.
    // The shapes below are what a live gateway actually sends: a `chat`
    // event with state "delta" carrying deltaText, then the same event with
    // state "final" and a stopReason.
    transport.push({'type': 'event', 'event': 'chat',
      'payload': {'sessionKey': 's1', 'state': 'delta', 'deltaText': 'I am '}});
    transport.push({'type': 'event', 'event': 'chat',
      'payload': {'sessionKey': 's1', 'state': 'delta', 'deltaText': 'glm-5.'}});
    transport.push({'type': 'event', 'event': 'chat',
      'payload': {'sessionKey': 's1', 'state': 'final',
        'message': 'I am glm-5.', 'stopReason': 'stop'}});
    await Future<void>.delayed(Duration.zero);

    expect(chunks, ['I am ', 'glm-5.']);
    expect(await turn.whenDone, 'I am glm-5.');
    await gateway.dispose();
  });

  test('only state:final ends the turn, and it is on the chat event',
      () async {
    final (gateway, transport) = await _connected();
    final turn = gateway.send('s1', 'hi', clientId: 'k2');
    await Future<void>.delayed(Duration.zero);
    transport.push({'type': 'event', 'event': 'chat',
      'payload': {'sessionKey': 's1', 'state': 'delta', 'deltaText': 'hey'}});

    // Everything an earlier draft believed ended a turn. None of these exist,
    // and a client that waits for one hangs in a way indistinguishable from a
    // hung agent — which is why they are asserted *not* to end it.
    transport.push({'type': 'event', 'event': 'chat.done',
      'payload': {'sessionKey': 's1'}});
    transport.push({'type': 'event', 'event': 'message.complete',
      'payload': {'sessionKey': 's1'}});
    transport.push({'type': 'event', 'event': 'sessions.changed',
      'payload': {'sessionKey': 's1', 'status': 'done', 'phase': 'end'}});
    await Future<void>.delayed(Duration.zero);
    var ended = false;
    unawaited(turn.whenDone.then((_) => ended = true));
    await Future<void>.delayed(Duration.zero);
    expect(ended, isFalse);

    transport.push({'type': 'event', 'event': 'chat',
      'payload': {'sessionKey': 's1', 'state': 'final', 'stopReason': 'stop'}});
    expect(await turn.whenDone.timeout(const Duration(seconds: 1)), 'hey');
    await gateway.dispose();
  });

  test('events for another session do not bleed into the turn', () async {
    final (gateway, transport) = await _connected();
    final turn = gateway.send('s1', 'hi', clientId: 'k3');
    final chunks = <String>[];
    turn.deltas.listen(chunks.add);
    await Future<void>.delayed(Duration.zero);

    transport.push({'type': 'event', 'event': 'chat',
      'payload': {'sessionKey': 's2', 'state': 'delta', 'deltaText': 'not mine'}});
    transport.push({'type': 'event', 'event': 'chat',
      'payload': {'sessionKey': 's1', 'state': 'delta', 'deltaText': 'mine'}});
    transport.push({'type': 'event', 'event': 'chat',
      'payload': {'sessionKey': 's1', 'state': 'final', 'stopReason': 'stop'}});
    await Future<void>.delayed(Duration.zero);

    expect(chunks, ['mine']);
    await gateway.dispose();
  });

  test('a send that the gateway rejects fails the turn, not the process',
      () async {
    final (gateway, transport) = await _connected();
    final turn = gateway.send('s1', 'hi', clientId: 'k4');
    await Future<void>.delayed(Duration.zero);
    final id = transport.lastOf('sessions.send')['id'];
    transport.push({'type': 'res', 'id': id, 'ok': false,
      'error': {'code': 'FORBIDDEN', 'message': 'no', 'details': {'code': 'MISSING_SCOPE'}}});

    await expectLater(turn.whenDone, throwsA(isA<ClawRpcException>()));
    await gateway.dispose();
  });

  test('createSession() sends only what the schema allows', () async {
    final (gateway, transport) = await _connected();
    final future = gateway.createSession(label: 'new');
    await Future<void>.delayed(Duration.zero);

    final params = transport.lastOf('sessions.create')['params'] as Map;
    expect(params['label'], 'new');
    // additionalProperties: false. Every one of these was sent by an earlier
    // draft, and any one of them fails the whole request rather than being
    // ignored — which is why they are asserted absent rather than left to
    // chance.
    expect(params.containsKey('title'), isFalse);
    expect(params.containsKey('cwd'), isFalse);
    expect(params.containsKey('idempotencyKey'), isFalse);

    transport.reply('sessions.create', {'ok': true, 'key': 's-new'});
    expect(await future, 's-new');
    await gateway.dispose();
  });

  test('createSession() forks a parent transcript when asked', () async {
    final (gateway, transport) = await _connected();
    final future = gateway.createSession(parentSessionKey: 's1', fork: true);
    await Future<void>.delayed(Duration.zero);

    final params = transport.lastOf('sessions.create')['params'] as Map;
    expect(params['parentSessionKey'], 's1');
    expect(params['fork'], isTrue);

    transport.reply('sessions.create', {'ok': true, 'key': 's-fork'});
    expect(await future, 's-fork');
    await gateway.dispose();
  });

  test('resolveApproval() sends exactly id and decision', () async {
    final (gateway, transport) = await _connected();
    final future = gateway.resolveApproval(id: 'r1', decision: 'allow');
    await Future<void>.delayed(Duration.zero);

    // The whole schema, and nothing beside it. An earlier draft sent this as
    // `requestId` with an idempotency key attached; both would have failed.
    expect(transport.lastOf('exec.approval.resolve')['params'], {
      'id': 'r1',
      'decision': 'allow',
    });

    transport.reply('exec.approval.resolve', const {});
    await future;
    await gateway.dispose();
  });

  test('the transcript subscription is the one that carries a reply',
      () async {
    final (gateway, transport) = await _connected();

    // Session-index events. Per connection, and no parameters at all.
    unawaited(gateway.subscribeSessions());
    await Future<void>.delayed(Duration.zero);
    expect(transport.lastOf('sessions.subscribe')['params'], isEmpty);
    transport.reply('sessions.subscribe', const {});

    // The transcript. A client that subscribes only to the index above sends
    // a prompt and then waits forever for a reply that travels here.
    unawaited(gateway.subscribeMessages('s1'));
    await Future<void>.delayed(Duration.zero);
    expect(
      transport.lastOf('sessions.messages.subscribe')['params'],
      {'key': 's1'},
    );
    transport.reply('sessions.messages.subscribe', const {});

    unawaited(gateway.unsubscribeMessages('s1'));
    await Future<void>.delayed(Duration.zero);
    expect(
      transport.lastOf('sessions.messages.unsubscribe')['params'],
      {'key': 's1'},
      reason: 'skipping this leaves the gateway streaming to nobody',
    );
    transport.reply('sessions.messages.unsubscribe', const {});
    await gateway.dispose();
  });

  test('abort names the session key on sessions.abort', () async {
    final (gateway, transport) = await _connected();
    unawaited(gateway.abort('s1'));
    await Future<void>.delayed(Duration.zero);
    // Not chat.abort, which an earlier draft called with a `sessionId`.
    expect(transport.lastOf('sessions.abort')['params'], {'key': 's1'});
    transport.reply('sessions.abort', const {});
    await gateway.dispose();
  });

  test('history() reads chat.history, whose parameter is sessionKey',
      () async {
    final (gateway, transport) = await _connected();
    final future = gateway.history('s1', limit: 50);
    await Future<void>.delayed(Duration.zero);

    // `sessionKey` here, `key` on every sessions.* method. The gateway's own
    // inconsistency, and only its schema says so.
    expect(transport.lastOf('chat.history')['params'], {
      'sessionKey': 's1',
      'limit': 50,
    });
    transport.reply('chat.history', {
      'messages': [
        {'role': 'user', 'text': 'hello'},
      ],
    });

    expect((await future).single['role'], 'user');
    await gateway.dispose();
  });
}
