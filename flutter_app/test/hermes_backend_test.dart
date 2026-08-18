/// [HermesBackend] driven through the real [HermesGateway], socket faked.
///
/// The bugs this file exists to catch live in the translation, not in either
/// side of it: routing an event on the wrong id (the two-id problem), sending
/// an answer to the wrong `*.respond` method, or letting a JSON-RPC code leak
/// past the adapter. Unit tests on `hermes_mapping.dart` alone or on
/// `HermesGateway` alone both pass with any of these bugs present.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:caduceus/backends/hermes_backend.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

/// Copied verbatim from send_flow_test.dart, plus [replyError] for the
/// error-translation tests, which that suite never needed.
class _Socket implements GatewayTransport {
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

  Map<String, dynamic>? lastOf(String method) {
    for (final f in sent.reversed) {
      if (f['method'] == method) return f;
    }
    return null;
  }

  void reply(String method, Object result) {
    final frame = lastOf(method)!;
    _in.add(
      jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], 'result': result}),
    );
  }

  /// Answers every outstanding [method] frame, in order, with [results].
  ///
  /// [reply] alone targets only the *last* frame of a method, which is fine
  /// for the one-at-a-time reads most tests drive and wrong for the
  /// concurrent `learning.detail` fan-out the skill library makes — this is
  /// the per-frame version.
  void replyEach(String method, List<Object> results) {
    final frames = [
      for (final f in sent)
        if (f['method'] == method) f,
    ];
    for (var i = 0; i < frames.length && i < results.length; i++) {
      _in.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': frames[i]['id'],
          'result': results[i],
        }),
      );
    }
  }

  void replyError(String method, int code, String message) {
    final frame = lastOf(method)!;
    _in.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': frame['id'],
        'error': {'code': code, 'message': message},
      }),
    );
  }

  void event(String type, String sessionId, Map<String, dynamic> payload) =>
      _in.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {'type': type, 'session_id': sessionId, 'payload': payload},
        }),
      );
}

/// A connected gateway and backend, with [socket] kept for driving frames.
class _Rig {
  _Rig._(this.socket, this.gateway, this.backend);

  final _Socket socket;
  final HermesGateway gateway;
  final HermesBackend backend;

  static Future<_Rig> connect({String profile = 'default'}) async {
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    final backend = HermesBackend(gateway, profile: profile);
    // Not gateway.connect() as well — HermesBackend.connect() already does
    // that, and calling it twice opens two transports onto the same fake
    // socket, so every frame is delivered twice.
    await backend.connect();
    return _Rig._(socket, gateway, backend);
  }

  Future<void> dispose() async {
    await backend.dispose();
  }
}

