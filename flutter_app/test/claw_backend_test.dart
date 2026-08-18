/// [ClawBackend] driven through the real [ClawGateway], transport faked.
///
/// The bugs this file exists to catch are the six differences ARCHITECTURE.md
/// §3 calls out between OpenClaw and Hermes: explicit subscribe/unsubscribe,
/// an opaque resume cursor, delta-plus-snapshot reconciliation, and — most
/// important — a device that is authenticated but not paired becoming a
/// connection *state* rather than a thrown error. Unit tests on the mapping
/// alone or on `ClawGateway` alone both pass with any of these bugs present.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:caduceus/backends/claw_backend.dart';
import 'package:caduceus/backends/claw_memory.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';

/// Same shape as `handshake_test.dart`'s fake, plus helpers for driving
/// requests and events once the handshake is past.
class _Transport implements ClawTransport {
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

  void challenge({String nonce = 'n-1', int ts = 1785909648645}) => push({
    'type': 'event',
    'event': 'connect.challenge',
    'payload': {'nonce': nonce, 'ts': ts},
  });

  Map<String, dynamic>? lastOf(String method) {
    for (final f in sent.reversed) {
      if (f['method'] == method) return f;
    }
    return null;
  }

  void reply(String method, Object payload) {
    final frame = lastOf(method)!;
    push({'type': 'res', 'id': frame['id'], 'ok': true, 'payload': payload});
  }

  void replyError(String method, Map<String, dynamic> error) {
    final frame = lastOf(method)!;
    push({'type': 'res', 'id': frame['id'], 'ok': false, 'error': error});
  }

  /// Answers every outstanding [method] frame, in order, with [payloads].
  ///
  /// [reply] alone targets only the *last* frame of a method, which is wrong
  /// for the concurrent `skills.detail` fan-out the skill library makes.
  void replyEach(String method, List<Object> payloads) {
    final frames = [
      for (final f in sent)
        if (f['method'] == method) f,
    ];
    for (var i = 0; i < frames.length && i < payloads.length; i++) {
      push({
        'type': 'res',
        'id': frames[i]['id'],
        'ok': true,
        'payload': payloads[i],
      });
    }
  }

  /// A successful handshake, carrying the scopes the gateway *granted*.
  ///
  /// `auth.scopes` is not decoration: it is the only per-connection statement
  /// of what this device may do, and the adapter gates its capabilities on it.
  /// A fake that omitted it made every capability read as false — correctly,
  /// which is how this helper came to exist.
  void connectOk({List<String> scopes = ClawGateway.chatScopes}) => push({
    'type': 'res',
    'id': '_connect',
    'ok': true,
    'payload': {
      'protocol': 4,
      'auth': {'role': 'operator', 'scopes': scopes},
    },
  });

  void connectError(Map<String, dynamic> error) =>
      push({'type': 'res', 'id': '_connect', 'ok': false, 'error': error});

  void event(
    String type,
    Map<String, dynamic> payload, {
    int? seq,
    String? stateVersion,
  }) => push({
    'type': 'event',
    'event': type,
    'payload': payload,
    'seq': ?seq,
    'stateVersion': ?stateVersion,
  });
}

/// A gateway and backend wired to a fake transport, before connecting — most
/// tests need to drive the handshake themselves to reach the state under
/// test.
class _Rig {
  _Rig._(this.transport, this.gateway, this.backend);

  final _Transport transport;
  final ClawGateway gateway;
  final ClawBackend backend;

  static Future<_Rig> create({
    List<String> requestedScopes = ClawGateway.chatScopes,
  }) async {
    final transport = _Transport();
    final gateway = ClawGateway(
      ClawEndpoint(url: Uri.parse('wss://example.test/'), token: 't'),
      identity: await ClawDeviceIdentity.generate(),
      // What a real app asks for. Before the handshake lands the adapter
      // falls back to this, so a rig that requested nothing would answer
      // every `supports` with false for a reason unrelated to the test.
      scopes: requestedScopes,
      connector: (_) async => transport,
    );
    return _Rig._(transport, gateway, ClawBackend(gateway));
  }

  /// Drives a full successful handshake and returns once connected.
  ///
  /// [grantedScopes] is what the hello reports — the device's approved set,
  /// which is not always what was asked for and can be *more* than it. The
  /// gateway authorizes each RPC against the session's own request, so a rig
  /// that reports admin while asking only for chatScopes exercises the same
  /// mismatch a real paired device shows.
  static Future<_Rig> connected({
    List<String>? requestedScopes,
    List<String> grantedScopes = ClawGateway.chatScopes,
  }) async {
    final rig = await create(requestedScopes: requestedScopes ?? grantedScopes);
    final connecting = rig.backend.connect();
    await Future<void>.delayed(Duration.zero);
    rig.transport.challenge();
    await Future<void>.delayed(Duration.zero);
    rig.transport.connectOk(scopes: grantedScopes);
    await connecting;
    return rig;
  }

  /// Opens a session, answering **both** subscriptions.
  ///
  /// `open` subscribes to the session index and to the transcript, and the
  /// second is the one a reply travels on. A rig that answered only the first
  /// would hang here — which is a better failure than the one the adapter had
  /// before, where it never asked at all and waited forever at run time.
  Future<SessionHandle> open(String key) async {
    final opening = backend.open(key);
    await Future<void>.delayed(Duration.zero);
    transport.reply('sessions.subscribe', const {});
    await Future<void>.delayed(Duration.zero);
    transport.reply('sessions.messages.subscribe', const {});
    await Future<void>.delayed(Duration.zero);
    // A session asks its own row what it is called; without it a session
    // opened directly shows its routing address as a heading.
    transport.reply('sessions.describe', const {
      'session': {'key': 's1', 'derivedTitle': 'what model are you'},
    });
    return opening;
  }

  Future<void> dispose() => backend.dispose();
}

