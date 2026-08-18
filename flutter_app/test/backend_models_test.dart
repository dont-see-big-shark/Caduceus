/// Switching a model and forking a transcript, on both backends.
///
/// Both were declared unsupported for OpenClaw not because the gateway cannot
/// do them — it can, through `models.list`, `sessions.patch` and
/// `sessions.create {parentSessionKey, fork}` — but because this client's paths
/// to them went through the Hermes wire. Two agents that both switch models
/// should not need two code paths to do it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backends/claw_backend.dart';
import 'package:caduceus/backends/hermes_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';

class _Claw implements ClawTransport {
  final _in = StreamController<String>.broadcast();
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<String> get inbound => _in.stream;
  @override
  void send(String d) => sent.add(jsonDecode(d) as Map<String, dynamic>);
  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  void push(Object frame) => _in.add(jsonEncode(frame));
  Map<String, dynamic>? lastOf(String m) {
    for (final f in sent.reversed) {
      if (f['method'] == m) return f;
    }
    return null;
  }

  void reply(String m, Map<String, dynamic> payload) => push({
    'type': 'res',
    'id': lastOf(m)!['id'],
    'ok': true,
    'payload': payload,
  });
}

class _Hermes implements GatewayTransport {
  final _in = StreamController<String>.broadcast();
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<String> get inbound => _in.stream;
  @override
  void send(String d) => sent.add(jsonDecode(d) as Map<String, dynamic>);
  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  Map<String, dynamic>? lastOf(String m) {
    for (final f in sent.reversed) {
      if (f['method'] == m) return f;
    }
    return null;
  }

  void reply(String m, Object result) => _in.add(
    jsonEncode({'jsonrpc': '2.0', 'id': lastOf(m)!['id'], 'result': result}),
  );
}

Future<(ClawBackend, _Claw)> _claw() async {
  final transport = _Claw();
  final gateway = ClawGateway(
    ClawEndpoint(url: Uri.parse('wss://example.test/'), token: 't'),
    identity: await ClawDeviceIdentity.generate(),
    connector: (_) async => transport,
  );
  final backend = ClawBackend(gateway);
  final connecting = backend.connect();
  await Future<void>.delayed(Duration.zero);
  transport.push({
    'type': 'event',
    'event': 'connect.challenge',
    'payload': {'nonce': 'n', 'ts': 1},
  });
  await Future<void>.delayed(Duration.zero);
  transport.push({
    'type': 'res',
    'id': '_connect',
    'ok': true,
    'payload': {'protocol': 4},
  });
  await connecting;
  return (backend, transport);
}

Future<SessionHandle> _open(ClawBackend backend, _Claw transport) async {
  final opening = backend.open('s1');
  await Future<void>.delayed(Duration.zero);
  transport.reply('sessions.subscribe', const {});
  await Future<void>.delayed(Duration.zero);
  transport.reply('sessions.messages.subscribe', const {});
  await Future<void>.delayed(Duration.zero);
  transport.reply('sessions.describe', const {
    'session': {'key': 's1'},
  });
  return opening;
}

void main() {
  group('OpenClaw', () {
    test(
      'models() asks for the agent\'s allowed models, not the catalog',
      () async {
        final (backend, transport) = await _claw();
        addTearDown(backend.dispose);
        final handle = await _open(backend, transport);

        final listing = backend.models(handle);
        await Future<void>.delayed(Duration.zero);
        // The default view is the agent's allowlist — exactly the models
        // `sessions.patch` accepts. `view: all` lists 200+ catalog models most
        // of which the gateway refuses with "model not allowed", so a picker
        // built on it offers switches that cannot succeed.
        expect(transport.lastOf('models.list')!['params'], const {});
        transport.reply('models.list', {
          'models': [
            {
              'id': 'glm-latest',
              'name': 'GLM Latest',
              'provider': 'volcengine',
              'contextWindow': 200000,
              'reasoning': true,
            },
            {'id': 'locked', 'provider': 'anthropic', 'available': false},
          ],
        });

        final models = await listing;
        expect(models.first.id, 'glm-latest');
        expect(models.first.label, 'GLM Latest');
        expect(models.first.contextTokens, 200000);
        expect(models.first.reasoning, isTrue);
        // Absent means available; the gateway says so only when it is not.
        expect(models.first.available, isTrue);
        expect(models[1].available, isFalse);
        expect(models[1].label, 'locked', reason: 'the id at least names it');
      },
    );

    test('selectModel patches the session', () async {
      final (backend, transport) = await _claw();
      addTearDown(backend.dispose);
      final handle = await _open(backend, transport);

      final setting = backend.selectModel(handle, 'glm-latest');
      await Future<void>.delayed(Duration.zero);
      expect(transport.lastOf('sessions.patch')!['params'], {
        'key': 's1',
        'model': 'glm-latest',
      });
      transport.reply('sessions.patch', const {});
      await setting;
    });

    test('branch forks the parent and opens what it made', () async {
      final (backend, transport) = await _claw();
      addTearDown(backend.dispose);
      final handle = await _open(backend, transport);

      final branching = backend.branch(handle);
      await Future<void>.delayed(Duration.zero);
      final params = transport.lastOf('sessions.create')!['params'] as Map;
      expect(params['parentSessionKey'], 's1');
      expect(params['fork'], isTrue);
      // No label. The gateway derives one, and labels are unique per gateway —
      // "X (copy)" would collide the second time anyone branched the same
      // conversation.
      expect(params.containsKey('label'), isFalse);
      transport.reply('sessions.create', {'ok': true, 'key': 's1-fork'});

      await Future<void>.delayed(Duration.zero);
      transport.reply('sessions.subscribe', const {});
      await Future<void>.delayed(Duration.zero);
      transport.reply('sessions.messages.subscribe', const {});
      await Future<void>.delayed(Duration.zero);
      transport.reply('sessions.describe', const {
        'session': {'key': 's1-fork'},
      });

      final branched = await branching;
      expect(branched.sessionId, 's1-fork');
    });
  });

  group('Hermes', () {
    test(
      'models() flattens providers and keeps the ones with no key',
      () async {
        final transport = _Hermes();
        final gateway = HermesGateway(
          HermesEndpoint.tunnelled(token: 't', port: 9219),
          connector: (_) async => transport,
        );
        final backend = HermesBackend(gateway);
        await backend.connect();
        addTearDown(backend.dispose);

        final opening = backend.open('s1');
        await Future<void>.delayed(Duration.zero);
        transport.reply('session.resume', {
          'session_id': 'live1',
          'resumed': 's1',
          'running': false,
          'messages': <Object>[],
        });
        final handle = await opening;

        final listing = backend.models(handle);
        await Future<void>.delayed(Duration.zero);
        // Not decorative: `model.options` answers `session not found (4001)`
        // without a session id, the same way `prompt.submit` does.
        expect(
          (transport.lastOf('model.options')!['params'] as Map)['session_id'],
          'live1',
        );
        transport.reply('model.options', {
          'providers': [
            {
              'slug': 'anthropic',
              'models': ['opus', 'sonnet'],
              'authenticated': true,
            },
            {
              'slug': 'openai',
              'models': ['gpt'],
              'authenticated': false,
            },
          ],
        });

        final models = await listing;
        expect(models.map((m) => m.id), ['opus', 'sonnet', 'gpt']);
        expect(models.first.provider, 'anthropic');
        // Listed and unavailable, not dropped: hiding it turns "connect this
        // provider" into a model that does not appear to exist.
        expect(models.last.available, isFalse);
      },
    );
  });
}