void main() {
  test(
    'an event addressed with the durable id is dropped, the live id arrives',
    () async {
      final rig = await _Rig.connect();
      addTearDown(rig.dispose);

      final opening = rig.backend.open('20260101_aaa');
      rig.socket.reply('session.resume', {
        'session_id': 'live99',
        'resumed': '20260101_aaa',
        'running': false,
        'messages': <Object>[],
      });
      final handle = await opening;

      expect(
        handle.sessionId,
        '20260101_aaa',
        reason: 'the durable id is what the caller opened',
      );
      expect(
        handle.wireId,
        'live99',
        reason: 'every later frame must be addressed with the live handle',
      );

      final events = <AgentEvent>[];
      final sub = rig.backend.events(handle).listen(events.add);
      addTearDown(sub.cancel);

      // Addressed with the durable id: must be dropped, not delivered.
      rig.socket.event('message.delta', '20260101_aaa', {'text': 'wrong'});
      await Future<void>.delayed(Duration.zero);
      expect(
        events,
        isEmpty,
        reason:
            'routing on the durable id silently drops every event — this '
            'is the single most important assertion in the file',
      );

      // Addressed with the live handle: must arrive.
      rig.socket.event('message.delta', 'live99', {'text': 'right'});
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect((events.single as TextDelta).text, 'right');
    },
  );

  test('opened carries the model, cwd and a turn already running', () async {
    final rig = await _Rig.connect();
    addTearDown(rig.dispose);

    final opening = rig.backend.open('s1');
    rig.socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': true,
      'info': {'model': 'a-model', 'cwd': '/srv/app', 'branch': 'main'},
      'inflight': {
        'user': 'the question being answered',
        'assistant': 'a partial ',
        'streaming': true,
      },
      'queued': {'user': 'and one waiting behind it'},
      'messages': <Object>[],
    });
    final handle = await opening;

    final opened = await rig.backend.opened(handle);
    expect(opened.session.model, 'a-model');
    expect(opened.session.cwd, '/srv/app');
    expect(opened.session.branch, 'main');
    expect(opened.session.running, isTrue);
    // Joining mid-turn is ordinary — reopening the app while the agent works.
    // Dropping this shows the transcript without the question being answered,
    // and then appends new deltas under nothing.
    expect(opened.inflight?.prompt, 'the question being answered');
    expect(opened.inflight?.answerSoFar, 'a partial ');
    expect(opened.inflight?.streaming, isTrue);
    expect(opened.queuedPrompt, 'and one waiting behind it');

    expect(
      rig.socket.sent.where((f) => f['method'] == 'session.resume'),
      hasLength(1),
      reason: 'the server says this once; there is no method to ask again',
    );
  });

  test(
    'create keys the session by stored_session_id, not the handle',
    () async {
      final rig = await _Rig.connect();
      addTearDown(rig.dispose);

      final creating = rig.backend.create();
      await Future<void>.delayed(Duration.zero);
      rig.socket.reply('session.create', {
        'session_id': 'live7',
        'stored_session_id': '20260803_113947_a6f6ae',
        'info': {'model': 'a-model'},
      });
      final handle = await creating;

      expect(
        handle.sessionId,
        '20260803_113947_a6f6ae',
        reason:
            'the sidebar and session.list speak the durable id; keying on '
            'the handle means a new session matches no row and creating one '
            'looks like nothing happened',
      );
      expect(handle.wireId, 'live7');
      expect((await rig.backend.opened(handle)).session.model, 'a-model');
    },
  );

  test('history returns what open was given, without a wire call', () async {
    final rig = await _Rig.connect();
    addTearDown(rig.dispose);

    final opening = rig.backend.open('s1');
    rig.socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': [
        {'role': 'user', 'text': 'question'},
        {'role': 'assistant', 'text': 'answer'},
      ],
    });
    final handle = await opening;

    final history = await rig.backend.history(handle);
    expect(history, hasLength(2));
    expect(history[0].role, MessageRole.user);
    expect(history[0].text, 'question');
    expect(history[1].role, MessageRole.assistant);
    expect(history[1].text, 'answer');

    expect(
      rig.socket.lastOf('session.history'),
      isNull,
      reason:
          'session.history answers "session not found" for a live session '
          'even right after resume — history must come from what open() '
          'already received',
    );
  });

  group('event mapping', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connect();
      final opening = rig.backend.open('s1');
      rig.socket.reply('session.resume', {
        'session_id': 'live1',
        'resumed': 's1',
        'running': false,
        'messages': <Object>[],
      });
      handle = await opening;
    });

    tearDown(() => rig.dispose());

    Future<AgentEvent> next(String type, Map<String, dynamic> payload) async {
      final future = rig.backend.events(handle).first;
      rig.socket.event(type, 'live1', payload);
      return future;
    }

    test('message.start maps to TurnStarted', () async {
      expect(await next('message.start', const {}), isA<TurnStarted>());
    });

    test('message.delta maps to TextDelta carrying the text', () async {
      final e = await next('message.delta', {'text': 'hi'});
      expect(e, isA<TextDelta>());
      expect((e as TextDelta).text, 'hi');
    });

    test('reasoning.delta maps to ReasoningDelta', () async {
      final e = await next('reasoning.delta', {'text': 'thinking'});
      expect(e, isA<ReasoningDelta>());
      expect((e as ReasoningDelta).text, 'thinking');
    });

    test('reasoning.available maps to ReasoningBlock', () async {
      final e = await next('reasoning.available', {'text': 'block'});
      expect(e, isA<ReasoningBlock>());
      expect((e as ReasoningBlock).text, 'block');
    });

    test('thinking.delta maps to StatusText, not ReasoningDelta', () async {
      // A real bug this client shipped: spinner text folded into the
      // model's private reasoning channel for months.
      final e = await next('thinking.delta', {'text': 'cogitating'});
      expect(e, isA<StatusText>());
      expect(e, isNot(isA<ReasoningDelta>()));
      expect((e as StatusText).text, 'cogitating');
    });

    test('tool.generating maps to ToolPreparing', () async {
      final e = await next('tool.generating', {'name': 'bash'});
      expect(e, isA<ToolPreparing>());
      expect((e as ToolPreparing).toolName, 'bash');
    });

    test('tool.start maps to ToolStarted with the tool id', () async {
      final e = await next('tool.start', {'tool_id': 't1', 'name': 'bash'});
      expect(e, isA<ToolStarted>());
      expect((e as ToolStarted).toolId, 't1');
    });

    test(
      'tool.complete maps to ToolFinished with output and failure',
      () async {
        final e = await next('tool.complete', {
          'tool_id': 't1',
          'name': 'bash',
          'result': {'output': 'ok', 'exit_code': 1},
        });
        expect(e, isA<ToolFinished>());
        final call = (e as ToolFinished).call;
        expect(call.output, 'ok');
        expect(
          call.failed,
          isTrue,
          reason: 'a non-zero exit is a failure even with no error field',
        );
      },
    );

    test('message.complete maps to TurnFinished', () async {
      expect(await next('message.complete', const {}), isA<TurnFinished>());
    });

    test('clarify.request maps to PromptRaised with kind clarify', () async {
      final e = await next('clarify.request', {
        'request_id': 'r1',
        'question': 'which?',
      });
      expect(e, isA<PromptRaised>());
      expect((e as PromptRaised).prompt.kind, AgentPromptKind.clarify);
    });

    test('sudo.request maps to PromptRaised with kind password', () async {
      final e = await next('sudo.request', {
        'request_id': 'r2',
        'prompt': 'password',
      });
      expect(e, isA<PromptRaised>());
      expect((e as PromptRaised).prompt.kind, AgentPromptKind.password);
    });

    test('secret.request maps to PromptRaised with kind secret', () async {
      final e = await next('secret.request', {
        'request_id': 'r3',
        'prompt': 'token',
      });
      expect(e, isA<PromptRaised>());
      expect((e as PromptRaised).prompt.kind, AgentPromptKind.secret);
    });

    test('clarify.expire maps to PromptExpired with the matching id', () async {
      final e = await next('clarify.expire', {'request_id': 'r1'});
      expect(e, isA<PromptExpired>());
      expect((e as PromptExpired).id, const PromptId('r1'));
    });

    test(
      'approval.request maps to PromptRaised carrying the choices verbatim',
      () async {
        final e = await next('approval.request', {
          'command': 'rm -rf /',
          'choices': ['once', 'session', 'always', 'deny'],
        });
        expect(e, isA<PromptRaised>());
        expect((e as PromptRaised).prompt.choices, [
          'once',
          'session',
          'always',
          'deny',
        ]);
      },
    );

    test('an unrecognised event type maps to BackendNotice', () async {
      final e = await next('some.new.event', {'text': 'huh'});
      expect(e, isA<BackendNotice>());
      expect((e as BackendNotice).kind, 'some.new.event');
    });
  });

  group('respond', () {
    late _Rig rig;
    late SessionHandle handle;

    setUp(() async {
      rig = await _Rig.connect();
      final opening = rig.backend.open('s1');
      rig.socket.reply('session.resume', {
        'session_id': 'live1',
        'resumed': 's1',
        'running': false,
        'messages': <Object>[],
      });
      handle = await opening;
    });

    tearDown(() => rig.dispose());

    test('a sudo.request answer is sent as sudo.respond', () async {
      final sub = rig.backend.events(handle).listen((_) {});
      addTearDown(sub.cancel);
      rig.socket.event('sudo.request', 'live1', {'request_id': 'r1'});
      await Future<void>.delayed(Duration.zero);

      final answering = rig.backend.respond(
        const PromptId('r1'),
        const PromptAnswer('pw', secret: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        rig.socket.lastOf('sudo.respond'),
        isNotNull,
        reason: 'must route by the remembered kind, not by guessing',
      );
      expect(rig.socket.lastOf('clarify.respond'), isNull);
      rig.socket.reply('sudo.respond', {'status': 'ok'});
      await answering;
    });

    test('a clarify.request answer is sent as clarify.respond', () async {
      final sub = rig.backend.events(handle).listen((_) {});
      addTearDown(sub.cancel);
      rig.socket.event('clarify.request', 'live1', {'request_id': 'c1'});
      await Future<void>.delayed(Duration.zero);

      final answering = rig.backend.respond(
        const PromptId('c1'),
        const PromptAnswer('yes'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(rig.socket.lastOf('clarify.respond'), isNotNull);
      expect(rig.socket.lastOf('sudo.respond'), isNull);
      rig.socket.reply('clarify.respond', {'status': 'ok'});
      await answering;
    });

    test('a secret.request answer is sent as secret.respond', () async {
      final sub = rig.backend.events(handle).listen((_) {});
      addTearDown(sub.cancel);
      rig.socket.event('secret.request', 'live1', {'request_id': 's1'});
      await Future<void>.delayed(Duration.zero);

      final answering = rig.backend.respond(
        const PromptId('s1'),
        const PromptAnswer('token', secret: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(rig.socket.lastOf('secret.respond'), isNotNull);
      expect(rig.socket.lastOf('clarify.respond'), isNull);
      rig.socket.reply('secret.respond', {'status': 'ok'});
      await answering;
    });

    test(
      'an approval.request answer is addressed with the session id',
      () async {
        final sub = rig.backend.events(handle).listen((_) {});
        addTearDown(sub.cancel);
        rig.socket.event('approval.request', 'live1', {
          'command': 'rm -rf /',
          'choices': ['once', 'deny'],
        });
        await Future<void>.delayed(Duration.zero);

        final answering = rig.backend.respond(
          const PromptId('approval:live1'),
          const PromptAnswer('once'),
        );
        await Future<void>.delayed(Duration.zero);
        final sent = rig.socket.lastOf('approval.respond');
        expect(sent, isNotNull);
        expect(
          sent!['params']['session_id'],
          'live1',
          reason: 'approvals resolve against the session, not a request id',
        );
        rig.socket.reply('approval.respond', {'status': 'ok'});
        await answering;
      },
    );

    test('responding to an id that was never raised throws notFound', () async {
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

    test('responding to an id that already expired throws notFound', () async {
      final sub = rig.backend.events(handle).listen((_) {});
      addTearDown(sub.cancel);
      rig.socket.event('clarify.request', 'live1', {'request_id': 'c2'});
      await Future<void>.delayed(Duration.zero);
      rig.socket.event('clarify.expire', 'live1', {'request_id': 'c2'});
      await Future<void>.delayed(Duration.zero);

      expect(
        () => rig.backend.respond(
          const PromptId('c2'),
          const PromptAnswer('late'),
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
  });

  test(
    'a JSON-RPC error is classified, not rethrown as a wire exception',
    () async {
      final rig = await _Rig.connect();
      addTearDown(rig.dispose);

      final opening = rig.backend.open('missing');
      rig.socket.replyError('session.resume', 4001, 'session not found');

      await expectLater(
        opening,
        throwsA(
          isA<AgentException>()
              .having((e) => e.failure, 'failure', AgentFailure.notFound)
              .having((e) => e.code, 'code', '4001'),
        ),
        reason:
            'nothing above the adapter may see a wire code, and specifically '
            'must never see the raw GatewayRpcException',
      );
    },
  );

  test('connection emits the current value to a late subscriber', () async {
    final rig = await _Rig.connect();
    addTearDown(rig.dispose);

    final first = await rig.backend.connection.first;
    expect(
      first.status,
      AgentStatus.connected,
      reason: 'a late listener must not be left blank until the next change',
    );
  });

  test('GatewayStatus.connected maps to AgentStatus.connected', () async {
    final rig = await _Rig.connect();
    addTearDown(rig.dispose);

    // The mapped status updates via the gateway's connectionState stream,
    // one microtask behind connect() returning.
    await Future<void>.delayed(Duration.zero);
    expect(rig.backend.connectionState.status, AgentStatus.connected);
  });

  test(
    'release closes the event stream, a later event is dropped not thrown',
    () async {
      final rig = await _Rig.connect();
      addTearDown(rig.dispose);

      final opening = rig.backend.open('s1');
      rig.socket.reply('session.resume', {
        'session_id': 'live1',
        'resumed': 's1',
        'running': false,
        'messages': <Object>[],
      });
      final handle = await opening;

      final events = <AgentEvent>[];
      var done = false;
      final sub = rig.backend
          .events(handle)
          .listen(events.add, onDone: () => done = true);
      addTearDown(sub.cancel);

      await rig.backend.release(handle);
      await Future<void>.delayed(Duration.zero);
      expect(
        done,
        isTrue,
        reason: "release must close the session's event stream",
      );

      // Must not throw even though the channel is gone — this asserts by not
      // throwing, since the socket callback is synchronous inside _onFrame.
      rig.socket.event('message.delta', 'live1', {'text': 'late'});
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty, reason: 'a dropped event, not a crash');
    },
  );

  test('a staged file names itself in the prompt', () async {
    // `file.attach` stages the bytes and hands back a `ref_text` — what the
    // user would have pasted. Staging alone tells the model nothing: the file
    // sits in the workspace unmentioned, which is indistinguishable from an
    // attachment that was dropped on the floor.
    final rig = await _Rig.connect();
    addTearDown(rig.dispose);

    final opening = rig.backend.open('s1');
    rig.socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    final handle = await opening;

    final sending = rig.backend.send(
      handle,
      'what does this log say',
      clientId: 'k1',
      attachments: [
        Attachment(
          name: 'run.log',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'text/plain',
        ),
      ],
    );
    await Future<void>.delayed(Duration.zero);

    final attach = rig.socket.lastOf('file.attach');
    expect(attach, isNotNull, reason: 'the bytes have to reach the gateway');
    expect(attach!['params']['name'], 'run.log');
    expect(
      attach['params']['data_url'],
      startsWith('data:text/plain;base64,'),
      reason: 'a bare path names a file the gateway cannot open',
    );

    rig.socket.reply('file.attach', {
      'name': 'run.log',
      'path': '/srv/work/run.log',
      'ref_text': '@file:run.log',
      'uploaded': true,
    });
    await Future<void>.delayed(Duration.zero);

    final submit = rig.socket.lastOf('prompt.submit');
    expect(submit, isNotNull);
    expect(
      submit!['params']['text'],
      'what does this log say\n\n@file:run.log',
      reason: 'the reference travels in the message, not beside it',
    );

    rig.socket.reply('prompt.submit', {'ok': true});
    await sending;
  });

  test('an image needs no reference — it is in the turn already', () async {
    final rig = await _Rig.connect();
    addTearDown(rig.dispose);

    final opening = rig.backend.open('s1');
    rig.socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    final handle = await opening;

    final sending = rig.backend.send(
      handle,
      'what is this',
      clientId: 'k1',
      attachments: [
        Attachment(
          name: 'shot.png',
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'image/png',
        ),
      ],
    );
    await Future<void>.delayed(Duration.zero);

    expect(rig.socket.lastOf('file.attach'), isNull, reason: 'vision path');
    final attach = rig.socket.lastOf('image.attach_bytes');
    expect(attach, isNotNull);
    expect(attach!['params']['filename'], 'shot.png');
    expect(attach['params']['ext'], 'png');

    rig.socket.reply('image.attach_bytes', {'ok': true});
    await Future<void>.delayed(Duration.zero);

    expect(
      rig.socket.lastOf('prompt.submit')!['params']['text'],
      'what is this',
      reason: 'nothing to append; the picture is already in the turn',
    );
    rig.socket.reply('prompt.submit', {'ok': true});
    await sending;
  });

  test('a resumed session resolves @image: directives to download URLs', () async {
    final rig = await _Rig.connect();
    addTearDown(rig.dispose);

    final opening = rig.backend.open('s1');
    rig.socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': [
        {
          'role': 'user',
          'text':
              '你好\n@image:/home/ubuntu/.hermes/images/upload_20260818_000654_1.png',
        },
      ],
    });
    final handle = await opening;
    final messages = await rig.backend.history(handle);

    expect(messages.length, 1);
    expect(messages.single.role, MessageRole.user);
    // User text "你好" is on top, image link is below, in one single string
    expect(
      messages.single.text,
      startsWith('你好\n![upload_20260818_000654_1.png]('),
    );
    expect(
      messages.single.text,
      contains(
        'http://127.0.0.1:9219/api/files/download'
        '?path=%2Fhome%2Fubuntu%2F.hermes%2Fimages%2Fupload_20260818_000654_1.png'
        '&token=t)',
      ),
    );
  });

  test('a resumed session resolves MEDIA: tags in assistant text', () async {
    final rig = await _Rig.connect();
    addTearDown(rig.dispose);

    final opening = rig.backend.open('s1');
    rig.socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': [
        {
          'role': 'assistant',
          'text':
              '• 文件路径: MEDIA:/home/ubuntu/Videos/cyberpunk_metropolis.mp4\n'
              '🖼 视频画面与细节解析\n'
              'MEDIA:/home/ubuntu/images/cyberpunk.png\n'
              '• 核心场景: 赛博朋克',
        },
      ],
    });
    final handle = await opening;
    final messages = await rig.backend.history(handle);

    expect(messages.length, 1);
    expect(messages.single.role, MessageRole.assistant);
    expect(messages.single.text, contains('[🎬 cyberpunk_metropolis.mp4]('));
    expect(messages.single.text, contains('![cyberpunk.png]('));
    expect(
      messages.single.text,
      contains(
        'http://127.0.0.1:9219/api/files/download?path=%2Fhome%2Fubuntu%2Fimages%2Fcyberpunk.png&token=t',
      ),
    );
  });

  test('the inventory survives one group the server will not list', () async {
    // Three independent reads. A server with no plugins answers `plugins.list`
    // with an error rather than an empty list, and a single Future.wait turns
    // that into a panel that will not open at all.
    final rig = await _Rig.connect();
    addTearDown(rig.dispose);

    final opening = rig.backend.open('s1');
    rig.socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    final handle = await opening;

    final reading = rig.backend.skills(handle);
    await Future<void>.delayed(Duration.zero);

    expect(
      (rig.socket.lastOf('tools.list')!['params'] as Map)['session_id'],
      'live1',
      reason: 'which tools are live depends on the session',
    );

    rig.socket.reply('tools.list', {
      'toolsets': [
        {
          'name': 'browser',
          'description': 'drives a browser',
          'enabled': true,
          'tool_count': 12,
        },
      ],
    });
    rig.socket.reply('skills.manage', {
      'skills': {'pdf': 'reads a PDF'},
    });
    rig.socket.replyError('plugins.list', 4004, 'no plugin registry');

    final inventory = await reading;
    expect(inventory.map((s) => (s.name, s.group)).toList(), [
      ('browser', SkillGroup.tool),
      ('pdf', SkillGroup.skill),
    ], reason: 'the refused group is missing; the others are not');
    expect(inventory.first.detail, '12 tools');
  });

  test('reload targets are named, and each runs its own method', () async {
    // Hermes spells its three reloads as three distinct methods, so the
    // target is a label the UI hands straight back rather than an argument
    // the server understands.
    final rig = await _Rig.connect();
    addTearDown(rig.dispose);

    final opening = rig.backend.open('s1');
    rig.socket.reply('session.resume', {
      'session_id': 'live1',
      'resumed': 's1',
      'running': false,
      'messages': <Object>[],
    });
    final handle = await opening;

    expect(await rig.backend.reloadTargets(handle), [
      '.env',
      'MCP servers',
      'skills',
    ]);

    final reloading = rig.backend.reloadServer(handle, 'MCP servers');
    await Future<void>.delayed(Duration.zero);
    final call = rig.socket.lastOf('reload.mcp');
    expect(call, isNotNull);
    expect((call!['params'] as Map)['session_id'], 'live1');
    rig.socket.reply('reload.mcp', {'ok': true});
    await reloading;

    await expectLater(
      rig.backend.reloadServer(handle, 'something else'),
      throwsA(
        isA<AgentException>().having(
          (e) => e.failure,
          'failure',
          AgentFailure.notFound,
        ),
      ),
    );
  });

  group('applyMemory', () {
    MemoryEntry node(String id, String text) => MemoryEntry(
      id: 'hermes:$id',
      kind: MemoryKind.fact,
      text: text,
      origin: MemoryOrigin(backendId: 'hermes', nativeId: id),
    );

    test(
      'add is impossible here, and says so rather than failing late',
      () async {
        // There is no `learning.add`. Declaring it up front is what keeps the UI
        // from offering a push that could only fail.
        final rig = await _Rig.connect();
        addTearDown(rig.dispose);

        expect(rig.backend.supportedMemoryOps, {
          MemoryOp.update,
          MemoryOp.remove,
        });
        expect(rig.backend.supportedMemoryOps, isNot(contains(MemoryOp.add)));

        final result = await rig.backend.applyMemory([
          MemoryChange(MemoryOp.add, node('', 'something new')),
        ]);
        expect(result.refused.single.refusal, MemoryWriteRefusal.unsupported);
        expect(rig.socket.lastOf('learning.edit'), isNull);
      },
    );

    test('a mixed batch applies what it can and reports the rest', () async {
      // The whole reason outcomes are per change. A caller that failed the lot
      // would make the user re-pick the two that were fine.
      final rig = await _Rig.connect();
      addTearDown(rig.dispose);

      final pushing = rig.backend.applyMemory([
        MemoryChange(MemoryOp.update, node('n1', 'rewritten')),
        MemoryChange(MemoryOp.add, node('', 'brand new')),
        MemoryChange(MemoryOp.remove, node('n2', 'gone')),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(
        (rig.socket.lastOf('learning.edit')!['params'] as Map)['id'],
        'n1',
      );
      expect(
        (rig.socket.lastOf('learning.edit')!['params'] as Map)['content'],
        'rewritten',
      );
      rig.socket.reply('learning.edit', {'ok': true});
      await Future<void>.delayed(Duration.zero);

      expect(
        (rig.socket.lastOf('learning.delete')!['params'] as Map)['id'],
        'n2',
      );
      rig.socket.reply('learning.delete', {'ok': true});

      final result = await pushing;
      expect(result.applied, hasLength(2));
      expect(result.refused, hasLength(1));
      expect(result.refused.single.change.op, MemoryOp.add);
    });

    test('one node refusing does not stop the rest', () async {
      final rig = await _Rig.connect();
      addTearDown(rig.dispose);

      final pushing = rig.backend.applyMemory([
        MemoryChange(MemoryOp.update, node('n1', 'first')),
        MemoryChange(MemoryOp.update, node('n2', 'second')),
      ]);
      await Future<void>.delayed(Duration.zero);
      rig.socket.replyError('learning.edit', 4004, 'no such node');
      await Future<void>.delayed(Duration.zero);
      rig.socket.reply('learning.edit', {'ok': true});

      final result = await pushing;
      expect(result.applied, hasLength(1));
      expect(result.refused.single.refusal, MemoryWriteRefusal.serverRefused);
      expect(result.refused.single.detail, contains('no such node'));
    });

    test(
      'a memory with no address on this server is refused, not guessed',
      () async {
        final rig = await _Rig.connect();
        addTearDown(rig.dispose);

        final result = await rig.backend.applyMemory([
          MemoryChange(MemoryOp.update, node('', 'came from somewhere else')),
        ]);
        expect(result.refused.single.refusal, MemoryWriteRefusal.notOurs);
        expect(rig.socket.lastOf('learning.edit'), isNull);
      },
    );
  });

  group('memory()', () {
    Map<String, dynamic> framesWith({
      required List<Map<String, dynamic>> nodes,
    }) => {
      'buckets': [
        {
          'label': '8 Aug 2026',
          'date': '2026-08-08',
          'skills': nodes.where((n) => n['style'] == 'skill').length,
          'memories': nodes.where((n) => n['style'] != 'skill').length,
          'color': '#ffffff',
          'nodes': nodes,
        },
      ],
      'categories': <Object>[],
      'summary': <Object>[],
      'count': nodes.length,
      'axis': {'start': '2026-08-08', 'end': '2026-08-08'},
    };

    test(
      'a memory node keeps its full body, not the truncated label',
      () async {
        final rig = await _Rig.connect();
        addTearDown(rig.dispose);

        final reading = rig.backend.memory();
        rig.socket.reply(
          'learning.frames',
          framesWith(
            nodes: [
              {
                'id': 'memory:profile:6',
                'label': 'User is studying Japane…',
                'fullLabel':
                    'User is studying Japanese and prefers study slides to '
                    'include pitch accents (重音规…',
                'meta': 'profile memory · 1 Aug 2026',
                'style': 'memory',
                'body':
                    'User is studying Japanese and prefers study slides to '
                    'include pitch accents (重音规则), clear translations, and '
                    'etymological root analyses (词源词根分析).',
              },
            ],
          ),
        );
        final entries = await reading;

        expect(entries, hasLength(1));
        expect(entries.single.text, contains('词源词根分析'));
        expect(entries.single.text, isNot(endsWith('…')));
        expect(
          rig.socket.lastOf('learning.detail'),
          isNull,
          reason: 'a memory node needs no detail call',
        );
      },
    );

    test(
      'a skill node has no body and fetches its file through detail',
      () async {
        final rig = await _Rig.connect();
        addTearDown(rig.dispose);

        final reading = rig.backend.memory();
        rig.socket.reply(
          'learning.frames',
          framesWith(
            nodes: [
              {
                'id': 'video-courseware-generator',
                'label': 'video-courseware-generator',
                'fullLabel': 'video-courseware-generator',
                'meta': 'productivity · 6 Jul 2026',
                'style': 'skill',
                'body': '',
              },
            ],
          ),
        );
        // The adapter asks for the file's real content after the frames reply.
        await Future<void>.delayed(Duration.zero);
        rig.socket.reply('learning.detail', {
          'ok': true,
          'kind': 'skill',
          'id': 'video-courseware-generator',
          'label': 'video-courseware-generator',
          'content':
              '---\nname: video-courseware-generator\nversion: 1.0.0\n'
              'description: "Turn videos into courseware."\n---\n\nFull body.',
        });
        final entries = await reading;

        expect(entries, hasLength(1));
        expect(entries.single.kind, MemoryKind.skill);
        expect(
          entries.single.text,
          startsWith('---\nname: video-courseware-generator'),
        );
        expect(entries.single.text, contains('Full body.'));
        expect(rig.socket.lastOf('learning.detail'), isNotNull);
      },
    );

    test(
      'a failed detail keeps the label rather than dropping the row',
      () async {
        final rig = await _Rig.connect();
        addTearDown(rig.dispose);

        final reading = rig.backend.memory();
        rig.socket.reply(
          'learning.frames',
          framesWith(
            nodes: [
              {
                'id': 'some-skill',
                'label': 'some-skill',
                'fullLabel': 'some-skill',
                'meta': 'skills · 8 Aug 2026',
                'style': 'skill',
                'body': '',
              },
            ],
          ),
        );
        await Future<void>.delayed(Duration.zero);
        rig.socket.replyError('learning.detail', 4004, 'no such node');
        final entries = await reading;

        expect(entries, hasLength(1), reason: 'the row must not disappear');
        expect(entries.single.text, 'some-skill');
      },
    );
  });

  group('skillLibrary()', () {
    Map<String, dynamic> framesWith({
      required List<Map<String, dynamic>> nodes,
    }) => {
      'buckets': [
        {
          'label': '8 Aug 2026',
          'date': '2026-08-08',
          'skills': nodes.where((n) => n['style'] == 'skill').length,
          'memories': nodes.where((n) => n['style'] != 'skill').length,
          'color': '#ffffff',
          'nodes': nodes,
        },
      ],
      'categories': <Object>[],
      'summary': <Object>[],
      'count': nodes.length,
      'axis': {'start': '2026-08-08', 'end': '2026-08-08'},
    };

    test('reads skill nodes and fetches each file through detail', () async {
      final rig = await _Rig.connect();
      addTearDown(rig.dispose);

      final reading = rig.backend.skillLibrary();
      rig.socket.reply(
        'learning.frames',
        framesWith(
          nodes: [
            {
              'id': 'video-courseware-generator',
              'label': 'video-courseware-generator',
              'fullLabel': 'video-courseware-generator',
              'meta': 'productivity · 6 Jul 2026',
              'style': 'skill',
              'body': '',
            },
            {
              'id': 'whisper-transcribe',
              'label': 'whisper-transcribe',
              'fullLabel': 'whisper-transcribe',
              'meta': 'skills · 7 Jul 2026',
              'style': 'skill',
              'body': '',
            },
          ],
        ),
      );
      // The adapter asks for each file after the frames reply.
      await Future<void>.delayed(Duration.zero);
      rig.socket.replyEach('learning.detail', [
        {
          'ok': true,
          'kind': 'skill',
          'id': 'video-courseware-generator',
          'label': 'video-courseware-generator',
          'content':
              '---\nname: video-courseware-generator\n'
              'description: "Turn videos into courseware."\n---\n\nFull body.',
        },
        {
          'ok': true,
          'kind': 'skill',
          'id': 'whisper-transcribe',
          'label': 'whisper-transcribe',
          'content':
              '---\nname: whisper-transcribe\ndescription: >\n'
              '  Transcribe audio to text.\n---',
        },
      ]);
      final entries = await reading;

      expect(entries, hasLength(2));
      final generator = entries.firstWhere(
        (e) => e.key == 'video-courseware-generator',
      );
      expect(generator.backendId, 'hermes');
      expect(generator.eligible, isTrue);
      expect(generator.description, 'Turn videos into courseware.');
      expect(generator.content, contains('Full body.'));
      // A folded description marker is not shown as a description.
      final whisper = entries.firstWhere((e) => e.key == 'whisper-transcribe');
      expect(whisper.description, isEmpty);
      expect(whisper.content, isNotNull);
    });

    test('memory nodes are not part of the skill library', () async {
      final rig = await _Rig.connect();
      addTearDown(rig.dispose);

      final reading = rig.backend.skillLibrary();
      rig.socket.reply(
        'learning.frames',
        framesWith(
          nodes: [
            {
              'id': 'a-skill',
              'label': 'a-skill',
              'fullLabel': 'a-skill',
              'meta': 'skills · 8 Aug 2026',
              'style': 'skill',
              'body': '',
            },
            {
              'id': 'memory:profile:1',
              'label': 'A fact about you',
              'fullLabel': 'A fact about you',
              'meta': 'profile memory',
              'style': 'memory',
              'body': 'Likes tea.',
            },
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      rig.socket.replyEach('learning.detail', [
        {
          'ok': true,
          'kind': 'skill',
          'id': 'a-skill',
          'label': 'a-skill',
          'content': '---\nname: a-skill\n---\n\nBody.',
        },
      ]);
      final entries = await reading;

      expect(entries.map((e) => e.key), ['a-skill']);
      expect(rig.socket.lastOf('learning.detail'), isNotNull);
    });
  });
}