void main() {
  group('the pairing gate', () {
    test(
      'NOT_PAIRED completes connect() normally as awaitingApproval',
      () async {
        final rig = await _Rig.create();
        addTearDown(rig.dispose);

        final connecting = rig.backend.connect();
        await Future<void>.delayed(Duration.zero);
        rig.transport.challenge();
        await Future<void>.delayed(Duration.zero);
        rig.transport.connectError({
          'code': 'NOT_PAIRED',
          'message': 'device identity required',
        });

        // The single most important assertion in the file: a correct
        // handshake against a correct token must not surface as a failure.
        await expectLater(connecting, completes);
        expect(
          rig.backend.connectionState.status,
          AgentStatus.awaitingApproval,
          reason: 'nothing is wrong here — a human elsewhere must approve',
        );
        expect(rig.backend.connectionState.needsApproval, isTrue);
      },
    );

    test('a different connect error throws and sets fatal', () async {
      final rig = await _Rig.create();
      addTearDown(rig.dispose);

      final connecting = rig.backend.connect();
      await Future<void>.delayed(Duration.zero);
      rig.transport.challenge();
      await Future<void>.delayed(Duration.zero);
      rig.transport.connectError({
        'code': 'INVALID_REQUEST',
        'message': 'unauthorized: gateway token mismatch',
        'details': {'code': 'AUTH_TOKEN_MISMATCH'},
      });

      await expectLater(
        connecting,
        throwsA(isA<AgentException>()),
        reason: 'an auth problem is a real failure, unlike NOT_PAIRED',
      );
      expect(rig.backend.connectionState.status, AgentStatus.fatal);
    });
  });

  test('open() subscribes to the index and to the transcript', () async {
    final rig = await _Rig.connected();
    addTearDown(rig.dispose);

    await rig.open('s1');

    // The index subscription is per connection and takes no parameters.
    expect(rig.transport.lastOf('sessions.subscribe')?['params'], isEmpty);
    // The transcript subscription is the one a reply travels on, and it is
    // keyed. Calling only the first is the failure that looks exactly like a
    // hung agent: connected, listed, sent, and then nothing, forever.
    final messages = rig.transport.lastOf('sessions.messages.subscribe');
    expect(messages, isNotNull);
    expect((messages!['params'] as Map)['key'], 's1');
  });

  test('release() unsubscribes the transcript it subscribed to', () async {
    final rig = await _Rig.connected();
    addTearDown(rig.dispose);

    final handle = await rig.open('s1');

    final releasing = rig.backend.release(handle);
    await Future<void>.delayed(Duration.zero);
    final frame = rig.transport.lastOf('sessions.messages.unsubscribe');
    expect(frame, isNotNull);
    expect((frame!['params'] as Map)['key'], 's1');
    rig.transport.reply('sessions.messages.unsubscribe', const {});
    await releasing;
  });

  test(
    'release() does not throw when unsubscribe comes back as an error',
    () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      final handle = await rig.open('s1');

      final releasing = rig.backend.release(handle);
      await Future<void>.delayed(Duration.zero);
      rig.transport.replyError('sessions.messages.unsubscribe', {
        'code': 'NOT_FOUND',
        'message': 'no such subscription',
      });

      // Releasing is cleanup — a gateway that already forgot the
      // subscription is the outcome we wanted, not a bug to report.
      await expectLater(releasing, completes);
    },
  );

  group('event routing and the cursor', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connected();
      handle = await rig.open('s1');
    });

    tearDown(() => rig.dispose());

    test(
      'a delta for this session arrives as TextDelta with a cursor',
      () async {
        final future = rig.backend.events(handle).first;
        rig.transport.event(
          'agent',
          {'sessionKey': 's1', 'deltaText': 'hi'},
          seq: 3,
          stateVersion: 'v1',
        );
        final e = await future;
        expect(e, isA<TextDelta>());
        expect((e as TextDelta).text, 'hi');
        expect(
          e.cursor,
          isNotNull,
          reason: 'the frame carried seq and stateVersion',
        );
      },
    );

    test('an event tagged for another session does not arrive', () async {
      final events = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(events.add);
      addTearDown(sub.cancel);

      rig.transport.event('chat', {'sessionKey': 'other', 'deltaText': 'x'});
      await Future<void>.delayed(Duration.zero);
      expect(
        events,
        isEmpty,
        reason: 'routing must not leak one conversation into another',
      );
    });
  });

  group('a session renaming itself mid-conversation', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connected();
      handle = await rig.open('s1');
    });

    tearDown(() => rig.dispose());

    test('a derived title reaches the header while the turn runs', () async {
      final seen = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(seen.add);
      addTearDown(sub.cancel);

      // The gateway names a conversation from its first message, which means
      // *after* the session exists. Without this the header keeps whatever it
      // opened with, and a new session stays untitled for its whole life.
      rig.transport.event('sessions.changed', {
        'sessionKey': 's1',
        'displayName': 'what model are you',
        'model': 'glm-latest',
        'phase': 'start',
        'hasActiveRun': true,
      });
      await Future<void>.delayed(Duration.zero);

      final changed = seen.whereType<SessionChanged>().single;
      expect(changed.session.title, 'what model are you');
      expect(changed.session.model, 'glm-latest');
      expect(changed.session.running, isTrue);
      // Both, from the one frame: the header shows one and the timeline the
      // other.
      expect(seen.whereType<TurnStarted>(), hasLength(1));
    });

    test('a heartbeat with nothing to say raises nothing', () async {
      final seen = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(seen.add);
      addTearDown(sub.cancel);

      // `agent` beats arrive several times a turn carrying no text. A notice
      // per beat is churn through every listener for no gain.
      rig.transport.event('agent', {
        'sessionKey': 's1',
        'isHeartbeat': true,
        'runId': 'r1',
      });
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
    });
  });

  group('someone else talking to the same agent', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connected();
      handle = await rig.open('s1');
    });

    tearDown(() => rig.dispose());

    Future<List<AgentEvent>> collect(void Function() emit) async {
      final seen = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(seen.add);
      addTearDown(sub.cancel);
      emit();
      await Future<void>.delayed(Duration.zero);
      return seen;
    }

    test('a message from another client joins the transcript', () async {
      final seen = await collect(() {
        rig.transport.event('session.message', {
          'sessionKey': 's1',
          'message': {
            'role': 'user',
            'content': 'sent from a phone',
            'idempotencyKey': 'someone-else:user',
          },
        });
      });

      final appended = seen.whereType<MessageAppended>().single;
      expect(appended.message.text, 'sent from a phone');
      expect(appended.message.role, MessageRole.user);
    });

    test('our own message does not come back as a second copy', () async {
      // The gateway echoes every stored message to every subscriber, ours
      // included. Without recognising it, each message a user types appears
      // twice — once as they typed it and once as the server's copy.
      final sending = rig.backend.send(handle, 'mine', clientId: 'k-mine');
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('sessions.send', const {});
      await sending;

      final seen = await collect(() {
        rig.transport.event('session.message', {
          'sessionKey': 's1',
          'message': {
            'role': 'user',
            'content': 'mine',
            'idempotencyKey': 'k-mine:user',
          },
        });
      });

      expect(seen.whereType<MessageAppended>(), isEmpty);
    });

    test('a stored answer nobody streamed is still shown', () async {
      // Watched happening on a live gateway: the run completed, the deltas
      // never arrived, and the transcript stayed empty. The stored copy is
      // the only one there is in that case.
      final seen = await collect(() {
        rig.transport.event('session.message', {
          'sessionKey': 's1',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Hello there, friend!'},
            ],
          },
        });
      });

      expect(seen.whereType<TextReset>().single.text, 'Hello there, friend!');
    });

    test('a stored answer that matches the deltas is not repeated', () async {
      final seen = await collect(() {
        rig.transport.event('chat', {
          'sessionKey': 's1',
          'state': 'delta',
          'deltaText': 'Hello there, friend!',
        });
        rig.transport.event('session.message', {
          'sessionKey': 's1',
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Hello there, friend!'},
            ],
          },
        });
      });

      expect(seen.whereType<TextDelta>(), hasLength(1));
      expect(seen.whereType<TextReset>(), isEmpty);
    });

    test('a tool row is not shown twice', () async {
      // It already arrived as `session.tool`, in more detail and while it was
      // happening.
      final seen = await collect(() {
        rig.transport.event('session.message', {
          'sessionKey': 's1',
          'message': {
            'role': 'toolResult',
            'toolCallId': 'exec-1',
            'toolName': 'exec',
            'content': [
              {'type': 'text', 'text': 'output'},
            ],
          },
        });
      });

      expect(seen, isEmpty);
    });
  });

  group('an approval that has been answered', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connected();
      handle = await rig.open('s1');
    });

    tearDown(() => rig.dispose());

    test(
      'the resolution withdraws the question, it does not repeat it',
      () async {
        final seen = <AgentEvent>[];
        final sub = rig.backend.events(handle).listen(seen.add);
        addTearDown(sub.cancel);

        rig.transport.event('exec.approval.requested', {
          'sessionKey': 's1',
          'requestId': 'r1',
          'command': 'rm -rf /',
          'choices': ['allow', 'deny'],
        });
        await Future<void>.delayed(Duration.zero);
        // Matching anything with "approval" in its name put the answered
        // question straight back on screen, now unanswerable.
        rig.transport.event('exec.approval.resolved', {
          'sessionKey': 's1',
          'requestId': 'r1',
          'decision': 'allow',
        });
        await Future<void>.delayed(Duration.zero);

        expect(seen.whereType<PromptRaised>(), hasLength(1));
        expect(seen.whereType<PromptExpired>().single.id.value, 'r1');
      },
    );

    test('answering a withdrawn approval is refused, not sent', () async {
      final sub = rig.backend.events(handle).listen((_) {});
      addTearDown(sub.cancel);
      rig.transport.event('exec.approval.requested', {
        'sessionKey': 's1',
        'id': 'r2',
        'command': 'ls',
      });
      await Future<void>.delayed(Duration.zero);
      rig.transport.event('exec.approval.resolved', {
        'sessionKey': 's1',
        'id': 'r2',
      });
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        rig.backend.respond(const PromptId('r2'), const PromptAnswer('allow')),
        throwsA(
          isA<AgentException>().having(
            (e) => e.failure,
            'failure',
            AgentFailure.notFound,
          ),
        ),
      );
    });
  });

  test('the set of remembered sends does not grow forever', () async {
    final rig = await _Rig.connected();
    addTearDown(rig.dispose);
    final handle = await rig.open('s1');

    // A client meant to stay open for days cannot keep every key it ever
    // sent. The echo arrives within a turn, so the cap is far above any
    // plausible delay — but it is a cap.
    for (var i = 0; i < 260; i++) {
      final sending = rig.backend.send(handle, 'm$i', clientId: 'k$i');
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('sessions.send', const {});
      await sending;
    }

    final seen = <AgentEvent>[];
    final sub = rig.backend.events(handle).listen(seen.add);
    addTearDown(sub.cancel);

    // The most recent is still recognised as ours and dropped.
    rig.transport.event('session.message', {
      'sessionKey': 's1',
      'message': {
        'role': 'user',
        'content': 'm259',
        'idempotencyKey': 'k259:user',
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(seen.whereType<MessageAppended>(), isEmpty);
  });

  group('the session index', () {
    test('a session nobody opened still reaches the sidebar', () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      final seen = <AgentSession>[];
      final sub = rig.backend.sessionUpdates.listen(seen.add);
      addTearDown(sub.cancel);

      // Nothing is open. The per-session routing drops this, which is exactly
      // the case a live index exists for: a conversation started on a phone.
      rig.transport.event('sessions.changed', {
        'sessionKey': 'agent:main:ios-9f2',
        'displayName': 'from the phone',
        'lastMessagePreview': 'on my way',
        'origin': {'provider': 'ios'},
        'hasActiveRun': true,
      });
      await Future<void>.delayed(Duration.zero);

      final row = seen.single;
      expect(row.id, 'agent:main:ios-9f2');
      expect(row.label, 'from the phone');
      expect(row.preview, 'on my way');
      expect(row.source, 'ios');
      expect(row.running, isTrue);
    });

    test('an open session reports on both streams', () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);
      final handle = await rig.open('s1');

      final rows = <AgentSession>[];
      final events = <AgentEvent>[];
      final a = rig.backend.sessionUpdates.listen(rows.add);
      final b = rig.backend.events(handle).listen(events.add);
      addTearDown(a.cancel);
      addTearDown(b.cancel);

      rig.transport.event('sessions.changed', {
        'sessionKey': 's1',
        'displayName': 'renamed',
      });
      await Future<void>.delayed(Duration.zero);

      // The index draws the sidebar and the event stream draws the header.
      // One frame, two places that need it.
      expect(rows.single.label, 'renamed');
      expect(
        events.whereType<SessionChanged>().single.session.title,
        'renamed',
      );
    });
  });

  group('the end of a turn', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connected();
      handle = await rig.open('s1');
    });

    tearDown(() => rig.dispose());

    Future<List<AgentEvent>> collect(Map<String, dynamic> payload) async {
      final seen = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(seen.add);
      addTearDown(sub.cancel);
      rig.transport.event('chat', {'sessionKey': 's1', ...payload});
      await Future<void>.delayed(Duration.zero);
      return seen;
    }

    test('state:final with a clean stopReason completes the turn', () async {
      final seen = await collect({'state': 'final', 'stopReason': 'stop'});
      final finished = seen.whereType<TurnFinished>().single;
      expect(finished.reason, FinishReason.completed);
      expect(finished.detail, isEmpty);
    });

    test('an abort is reported as interrupted, not completed', () async {
      final seen = await collect({'state': 'final', 'stopReason': 'abort'});
      expect(
        seen.whereType<TurnFinished>().single.reason,
        FinishReason.interrupted,
        reason:
            'a turn cut short and one that finished look identical '
            'unless the reason survives',
      );
    });

    test(
      'an unrecognised stopReason is a failure carrying its own word',
      () async {
        final seen = await collect({
          'state': 'final',
          'stopReason': 'max_tokens',
        });
        final finished = seen.whereType<TurnFinished>().single;
        expect(finished.reason, FinishReason.failed);
        expect(finished.detail, 'max_tokens');
      },
    );

    test(
      'the signals an earlier draft waited for do not end anything',
      () async {
        final seen = <AgentEvent>[];
        final sub = rig.backend.events(handle).listen(seen.add);
        addTearDown(sub.cancel);

        // None of these exist on the wire. Waiting for one hangs in a way
        // indistinguishable from an agent that has stopped responding.
        rig.transport.event('chat.done', {'sessionKey': 's1'});
        rig.transport.event('message.complete', {'sessionKey': 's1'});
        await Future<void>.delayed(Duration.zero);

        expect(seen.whereType<TurnFinished>(), isEmpty);
      },
    );

    test('sessions.changed phase:start opens the turn', () async {
      final seen = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(seen.add);
      addTearDown(sub.cancel);

      rig.transport.event('sessions.changed', {
        'sessionKey': 's1',
        'phase': 'start',
        'status': 'running',
      });
      await Future<void>.delayed(Duration.zero);

      expect(seen.whereType<TurnStarted>(), hasLength(1));
    });
  });

  group('a stated replacement', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connected();
      handle = await rig.open('s1');
    });

    tearDown(() => rig.dispose());

    test('replace=true is a correction, not a continuation', () async {
      final seen = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(seen.add);
      addTearDown(sub.cancel);

      rig.transport.event('chat', {
        'sessionKey': 's1',
        'deltaText': 'a wrong answer',
      });
      await Future<void>.delayed(Duration.zero);
      // Protocol v4's own word for it. A correction that the server states is
      // better than one this client infers by comparing strings — the
      // inference cannot tell a replacement from a snapshot that merely
      // arrived early.
      rig.transport.event('chat', {
        'sessionKey': 's1',
        'deltaText': 'the right one',
        'replace': true,
      });
      await Future<void>.delayed(Duration.zero);

      expect(seen.whereType<TextDelta>().single.text, 'a wrong answer');
      expect(seen.whereType<TextReset>().single.text, 'the right one');
    });

    test('a later snapshot agrees with the replacement', () async {
      final seen = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(seen.add);
      addTearDown(sub.cancel);

      rig.transport.event('chat', {'sessionKey': 's1', 'deltaText': 'first'});
      await Future<void>.delayed(Duration.zero);
      rig.transport.event('chat', {
        'sessionKey': 's1',
        'deltaText': 'second',
        'replace': true,
      });
      await Future<void>.delayed(Duration.zero);
      // The replacement reset the accumulator, so the cumulative snapshot
      // that follows it must not read as a second disagreement.
      rig.transport.event('chat', {'sessionKey': 's1', 'message': 'second'});
      await Future<void>.delayed(Duration.zero);

      expect(seen.whereType<TextReset>(), hasLength(1));
    });
  });

  group('snapshot reconciliation', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connected();
      handle = await rig.open('s1');
    });

    tearDown(() => rig.dispose());

    test(
      'an agreeing snapshot after matching deltas emits no TextReset',
      () async {
        final events = <AgentEvent>[];
        final sub = rig.backend.events(handle).listen(events.add);
        addTearDown(sub.cancel);

        rig.transport.event('chat', {'sessionKey': 's1', 'deltaText': 'Hel'});
        await Future<void>.delayed(Duration.zero);
        rig.transport.event('chat', {'sessionKey': 's1', 'deltaText': 'lo'});
        await Future<void>.delayed(Duration.zero);
        rig.transport.event('chat', {'sessionKey': 's1', 'message': 'Hello'});
        await Future<void>.delayed(Duration.zero);

        expect(
          events.whereType<TextReset>(),
          isEmpty,
          reason: 'the snapshot agrees with what the deltas already built',
        );
      },
    );

    test('a notice carrying `text` is not mistaken for a snapshot', () async {
      final seen = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(seen.add);
      addTearDown(sub.cancel);

      rig.transport.event('chat', {'sessionKey': 's1', 'deltaText': 'Hello'});
      // `text` is the most generic field on the wire. Reconciling against it
      // would disagree with the answer and wipe the transcript with something
      // that was never part of the reply.
      rig.transport.event('notice', {
        'sessionKey': 's1',
        'text': 'reconnected',
      });
      await Future<void>.delayed(Duration.zero);

      expect(seen.whereType<TextReset>(), isEmpty);
      expect(seen.whereType<BackendNotice>().single.text, 'reconnected');
    });

    test('a disagreeing snapshot emits exactly one TextReset', () async {
      final events = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(events.add);
      addTearDown(sub.cancel);

      rig.transport.event('chat', {'sessionKey': 's1', 'deltaText': 'Hel'});
      await Future<void>.delayed(Duration.zero);
      rig.transport.event('chat', {'sessionKey': 's1', 'message': 'Goodbye'});
      await Future<void>.delayed(Duration.zero);

      final resets = events.whereType<TextReset>().toList();
      expect(resets, hasLength(1));
      expect(resets.single.text, 'Goodbye');
    });

    test(
      'a snapshot that is a prefix extension is not a disagreement',
      () async {
        final events = <AgentEvent>[];
        final sub = rig.backend.events(handle).listen(events.add);
        addTearDown(sub.cancel);

        rig.transport.event('chat', {'sessionKey': 's1', 'deltaText': 'Hel'});
        await Future<void>.delayed(Duration.zero);
        // The snapshot arrived ahead of the delta that completes it — not a
        // correction, just an early look at where the text is headed.
        rig.transport.event('chat', {'sessionKey': 's1', 'message': 'Hello'});
        await Future<void>.delayed(Duration.zero);

        expect(events.whereType<TextReset>(), isEmpty);
      },
    );
  });

  test(
    'opened() reports a session with no turn claimed to be running',
    () async {
      final rig = await _Rig.connected();
      final handle = await rig.open('s1');
      addTearDown(rig.dispose);

      final opened = await rig.backend.opened(handle);
      expect(opened.session.id, 's1');
      // Not a claim that nothing is running — the absence of one. Subscribing
      // is acknowledged, not answered with a state snapshot.
      expect(opened.inflight, isNull);
      expect(opened.queuedPrompt, isEmpty);
    },
  );

  test(
    'a session row reads a title, a preview and where it came from',
    () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      final listing = rig.backend.sessions(limit: 10);
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('sessions.list', {
        'sessions': [
          {
            'key': 'agent:main:main',
            'derivedTitle': 'what model are you',
            'lastMessagePreview': 'I am glm-5.',
            'origin': {'provider': 'webchat'},
            'hasActiveRun': true,
          },
        ],
      });

      final session = (await listing).single;
      // Never the key. `agent:main:dashboard:9d1628ad-…` is a routing address
      // and identifies nothing to a reader.
      expect(session.label, 'what model are you');
      expect(session.preview, 'I am glm-5.');
      expect(session.source, 'webchat');
      expect(session.running, isTrue);
      // The list carries no message count at all, and a zero would read as a
      // conversation with nothing in it rather than one nobody counted.
      expect(session.messageCount, 0);
    },
  );

  test('an opened session knows what it is called', () async {
    final rig = await _Rig.connected();
    addTearDown(rig.dispose);

    final handle = await rig.open('s1');
    final opened = await rig.backend.opened(handle);

    // Subscribing is acknowledged, not answered with a snapshot, so a session
    // opened directly — from a preset, or before the sidebar has listed
    // anything — would otherwise show its routing address as a heading.
    expect(opened.session.title, 'what model are you');
    expect(opened.session.id, 's1');
  });

  test('history() reads chat.history, whose parameter is sessionKey', () async {
    final rig = await _Rig.connected();
    addTearDown(rig.dispose);

    final handle = await rig.open('s1');

    final reading = rig.backend.history(handle);
    await Future<void>.delayed(Duration.zero);
    // `sessionKey` here and `key` on every sessions.* method. The gateway's
    // own inconsistency, and only its schema says which is which.
    expect(
      (rig.transport.lastOf('chat.history')!['params'] as Map)['sessionKey'],
      's1',
    );
    rig.transport.reply('chat.history', {
      'messages': [
        {'role': 'user', 'text': 'hello'},
        {'role': 'assistant', 'text': 'hi'},
      ],
    });

    final history = await reading;
    expect(history.map((m) => m.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);
    expect(
      rig.backend.supports(Capability.history),
      isTrue,
      reason:
          'this was held false while it was an open question, and the '
          'gateway turned out to have chat.history all along',
    );
  });

  group('supports()', () {
    /// Everything a chat-scoped device — `read` + `write` + `approvals`, the
    /// scopes this client asks for — can actually do.
    const chatScoped = {
      Capability.history,
      Capability.approvals,
      Capability.toolCalls,
      Capability.fileAttach,
      Capability.imageAttach,
      Capability.sessionBranching,
      Capability.channels,
      Capability.skills,
      Capability.serverConfig,
      Capability.usageReporting,
      Capability.backgroundProcesses,
      // `cron.list` is read. `cronEditing` is not here: every mutation of the
      // schedule — add, update, remove, run — is `operator.admin`.
      Capability.cron,
      // `agents.files.list` and `agents.files.get` are read; writing them is
      // admin, which is why memoryWrite is absent from this set.
      Capability.memoryRead,
    };

    test('names only what these scopes can actually reach', () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      for (final capability in Capability.values) {
        expect(
          rig.backend.supports(capability),
          chatScoped.contains(capability),
          reason:
              '${capability.name} — a newly added capability stays false '
              'until the gateway is shown to serve it *to these scopes*',
        );
      }
    });

    test(
      'modelSwitching is admin-only, and this client is not admin',
      () async {
        // The bug this pins: `sessions.patch` is scoped `dynamic`, and the rule
        // behind that word is an allowlist of fields a write-scoped operator
        // may set — key, agentId, label, category, pinned, archived, unread.
        // `model` is not in it. Declaring the capability unconditionally built
        // a picker that listed every model correctly and failed on the tap.
        final chat = await _Rig.connected();
        addTearDown(chat.dispose);
        expect(
          chat.backend.supports(Capability.modelSwitching),
          isFalse,
          reason: 'the picker must be absent rather than present and refused',
        );

        final admin = await _Rig.connected(
          grantedScopes: [...ClawGateway.chatScopes, 'operator.admin'],
        );
        addTearDown(admin.dispose);
        expect(
          admin.backend.supports(Capability.modelSwitching),
          isTrue,
          reason: 'a device an operator paired with admin really can switch it',
        );
      },
    );

    test(
      'a device approved with admin but asked only for chatScopes is not admin',
      () async {
        // The live gateway's actual contract: the hello reports what the
        // device *holds* — a superset — while each RPC is authorized against
        // what the session *asked for*. A client that trusted the hello would
        // build a memory-write surface that the server then refuses. The
        // adapter must answer from the intersection, not from the device.
        final rig = await _Rig.connected(
          requestedScopes: ClawGateway.chatScopes,
          grantedScopes: [...ClawGateway.chatScopes, 'operator.admin'],
        );
        addTearDown(rig.dispose);

        expect(rig.backend.supports(Capability.memoryRead), isTrue);
        expect(
          rig.backend.supports(Capability.memoryWrite),
          isFalse,
          reason:
              'the write would be refused — the session never asked for admin',
        );
        expect(
          rig.backend.supports(Capability.modelSwitching),
          isFalse,
          reason: 'same story: admin exists on the device, not in this session',
        );
      },
    );

    test('a device granted less than it asked for gets less', () async {
      // Pairing approves a *subset*. A client that trusted its own request
      // would offer everything it wanted rather than everything it got.
      final rig = await _Rig.connected(
        requestedScopes: ClawGateway.chatScopes,
        grantedScopes: const ['operator.read'],
      );
      addTearDown(rig.dispose);

      expect(rig.backend.supports(Capability.history), isTrue);
      expect(
        rig.backend.supports(Capability.fileAttach),
        isFalse,
        reason: 'sending needs operator.write, which was not granted',
      );
      expect(
        rig.backend.supports(Capability.approvals),
        isFalse,
        reason: 'answering an approval needs operator.approvals',
      );
      expect(
        rig.backend.supports(Capability.backgroundProcesses),
        isFalse,
        reason: 'a task list whose stop button cannot stop is not the surface',
      );
    });

    test('write implies read, and admin implies everything', () async {
      // Both implications are the gateway authorizer's own, not conveniences.
      final rig = await _Rig.connected(
        requestedScopes: ClawGateway.chatScopes,
        grantedScopes: const ['operator.write'],
      );
      addTearDown(rig.dispose);
      expect(rig.backend.supports(Capability.history), isTrue);

      final admin = await _Rig.connected(
        requestedScopes: [...ClawGateway.chatScopes, 'operator.admin'],
        grantedScopes: const ['operator.admin'],
      );
      addTearDown(admin.dispose);
      for (final capability in {...chatScoped, Capability.modelSwitching}) {
        expect(
          admin.backend.supports(capability),
          isTrue,
          reason: capability.name,
        );
      }
      // Still false for the things that are simply absent from this gateway.
      expect(
        admin.backend.supports(Capability.learning),
        isFalse,
        reason:
            '`doctor.memory.*` probes the search index\'s health, which '
            'is not the question "what has it learned"',
      );
    });
  });

  group('send()', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connected();
      handle = await rig.open('s1');
    });

    tearDown(() => rig.dispose());

    test('carries clientId as the idempotency key', () async {
      final sending = rig.backend.send(handle, 'hi', clientId: 'ck-1');
      await Future<void>.delayed(Duration.zero);
      final frame = rig.transport.lastOf('sessions.send');
      expect(frame, isNotNull);
      expect((frame!['params'] as Map)['idempotencyKey'], 'ck-1');
      rig.transport.reply('sessions.send', const {});
      await sending;
    });

    test('an attachment travels as base64 beside the message', () async {
      final sending = rig.backend.send(
        handle,
        'look at this',
        clientId: 'ck-2',
        attachments: [
          Attachment(
            name: 'shot.png',
            bytes: Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/png',
          ),
        ],
      );
      await Future<void>.delayed(Duration.zero);

      final params = rig.transport.lastOf('sessions.send')!['params'] as Map;
      final sent = (params['attachments'] as List).single as Map;
      // The schema types an entry as unknown — the one thing about this
      // method its contract does not pin down — so the shape comes from the
      // gateway's own normaliser: `content` is canonical base64 and the only
      // required field.
      expect(sent['fileName'], 'shot.png');
      expect(sent['mimeType'], 'image/png');
      expect(sent['content'], base64Encode(const [1, 2, 3]));

      rig.transport.reply('sessions.send', const {});
      await sending;
    });
  });

  group('error translation', () {
    test('a retryable error becomes transient with retryAfter', () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      final opening = rig.backend.open('s1');
      await Future<void>.delayed(Duration.zero);
      rig.transport.replyError('sessions.subscribe', {
        'code': 'RATE_LIMITED',
        'message': 'slow down',
        'retryable': true,
        'retryAfterMs': 1500,
      });

      await expectLater(
        opening,
        throwsA(
          isA<AgentException>()
              .having((e) => e.failure, 'failure', AgentFailure.transient)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(milliseconds: 1500),
              ),
        ),
        reason: 'nothing above the adapter may see a raw ClawRpcException',
      );
    });

    test('NOT_PAIRED from a normal RPC becomes notPaired', () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      final opening = rig.backend.open('s1');
      await Future<void>.delayed(Duration.zero);
      rig.transport.replyError('sessions.subscribe', {
        'code': 'NOT_PAIRED',
        'message': 'device identity required',
      });

      await expectLater(
        opening,
        throwsA(
          isA<AgentException>()
              .having((e) => e.failure, 'failure', AgentFailure.notPaired)
              .having((e) => e.needsApproval, 'needsApproval', isTrue),
        ),
      );
    });
  });

  group('respond()', () {
    test('an id that was never raised throws notFound', () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      expect(
        () => rig.backend.respond(
          const PromptId('ghost'),
          const PromptAnswer('x'),
        ),
        throwsA(
          isA<AgentException>().having(
            (e) => e.failure,
            'failure',
            AgentFailure.notFound,
          ),
        ),
      );
    });

    test(
      'after an approval event, respond sends the choice verbatim',
      () async {
        final rig = await _Rig.connected();
        addTearDown(rig.dispose);

        final handle = await rig.open('s1');

        final sub = rig.backend.events(handle).listen((_) {});
        addTearDown(sub.cancel);
        rig.transport.event('exec.approval.request', {
          'sessionKey': 's1',
          'requestId': 'r1',
          'command': 'rm -rf /',
          'choices': ['once', 'deny'],
        });
        await Future<void>.delayed(Duration.zero);

        final answering = rig.backend.respond(
          const PromptId('r1'),
          const PromptAnswer('once'),
        );
        await Future<void>.delayed(Duration.zero);
        final frame = rig.transport.lastOf('exec.approval.resolve');
        expect(frame, isNotNull);
        expect(
          (frame!['params'] as Map)['decision'],
          'once',
          reason: 'the server\'s own choice string, not an invented one',
        );
        rig.transport.reply('exec.approval.resolve', const {});
        await answering;
      },
    );
  });

  group('skills()', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connected();
      handle = await rig.open('s1');
    });
    tearDown(() => rig.dispose());

    /// Answers all three inventory reads. They go out concurrently, so all
    /// three frames are on the wire before any reply is needed.
    void answerAll({
      List<Object> skills = const [],
      List<Object> groups = const [],
      List<Object> commands = const [],
    }) {
      rig.transport.reply('skills.status', {'skills': skills});
      rig.transport.reply('tools.effective', {
        'agentId': 'main',
        'profile': 'default',
        'groups': groups,
      });
      rig.transport.reply('commands.list', {'commands': commands});
    }

    test('reads skills, effective tools and commands', () async {
      final reading = rig.backend.skills(handle);
      await Future<void>.delayed(Duration.zero);

      // `tools.effective` is the one with a required parameter, and it is the
      // session key rather than the id — the same distinction that gets a
      // well-formed request rejected everywhere else in this backend.
      expect(rig.transport.lastOf('tools.effective')!['params'], {
        'sessionKey': 's1',
      });

      answerAll(
        skills: [
          {
            'name': 'gh-review',
            'description': 'reviews a pull request',
            'eligible': true,
            'bundled': false,
            'source': 'workspace',
          },
        ],
        groups: [
          {
            'id': 'core',
            'label': 'Core',
            'source': 'core',
            'tools': [
              {
                'id': 'bash',
                'label': 'bash',
                'description': 'runs a command',
                'rawDescription': 'runs a command',
                'source': 'core',
                'risk': 'high',
              },
            ],
          },
          {
            'id': 'plugin',
            'label': 'Browser',
            'source': 'plugin',
            'tools': [
              {
                'id': 'browser_open',
                'label': 'browser_open',
                'description': '',
                'rawDescription': '',
                'source': 'plugin',
              },
            ],
          },
        ],
        commands: [
          {
            'name': 'compact',
            'description': 'compacts the transcript',
            'source': 'native',
            'scope': 'all',
            'acceptsArgs': false,
          },
        ],
      );
      final inventory = await reading;

      expect(inventory.map((s) => (s.name, s.group)).toList(), [
        ('gh-review', SkillGroup.skill),
        ('bash', SkillGroup.tool),
        // A plugin's tools are the only way this gateway reports a plugin.
        ('browser_open', SkillGroup.plugin),
        ('/compact', SkillGroup.command),
      ]);
      expect(
        inventory.first.enabled,
        isTrue,
        reason: 'eligible is the verdict that folds in every other flag',
      );
      expect(inventory[1].detail, 'Core · high risk');
    });

    test(
      'a skill that will not run says why, in the server\'s words',
      () async {
        // The verdict alone makes a greyed row a mystery. `skills.status`
        // reports the evidence too, and it is the only useful half.
        final reading = rig.backend.skills(handle);
        await Future<void>.delayed(Duration.zero);
        answerAll(
          skills: [
            {
              'name': 'needs-gh',
              'eligible': false,
              'disabled': false,
              'missing': {
                'os': <String>[],
                'bin': ['gh'],
              },
            },
            {'name': 'switched-off', 'eligible': false, 'disabled': true},
          ],
        );
        final inventory = await reading;

        expect(inventory.map((s) => s.enabled), everyElement(isFalse));
        expect(inventory.first.detail, 'missing bin: gh');
        expect(inventory[1].detail, 'disabled in config');
      },
    );

    test('one refused read costs its group, not the panel', () async {
      // The three methods are separately scoped in the gateway's descriptor
      // table. A build that tightens one of them should not empty the panel.
      final reading = rig.backend.skills(handle);
      await Future<void>.delayed(Duration.zero);
      rig.transport.replyError('skills.status', {
        'code': 'FORBIDDEN',
        'message': 'operator.admin required',
      });
      rig.transport.reply('tools.effective', {
        'agentId': 'main',
        'profile': 'default',
        'groups': [
          {
            'id': 'core',
            'label': 'Core',
            'source': 'core',
            'tools': [
              {
                'id': 'bash',
                'label': 'bash',
                'description': '',
                'rawDescription': '',
                'source': 'core',
              },
            ],
          },
        ],
      });
      rig.transport.reply('commands.list', {'commands': <Object>[]});

      final inventory = await reading;
      expect(inventory.map((s) => s.name), ['bash']);
    });
  });

  group('skillLibrary()', () {
    late _Rig rig;

    setUp(() async {
      rig = await _Rig.connected();
    });
    tearDown(() => rig.dispose());

    Map<String, Object> skill(Map<String, Object> fields) => {
      'name': 'tavily',
      'skillKey': 'tavily',
      'description': 'web search',
      'eligible': true,
      'bundled': false,
      'source': 'openclaw-workspace',
      'filePath': '/workspace/skills/tavily/SKILL.md',
      ...fields,
    };

    test('reads status and the registry copy for each skill', () async {
      final reading = rig.backend.skillLibrary();
      await Future<void>.delayed(Duration.zero);
      expect(
        rig.transport.lastOf('skills.status')!['params'],
        const <String, dynamic>{},
      );
      rig.transport.reply('skills.status', {
        'skills': [
          skill({
            'name': 'tavily',
            'skillKey': 'tavily',
            'description': 'AI-optimized web search',
          }),
          skill({
            'name': 'exa-search',
            'skillKey': 'exa-search',
            'description': 'search via Exa',
            'eligible': false,
            'disabled': false,
            'missing': {
              'bins': ['node'],
              'env': ['EXA_API_KEY'],
            },
          }),
        ],
      });
      await Future<void>.delayed(Duration.zero);
      rig.transport.replyEach('skills.detail', [
        {
          'skill': {
            'slug': 'tavily',
            'displayName': 'Tavily AI Search',
            'description': '---\nname: tavily\n---\n\nRegistry body.',
          },
        },
        {
          'skill': {
            'slug': 'exa-search',
            'displayName': 'Exa Search',
            'description': '---\nname: exa-search\n---\n\nExa body.',
          },
        },
      ]);
      final entries = await reading;

      expect(entries, hasLength(2));
      final tavily = entries.firstWhere((e) => e.key == 'tavily');
      expect(tavily.backendId, 'openclaw');
      expect(tavily.eligible, isTrue);
      expect(tavily.filePath, '/workspace/skills/tavily/SKILL.md');
      expect(tavily.content, contains('Registry body.'));
      // The verdict alone makes a greyed row a mystery; the evidence is the
      // answer.
      final exa = entries.firstWhere((e) => e.key == 'exa-search');
      expect(exa.eligible, isFalse);
      expect(exa.detail, 'missing bins: node');
      expect(exa.content, isNotNull);
    });

    test(
      'a local-only skill has no registry content, and the row stays',
      () async {
        final reading = rig.backend.skillLibrary();
        await Future<void>.delayed(Duration.zero);
        rig.transport.reply('skills.status', {
          'skills': [
            skill({
              'name': 'trim-cli',
              'skillKey': 'trim-cli',
              'filePath': '/workspace/skills/fnos/SKILL.md',
            }),
          ],
        });
        await Future<void>.delayed(Duration.zero);
        rig.transport.replyError('skills.detail', {
          'code': 'UNAVAILABLE',
          'message': 'ClawHub 404: Skill not found',
        });
        final entries = await reading;

        expect(entries, hasLength(1));
        expect(entries.single.content, isNull);
        expect(entries.single.filePath, '/workspace/skills/fnos/SKILL.md');
      },
    );
  });

  test(
    'serverConfig flattens the redacted snapshot the gateway sends',
    () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      final reading = rig.backend.serverConfig();
      await Future<void>.delayed(Duration.zero);
      expect(
        rig.transport.lastOf('config.get')!['params'],
        const <String, dynamic>{},
        reason: 'the schema is an empty object with additionalProperties false',
      );
      rig.transport.reply('config.get', {
        'gateway': {
          'port': 8765,
          'remote': {'token': '***'},
        },
        'agents': {
          'defaults': {'model': 'anthropic/claude'},
        },
        'version': '2026.7.1',
      });
      final sections = await reading;

      // Loose leaves are gathered rather than dropped, and they come first
      // because a tree that starts three levels deep reads as though the
      // top-level facts are missing.
      expect(sections.first.title, 'General');
      expect(sections.first.rows, contains(('version', '2026.7.1')));

      final gateway = sections.firstWhere((s) => s.title == 'gateway');
      expect(gateway.rows, contains(('port', '8765')));
      expect(
        gateway.rows,
        contains(('remote.token', '***')),
        reason:
            'redaction is the server\'s job and this client must not undo it',
      );
    },
  );

  test('the gateway takes no reload requests from a client', () async {
    // Every reload-shaped method there is operator.admin, and this client
    // pairs with read/write/approvals. Absent beats refused.
    final rig = await _Rig.connected();
    addTearDown(rig.dispose);
    final handle = await rig.open('s1');

    expect(rig.backend.supports(Capability.serverMaintenance), isFalse);
    expect(await rig.backend.reloadTargets(handle), isEmpty);
    await expectLater(
      rig.backend.reloadServer(handle, 'skills'),
      throwsA(isA<AgentException>()),
    );
  });

  test('usage reports spend, and no context window it does not have', () async {
    final rig = await _Rig.connected();
    addTearDown(rig.dispose);
    final handle = await rig.open('s1');

    final reading = rig.backend.usage(handle);
    await Future<void>.delayed(Duration.zero);
    expect(rig.transport.lastOf('sessions.usage')!['params'], {
      'key': 's1',
    }, reason: 'the session key, not the sessionId in the same row');

    rig.transport.reply('sessions.usage', {
      'updatedAt': 1785909648645,
      'startDate': '2026-07-01',
      'endDate': '2026-08-06',
      'sessions': <Object>[],
      'totals': {
        'input': 1200,
        'output': 340,
        'cacheRead': 9000,
        'cacheWrite': 120,
        'totalTokens': 10660,
        'totalCost': 0.0421,
        'missingCostEntries': 0,
      },
    });
    final usage = await reading;

    expect(usage.inputTokens, 1200);
    expect(usage.outputTokens, 340);
    expect(
      usage.totalTokens,
      10660,
      reason:
          'the server\'s own total — cache traffic is most of it, so '
          'input + output would silently disagree with its arithmetic',
    );
    expect(usage.costUsd, closeTo(0.0421, 1e-9));
    expect(
      usage.hasContext,
      isFalse,
      reason:
          'this gateway has no live context figure, and a meter drawn '
          'against nothing reads as plenty left',
    );
    expect(usage.details, contains(('cache read', '9000')));
    expect(
      usage.details.map((d) => d.$1),
      isNot(contains('unpriced entries')),
      reason: 'zero unpriced entries is not a fact worth a row',
    );
  });

  test('tasks are the ledger, and only a live one offers a stop', () async {
    final rig = await _Rig.connected();
    addTearDown(rig.dispose);
    final handle = await rig.open('s1');

    final reading = rig.backend.tasks(handle);
    await Future<void>.delayed(Duration.zero);
    expect(rig.transport.lastOf('tasks.list')!['params'], {'sessionKey': 's1'});

    rig.transport.reply('tasks.list', {
      'tasks': [
        {
          'id': 't-1',
          'kind': 'subagent',
          'runtime': 'embedded',
          'status': 'running',
          'title': 'review the diff',
          'startedAt': 1785909648645,
          'progressSummary': 'reading files',
        },
        {
          'id': 't-2',
          'status': 'succeeded',
          'title': 'earlier run',
          'terminalSummary': 'done',
        },
        {
          'id': 't-3',
          'status': 'some-status-this-client-has-never-seen',
          'title': 'unknown',
        },
      ],
    });
    final tasks = await reading;

    expect(tasks.map((t) => t.id), ['t-1', 't-2', 't-3']);
    expect(tasks.first.canStop, isTrue);
    expect(tasks.first.detail, 'embedded · reading files');
    expect(tasks[1].canStop, isFalse);
    expect(
      tasks[2].canStop,
      isFalse,
      reason:
          'an unrecognised status must read as not stoppable — the cost '
          'of guessing that way is a missing button, not a lying one',
    );

    final stopping = rig.backend.stopTask(handle, 't-1');
    await Future<void>.delayed(Duration.zero);
    expect(rig.transport.lastOf('tasks.cancel')!['params'], {'taskId': 't-1'});
    rig.transport.reply('tasks.cancel', {'found': true, 'cancelled': true});
    await stopping;

    // And there is no stop-everything to build out of list + cancel.
    await expectLater(
      rig.backend.stopAllTasks(),
      throwsA(isA<AgentException>()),
    );
  });

  test('the cron schedule can be read but not written', () async {
    // `cron.list` is `operator.read`; `cron.add`/`update`/`remove`/`run` are
    // all `operator.admin`. A client that could see the schedule and offered
    // a create button would offer one that can only be refused.
    final rig = await _Rig.connected();
    addTearDown(rig.dispose);

    expect(rig.backend.supports(Capability.cron), isTrue);
    expect(rig.backend.supports(Capability.cronEditing), isFalse);

    final reading = rig.backend.jobs();
    await Future<void>.delayed(Duration.zero);
    rig.transport.reply('cron.list', {
      'jobs': [
        {
          'id': 'j-1',
          'name': 'morning-brief',
          'enabled': true,
          'createdAtMs': 1785386219284,
          'updatedAtMs': 1785386219284,
          'schedule': {
            'kind': 'cron',
            'expr': '0 9 * * *',
            'tz': 'Asia/Shanghai',
          },
          'payload': {'kind': 'agentTurn', 'message': 'summarise overnight'},
          'lastRunStatus': 'ok',
          'lastRunAtMs': 1785386219284,
        },
        {
          'id': 'j-2',
          'name': 'heartbeat',
          'enabled': false,
          'createdAtMs': 0,
          'updatedAtMs': 0,
          'schedule': {'kind': 'every', 'everyMs': 1800000},
          'payload': {'kind': 'systemEvent', 'text': 'ping'},
        },
        {
          'id': 'j-3',
          'name': 'cleanup',
          'enabled': true,
          'createdAtMs': 0,
          'updatedAtMs': 0,
          'schedule': {'kind': 'at', 'at': '2026-09-01T00:00:00Z'},
          'payload': {
            'kind': 'command',
            'argv': ['rm', '-rf', '/tmp/x'],
          },
        },
      ],
    });
    final jobs = await reading;

    // Three of the four schedule kinds have no cron expression to give, so
    // the adapter renders rather than pretending they all do.
    expect(jobs.map((j) => j.schedule).toList(), [
      '0 9 * * * (Asia/Shanghai)',
      'every 30m',
      'once, at 2026-09-01T00:00:00Z',
    ]);
    // And a payload is a union too — calling the last two "prompt" would
    // misdescribe them.
    expect(jobs[1].prompt, 'system event: ping');
    expect(jobs[2].prompt, r'$ rm -rf /tmp/x');
    expect(jobs.first.lastRunStatus, 'ok');
    expect(jobs[1].enabled, isFalse);
  });

  test('creating one fills the fields cron.add demands', () async {
    // The schema requires more than the three a caller supplies, and refuses
    // additional properties — so the extras are decisions, made in the
    // adapter and pinned here.
    final rig = await _Rig.connected(
      grantedScopes: [...ClawGateway.chatScopes, 'operator.admin'],
    );
    addTearDown(rig.dispose);
    expect(rig.backend.supports(Capability.cronEditing), isTrue);

    final creating = rig.backend.createJob(
      name: 'morning-brief',
      schedule: '0 9 * * *',
      prompt: 'summarise overnight',
    );
    await Future<void>.delayed(Duration.zero);
    expect(rig.transport.lastOf('cron.add')!['params'], {
      'name': 'morning-brief',
      'schedule': {'kind': 'cron', 'expr': '0 9 * * *'},
      // Its own session, so a 09:00 briefing does not interleave itself into
      // a conversation someone is reading.
      'sessionTarget': 'isolated',
      // The scheduler's pacing rather than forcing the gateway awake.
      'wakeMode': 'next-heartbeat',
      'payload': {'kind': 'agentTurn', 'message': 'summarise overnight'},
    });
    rig.transport.reply('cron.add', {'id': 'j-9'});
    await creating;
  });

  group('memory()', () {
    /// Answers the three calls a memory read makes, in the order it makes
    /// them: the agent list, then the file list for timestamps, then a `get`
    /// per file. The wire settled this — `agents.files.list` does not carry
    /// content, so a `get` each is not an inefficiency to optimise away.
    Future<List<MemoryEntry>> read(
      _Rig rig, {
      required String memory,
      bool memoryMissing = false,
      Map<String, String> persona = const {},
    }) async {
      final reading = rig.backend.memory();
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('agents.list', {
        'agents': [
          {'id': 'main', 'name': 'main'},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('agents.files.list', {
        'agentId': 'main',
        'workspace': '/srv/workspace',
        'files': [
          {
            'name': 'MEMORY.md',
            'path': '/srv/workspace/MEMORY.md',
            'missing': memoryMissing,
            if (!memoryMissing) 'updatedAtMs': 1785382346257,
          },
        ],
      });
      await Future<void>.delayed(Duration.zero);
      // All four gets go out together; answer each by name.
      for (final name in ['MEMORY.md', ...clawPersonaFiles]) {
        final frame = rig.transport.sent.lastWhere(
          (f) =>
              f['method'] == 'agents.files.get' &&
              (f['params'] as Map)['name'] == name,
          orElse: () => const {},
        );
        if (frame.isEmpty) continue;
        final content = name == 'MEMORY.md' ? memory : (persona[name] ?? '');
        rig.transport.push({
          'type': 'res',
          'id': frame['id'],
          'ok': true,
          'payload': {
            'agentId': 'main',
            'workspace': '/srv/workspace',
            'file': {
              'name': name,
              'path': '/srv/workspace/$name',
              'missing': name == 'MEMORY.md' ? memoryMissing : content.isEmpty,
              'content': content,
            },
          },
        });
      }
      await Future<void>.delayed(Duration.zero);
      return reading;
    }

    test('reads MEMORY.md and the persona documents', () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      final entries = await read(
        rig,
        memory: '## Coffee\nblack, never after 3pm\n',
        persona: {
          'USER.md': '# USER.md\n\n- **Name:** Jaden\n\nBuilds a client.\n',
        },
      );

      expect(entries.map((e) => (e.kind, e.label)).toList(), [
        (MemoryKind.fact, 'Coffee'),
        (MemoryKind.persona, 'USER.md'),
      ]);
      // The timestamp comes from `list`, which is the only call that reports
      // one — and it is `updatedAtMs`, never `size`, because size is bytes
      // while the content is UTF-16 and the two disagree by design.
      expect(entries.first.updatedAt, isNotNull);
    });

    test('a missing MEMORY.md is an empty state, not a failure', () async {
      // Exactly what the live gateway returns for a fresh workspace: the file
      // has never been written, `missing: true`, no error.
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      final entries = await read(rig, memory: '', memoryMissing: true);
      expect(entries, isEmpty);
    });

    test('a document still holding its template is not knowledge', () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      final entries = await read(
        rig,
        memory: '',
        memoryMissing: true,
        persona: {
          'USER.md':
              '# USER.md - About Your Human\n\n'
              '_Learn about the person you are helping._\n\n'
              '- **Name:**\n- **Timezone:**\n',
        },
      );
      expect(
        entries,
        isEmpty,
        reason: 'an unfilled form looks like knowledge and is not',
      );
    });

    test('every entry says which agent it came from', () async {
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      final entries = await read(rig, memory: '## A\nx\n');
      expect(
        entries.map((e) => e.origin.backendId).toSet(),
        {'openclaw'},
        reason:
            'the whole point of the bridge is that this stops being '
            'obvious from context',
      );
    });

    test('reading emits only agents.* calls, and no write', () async {
      // The device holds admin. The read path must not exercise it — this is
      // MEMORY_BRIDGE.md R5, asserted rather than left as a convention.
      final rig = await _Rig.connected(
        grantedScopes: [...ClawGateway.chatScopes, 'operator.admin'],
      );
      addTearDown(rig.dispose);

      final before = rig.transport.sent.length;
      await read(rig, memory: '## A\nx\n');
      final methods = rig.transport.sent
          .skip(before)
          .map((f) => '${f['method']}')
          .toSet();

      expect(methods, {'agents.list', 'agents.files.list', 'agents.files.get'});
      expect(methods, isNot(contains('agents.files.set')));
    });
  });

  group('applyMemory', () {
    /// Drives a write: answers the stamp re-read, the get, and the set.
    ///
    /// Returns what was written, so a test can assert on the *file* rather
    /// than on the call — which is the only way to check the splice.
    Future<(MemoryWriteResult, String?)> push(
      _Rig rig,
      List<MemoryChange> changes, {
      required String current,
      int stampMs = 1000,
      bool expectSet = true,
    }) async {
      final pushing = rig.backend.applyMemory(changes);
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('agents.files.list', {
        'agentId': 'main',
        'workspace': '/w',
        'files': [
          {
            'name': 'MEMORY.md',
            'path': '/w/MEMORY.md',
            'missing': false,
            'updatedAtMs': stampMs,
          },
        ],
      });
      await Future<void>.delayed(Duration.zero);
      if (rig.transport.lastOf('agents.files.get') != null) {
        rig.transport.reply('agents.files.get', {
          'agentId': 'main',
          'workspace': '/w',
          'file': {
            'name': 'MEMORY.md',
            'path': '/w/MEMORY.md',
            'missing': false,
            'content': current,
          },
        });
        await Future<void>.delayed(Duration.zero);
      }
      String? written;
      final setFrame = rig.transport.lastOf('agents.files.set');
      if (setFrame != null) {
        written = '${(setFrame['params'] as Map)['content']}';
        rig.transport.reply('agents.files.set', const {});
        await Future<void>.delayed(Duration.zero);
        // The adapter re-reads stamps after writing.
        if (rig.transport.sent
                .where((f) => f['method'] == 'agents.files.list')
                .length >
            1) {
          rig.transport.reply('agents.files.list', {
            'agentId': 'main',
            'workspace': '/w',
            'files': const <Object>[],
          });
          await Future<void>.delayed(Duration.zero);
        }
      }
      expect(setFrame != null, expectSet, reason: 'a set was/was not expected');
      return (await pushing, written);
    }

    Future<_Rig> adminRig() async {
      final rig = await _Rig.connected(
        grantedScopes: [...ClawGateway.chatScopes, 'operator.admin'],
      );
      // agents.list, answered once and cached.
      final reading = rig.backend.memory();
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('agents.list', {
        'agents': [
          {'id': 'main'},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('agents.files.list', {
        'agentId': 'main',
        'workspace': '/w',
        'files': [
          {
            'name': 'MEMORY.md',
            'path': '/w/MEMORY.md',
            'missing': false,
            'updatedAtMs': 1000,
          },
        ],
      });
      await Future<void>.delayed(Duration.zero);
      for (final name in ['MEMORY.md', ...clawPersonaFiles]) {
        final frame = rig.transport.sent.lastWhere(
          (f) =>
              f['method'] == 'agents.files.get' &&
              (f['params'] as Map)['name'] == name,
          orElse: () => const {},
        );
        if (frame.isEmpty) continue;
        rig.transport.push({
          'type': 'res',
          'id': frame['id'],
          'ok': true,
          'payload': {
            'agentId': 'main',
            'workspace': '/w',
            'file': {'name': name, 'path': '/w/$name', 'missing': true},
          },
        });
      }
      await Future<void>.delayed(Duration.zero);
      await reading;
      return rig;
    }

    MemoryEntry entry(String title, String text, {String? native}) =>
        MemoryEntry(
          id: 'caduceus:$title',
          kind: MemoryKind.fact,
          title: title,
          text: text,
          origin: MemoryOrigin(
            backendId: 'openclaw',
            nativeId: native ?? 'MEMORY.md#${title.toLowerCase()}',
          ),
        );

    test('a device without admin is told so, and sends no write', () async {
      // memoryWrite is operator.admin while memoryRead is operator.read, which
      // is why they are two capabilities.
      final rig = await _Rig.connected();
      addTearDown(rig.dispose);

      expect(rig.backend.supports(Capability.memoryWrite), isFalse);
      expect(rig.backend.supportedMemoryOps, isEmpty);

      final result = await rig.backend.applyMemory([
        MemoryChange(MemoryOp.add, entry('Coffee', 'black')),
      ]);
      expect(result.allApplied, isFalse);
      expect(result.refused.single.refusal, MemoryWriteRefusal.unsupported);
      expect(rig.transport.lastOf('agents.files.set'), isNull);
    });

    test('an admin device can add, and every ops is available', () async {
      final rig = await adminRig();
      addTearDown(rig.dispose);

      expect(rig.backend.supportedMemoryOps, MemoryOp.values.toSet());

      final (result, written) = await push(rig, [
        MemoryChange(MemoryOp.add, entry('Coffee', 'Drinks it black.')),
      ], current: '# Memory\n\nhand written by me\n');

      expect(result.allApplied, isTrue);
      expect(written, contains('## Coffee'));
      expect(written, contains('Drinks it black.'));
    });

    test('R1 — the text outside the markers survives byte for byte', () async {
      // The rule that keeps a whole-file `set` from destroying a user's notes.
      const before =
          '# Memory\n\n'
          'a line I typed   \n'
          '\ttabbed line\n';
      final rig = await adminRig();
      addTearDown(rig.dispose);

      final (_, written) = await push(rig, [
        MemoryChange(MemoryOp.add, entry('Coffee', 'black')),
      ], current: before);

      expect(written, startsWith(before));
      expect(written, contains('a line I typed   \n'));
      expect(written, contains('\ttabbed line\n'));
      expect(MemoryBlock.clear(written!).trim(), before.trim());
    });

    test('R2 — a memory outside the block cannot be removed', () async {
      // A line the user or the agent wrote is not the app's to delete, even
      // when it looks exactly like a managed one.
      final rig = await adminRig();
      addTearDown(rig.dispose);

      final (result, _) = await push(
        rig,
        [
          MemoryChange(
            MemoryOp.remove,
            entry('Theirs', 'not ours', native: 'MEMORY.md#theirs'),
          ),
        ],
        current: '## Theirs\n\nnot ours\n',
        expectSet: false,
      );

      expect(result.refused.single.refusal, MemoryWriteRefusal.notOurs);
    });

    test('R2 — updating something outside the block is refused too', () async {
      final rig = await adminRig();
      addTearDown(rig.dispose);

      final (result, _) = await push(
        rig,
        [
          MemoryChange(
            MemoryOp.update,
            entry('Theirs', 'rewritten', native: 'MEMORY.md#theirs'),
          ),
        ],
        current: '## Theirs\n\ntheir words\n',
        expectSet: false,
      );

      expect(result.refused.single.refusal, MemoryWriteRefusal.notOurs);
      expect(result.refused.single.detail, contains('block this app manages'));
    });

    test(
      'R3 — a file that moved since the read refuses the whole write',
      () async {
        // The agent writes its own memory. A person looking at a diff of
        // yesterday's file must not silently overwrite today's.
        final rig = await adminRig();
        addTearDown(rig.dispose);

        final (result, written) = await push(
          rig,
          [MemoryChange(MemoryOp.add, entry('Coffee', 'black'))],
          current: '',
          stampMs: 2000,
          expectSet: false,
        );

        expect(result.applied, isEmpty);
        expect(result.refused.single.refusal, MemoryWriteRefusal.staleRead);
        expect(written, isNull, reason: 'nothing was written at all');
      },
    );

    test('R5 — a whole write emits only agents.files.*', () async {
      // The device holds admin, which authorises far more than this. The
      // memory path must never exercise it.
      final rig = await adminRig();
      addTearDown(rig.dispose);

      final before = rig.transport.sent.length;
      await push(rig, [
        MemoryChange(MemoryOp.add, entry('Coffee', 'black')),
      ], current: '');
      final methods = rig.transport.sent
          .skip(before)
          .map((f) => '${f['method']}')
          .toSet();

      expect(
        methods.difference({
          'agents.files.list',
          'agents.files.get',
          'agents.files.set',
        }),
        isEmpty,
      );
    });

    test('a managed entry can be updated and removed', () async {
      final rig = await adminRig();
      addTearDown(rig.dispose);

      const managed =
          'notes\n\n$memoryBlockBegin\n'
          '## Coffee\n\nblack\n\n'
          '$memoryBlockEnd\n';

      final (updated, afterUpdate) = await push(rig, [
        MemoryChange(MemoryOp.update, entry('Coffee', 'black, no sugar')),
      ], current: managed);
      expect(updated.allApplied, isTrue);
      expect(afterUpdate, contains('black, no sugar'));
      expect(afterUpdate, contains('notes'));
    });

    test('an empty push does nothing and says nothing', () async {
      final rig = await adminRig();
      addTearDown(rig.dispose);

      final result = await rig.backend.applyMemory(const []);
      expect(result.outcomes, isEmpty);
      expect(rig.transport.lastOf('agents.files.set'), isNull);
    });
  });

  group('persona documents', () {
    /// An admin rig whose MEMORY.md and persona files have all been read once,
    /// so the staleness baseline exists.
    Future<_Rig> personaRig({int soulStampMs = 500}) async {
      final rig = await _Rig.connected(
        grantedScopes: [...ClawGateway.chatScopes, 'operator.admin'],
      );
      final reading = rig.backend.memory();
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('agents.list', {
        'agents': [
          {'id': 'main'},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('agents.files.list', {
        'agentId': 'main',
        'workspace': '/w',
        'files': [
          {
            'name': 'SOUL.md',
            'path': '/w/SOUL.md',
            'missing': false,
            'updatedAtMs': soulStampMs,
          },
        ],
      });
      await Future<void>.delayed(Duration.zero);
      for (final name in ['MEMORY.md', ...clawPersonaFiles]) {
        final frame = rig.transport.sent.lastWhere(
          (f) =>
              f['method'] == 'agents.files.get' &&
              (f['params'] as Map)['name'] == name,
          orElse: () => const {},
        );
        if (frame.isEmpty) continue;
        rig.transport.push({
          'type': 'res',
          'id': frame['id'],
          'ok': true,
          'payload': {
            'agentId': 'main',
            'workspace': '/w',
            'file': {
              'name': name,
              'path': '/w/$name',
              'missing': name != 'SOUL.md',
              if (name == 'SOUL.md') 'content': 'Old soul, written by them.',
            },
          },
        });
      }
      await Future<void>.delayed(Duration.zero);
      await reading;
      return rig;
    }

    MemoryChange write(String name, String text) => MemoryChange(
      MemoryOp.update,
      MemoryEntry(
        id: 'openclaw:$name',
        kind: MemoryKind.persona,
        title: name,
        text: text,
        origin: MemoryOrigin(backendId: 'openclaw', nativeId: name),
      ),
    );

    /// Drives a persona push: the stamp re-read, the get, the set.
    Future<(MemoryWriteResult, String?)> pushPersona(
      _Rig rig,
      List<MemoryChange> changes, {
      int stampMs = 500,
      String current = 'Old soul, written by them.',
      bool setFails = false,
    }) async {
      final pushing = rig.backend.applyMemory(changes);
      await Future<void>.delayed(Duration.zero);
      rig.transport.reply('agents.files.list', {
        'agentId': 'main',
        'workspace': '/w',
        'files': [
          {
            'name': 'SOUL.md',
            'path': '/w/SOUL.md',
            'missing': false,
            'updatedAtMs': stampMs,
          },
        ],
      });
      await Future<void>.delayed(Duration.zero);
      if (rig.transport.lastOf('agents.files.get') != null) {
        rig.transport.reply('agents.files.get', {
          'agentId': 'main',
          'workspace': '/w',
          'file': {
            'name': 'SOUL.md',
            'path': '/w/SOUL.md',
            'missing': false,
            'content': current,
          },
        });
        await Future<void>.delayed(Duration.zero);
      }
      String? written;
      final setFrame = rig.transport.lastOf('agents.files.set');
      if (setFrame != null) {
        written = '${(setFrame['params'] as Map)['content']}';
        if (setFails) {
          rig.transport.replyError('agents.files.set', {
            'code': 'FORBIDDEN',
            'message': 'operator.admin required',
          });
          written = null;
        } else {
          rig.transport.reply('agents.files.set', const {});
        }
        await Future<void>.delayed(Duration.zero);
      }
      // The trailing stamp re-read.
      final lists = rig.transport.sent
          .where((f) => f['method'] == 'agents.files.list')
          .length;
      if (lists > 2) {
        rig.transport.reply('agents.files.list', {
          'agentId': 'main',
          'workspace': '/w',
          'files': const <Object>[],
        });
        await Future<void>.delayed(Duration.zero);
      }
      return (await pushing, written);
    }

    test('a whole document is replaced, and what it held is kept', () async {
      // The one destructive operation in the bridge, so the thing it destroys
      // is preserved — an irreversible overwrite is a feature nobody tries
      // twice.
      final rig = await personaRig();
      addTearDown(rig.dispose);

      final backups = <String, String>{};
      rig.backend.onOverwrite = (backend, name, previous) async =>
          backups['$backend/$name'] = previous;

      final (result, written) = await pushPersona(rig, [
        write('SOUL.md', 'New soul, from the other agent.'),
      ]);

      expect(result.allApplied, isTrue);
      expect(written, 'New soul, from the other agent.');
      expect(
        backups['openclaw/SOUL.md'],
        'Old soul, written by them.',
        reason: 'the backup is what was there, not what replaced it',
      );
    });

    test('a refused write leaves the existing backup alone', () async {
      // Recording before the set meant a failed push destroyed the only copy
      // of the version the user actually wanted back.
      final rig = await personaRig();
      addTearDown(rig.dispose);

      var recorded = 0;
      rig.backend.onOverwrite = (backend, name, previous) async => recorded++;

      final (result, _) = await pushPersona(rig, [
        write('SOUL.md', 'Never lands.'),
      ], setFails: true);

      expect(result.applied, isEmpty);
      expect(result.refused.single.refusal, MemoryWriteRefusal.serverRefused);
      expect(
        recorded,
        0,
        reason: 'nothing was overwritten, so nothing backed up',
      );
    });

    test('only the three known documents may be written', () async {
      // agents.files.set would happily write AGENTS.md — the file that tells
      // the agent how to operate.
      final rig = await personaRig();
      addTearDown(rig.dispose);

      final result = await rig.backend.applyMemory([
        MemoryChange(
          MemoryOp.update,
          MemoryEntry(
            id: 'x',
            kind: MemoryKind.persona,
            title: 'AGENTS.md',
            text: 'rewritten instructions',
            origin: const MemoryOrigin(
              backendId: 'openclaw',
              nativeId: 'AGENTS.md',
            ),
          ),
        ),
      ]);

      expect(result.refused.single.refusal, MemoryWriteRefusal.notOurs);
      expect(rig.transport.lastOf('agents.files.set'), isNull);
    });

    test('deleting a persona document is refused outright', () async {
      // Not a memory operation; breaking the agent.
      final rig = await personaRig();
      addTearDown(rig.dispose);

      final result = await rig.backend.applyMemory([
        MemoryChange(
          MemoryOp.remove,
          MemoryEntry(
            id: 'x',
            kind: MemoryKind.persona,
            title: 'SOUL.md',
            text: '',
            origin: const MemoryOrigin(
              backendId: 'openclaw',
              nativeId: 'SOUL.md',
            ),
          ),
        ),
      ]);

      expect(result.refused.single.refusal, MemoryWriteRefusal.unsupported);
      expect(result.refused.single.detail, contains('break the agent'));
      expect(rig.transport.lastOf('agents.files.set'), isNull);
    });

    test('a document that moved since it was read is refused', () async {
      // Persona files move independently of MEMORY.md, so the guard is per
      // file rather than one stamp for the workspace.
      final rig = await personaRig();
      addTearDown(rig.dispose);

      final (result, written) = await pushPersona(rig, [
        write('SOUL.md', 'Would have overwritten a newer soul.'),
      ], stampMs: 999);

      expect(result.refused.single.refusal, MemoryWriteRefusal.staleRead);
      expect(written, isNull);
    });
  });
}
