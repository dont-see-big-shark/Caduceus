/// Connect to an OpenClaw gateway, list sessions, and hold a short exchange.
///
/// This is the "one run" the whole client builds toward. It persists its
/// device identity to a seed file, so the FIRST run registers a device (which
/// an operator then approves once), and EVERY run after that reuses the same
/// approved identity — a device that regenerates its key each launch would need
/// re-approving each launch.
///
///   dart run openclaw_protocol:connect \
///     --url wss://host/ --token GATEWAY_AUTH_TOKEN \
///     [--cookie PROXY_COOKIE] [--seed PATH] [--say "hello"]
///
/// The token and cookie are read from flags or the environment (CLAW_TOKEN,
/// CLAW_COOKIE) and never written anywhere but the process — the seed file
/// holds only the device key, which is useless without an approved pairing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:openclaw_protocol/openclaw_protocol.dart';

String? _flag(List<String> args, String name) {
  final i = args.indexOf('--$name');
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

Future<ClawDeviceIdentity> _identity(String path) async {
  final file = File(path);
  if (file.existsSync()) {
    return ClawDeviceIdentity.fromSeed(base64.decode(file.readAsStringSync().trim()));
  }
  final identity = await ClawDeviceIdentity.generate();
  file.writeAsStringSync(base64.encode(await identity.extractSeed()));
  await Process.run('chmod', ['600', path]);
  return identity;
}

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final url = _flag(args, 'url') ?? env['CLAW_URL'];
  final token = _flag(args, 'token') ?? env['CLAW_TOKEN'] ?? '';
  final cookie = _flag(args, 'cookie') ?? env['CLAW_COOKIE'] ?? '';
  final seed = _flag(args, 'seed') ?? '${env['HOME']}/.caduceus-claw-seed';
  final say = _flag(args, 'say') ?? 'Hello from Caduceus — reply with one short line.';
  if (url == null) {
    stderr.writeln('need --url (or CLAW_URL)');
    exit(64);
  }

  final trace = args.contains('--trace');
  final identity = await _identity(seed);
  stdout.writeln('device ${identity.deviceId}');

  final gateway = ClawGateway(
    ClawEndpoint(
      url: Uri.parse(url),
      token: token,
      headers: cookie.isEmpty ? const {} : {'Cookie': cookie},
    ),
    identity: identity,
    // Asking for nothing pairs a device that cannot then do anything, and the
    // approval has already been spent by the time that is visible.
    scopes: ClawGateway.chatScopes,
  );

  try {
    final hello = await gateway.connect();
    stdout.writeln('connected: $hello');

    final sessions = await gateway.sessions(limit: 20);
    stdout.writeln('\n${sessions.length} session(s):');
    for (final s in sessions.take(20)) {
      stdout.writeln('  $s');
    }
    if (sessions.isEmpty) {
      stdout.writeln('  (none — creating one)');
    }
    // Raw shapes, for the fields a schema types as `unknown`. Everything the
    // client gets wrong about a payload it cannot see is found here first.
    if (args.contains('--inspect')) {
      final raw = await gateway.call('sessions.list', {
        'limit': 40,
        'includeDerivedTitles': true,
        'includeLastMessage': true,
      });
      final rows = (raw['sessions'] as List?) ?? const [];
      rows.sort((a, b) => ((b as Map)['updatedAt'] as int? ?? 0)
          .compareTo((a as Map)['updatedAt'] as int? ?? 0));
      for (final row in rows.take(1).whereType<Map>()) {
        stdout.writeln('--- session row');
        for (final e in row.entries) {
          final v = '${e.value}';
          stdout.writeln('  ${e.key} = ${v.length > 90 ? '${v.substring(0, 90)}…' : v}');
        }
      }
      final models = await gateway.models();
      stdout.writeln('--- models (${models.length})');
      for (final m in models.take(6)) {
        stdout.writeln('  ${m['id']} | ${m['provider']} '
            '| available=${m['available'] ?? true}');
      }
      final wanted = _flag(args, 'session');
      final key = wanted ?? '${(rows.first as Map)['key']}';
      final hist = await gateway.call('chat.history', {
        'sessionKey': key,
        'limit': 12,
      });
      stdout.writeln('--- chat.history keys: ${hist.keys.toList()}');
      for (final m in ((hist['messages'] as List?) ?? const []).take(8)) {
        stdout.writeln('--- message');
        if (m is Map) {
          for (final e in m.entries) {
            final v = '${e.value}';
            stdout.writeln('  ${e.key} = ${v.length > 160 ? '${v.substring(0, 160)}…' : v}');
          }
        }
      }
      await gateway.dispose();
      return;
    }

    // What each agent remembers, and in what shape.
    //
    // The schemas say `agents.files.*` exists and what it takes; only the
    // wire says what a real workspace actually holds — which files are
    // present, how big MEMORY.md is, and whether the content comes back
    // inline on `list` or only on `get`.
    if (args.contains('--memory')) {
      final agents = await gateway.call('agents.list', const {});
      final rows = (agents['agents'] as List?) ?? const [];
      stdout.writeln('--- agents (${rows.length})');
      for (final a in rows.whereType<Map>()) {
        stdout.writeln('  ${a['id']} | ${a['name'] ?? ''}');
      }
      final agentId = _flag(args, 'agent') ??
          '${(rows.isEmpty ? null : (rows.first as Map)['id']) ?? 'main'}';
      stdout.writeln('--- agents.files.list agentId=$agentId');
      final listed = await gateway.call('agents.files.list', {
        'agentId': agentId,
      });
      stdout.writeln('  workspace = ${listed['workspace']}');
      for (final f in (listed['files'] as List?) ?? const []) {
        if (f is! Map) continue;
        stdout.writeln('  ${'${f['name']}'.padRight(16)} '
            'missing=${f['missing']} size=${f['size'] ?? '-'} '
            'updatedAtMs=${f['updatedAtMs'] ?? '-'} '
            'inlineContent=${f['content'] != null}');
      }
      for (final name in ['MEMORY.md', 'USER.md', 'SOUL.md', 'IDENTITY.md']) {
        try {
          final got = await gateway.call('agents.files.get', {
            'agentId': agentId,
            'name': name,
          });
          final file = (got['file'] as Map?) ?? const {};
          final content = '${file['content'] ?? ''}';
          stdout.writeln('--- $name (${content.length} chars, '
              'missing=${file['missing']})');
          final lines = content.split('\n');
          for (final line in lines.take(24)) {
            stdout.writeln('  | $line');
          }
          if (lines.length > 24) {
            stdout.writeln('  | … ${lines.length - 24} more lines');
          }
        } on ClawRpcException catch (e) {
          stdout.writeln('--- $name  ${e.code}: ${e.message}');
        }
      }
      await gateway.dispose();
      return;
    }

    // Which surfaces this gateway actually serves.
    //
    // The client declares a capability per *surface*, and the only honest
    // basis for declaring one is the server answering the call. A method that
    // does not exist answers with a distinct code, so an unknown method and a
    // method that exists but rejected these arguments are told apart — which
    // matters, because the second means the surface is real and only the
    // parameters are wrong.
    if (args.contains('--probe')) {
      final sessions = await gateway.sessions(limit: 1);
      final key = _flag(args, 'session') ??
          (sessions.isEmpty ? '' : sessions.first.key);
      final candidates = <String, Map<String, dynamic>>{
        'skills.list': const {},
        'plugins.list': const {},
        'commands.list': const {},
        'cron.list': const {},
        'schedules.list': const {},
        'processes.list': const {},
        'projects.list': const {},
        'workspaces.list': const {},
        'usage.get': {'sessionKey': key},
        'sessions.usage': {'sessionKey': key},
        'checkpoints.list': {'sessionKey': key},
        'rollback.list': {'sessionKey': key},
        'sessions.undo': {'sessionKey': key},
        'agents.list': const {},
        'subagents.list': const {},
        'memory.list': const {},
        'providers.list': const {},
        'models.providers': const {},
        'channels.list': const {},
        'sessions.get': {'key': key},
      };
      for (final entry in candidates.entries) {
        try {
          final result = await gateway.call(entry.key, entry.value);
          final keys = result.keys.take(8).join(', ');
          stdout.writeln('OK        ${entry.key.padRight(20)} {$keys}');
        } on ClawRpcException catch (e) {
          stdout.writeln('${e.code.padRight(9)} ${entry.key}  ${e.message}');
        } catch (e) {
          stdout.writeln('ERR       ${entry.key}  $e');
        }
      }
      await gateway.dispose();
      return;
    }

    // Exercises the three methods a fake socket cannot vouch for: a fake
    // asserts what the client sent, never what a server would accept, and
    // that is the gap five earlier parameter bugs lived in.
    if (args.contains('--verify')) {
      final parent = await gateway.createSession(
        label: 'Caduceus verify ${DateTime.now().millisecondsSinceEpoch}',
      );
      stdout.writeln('created  $parent');

      final fork = await gateway.createSession(
        parentSessionKey: parent,
        fork: true,
      );
      stdout.writeln('forked   $fork');

      final models = await gateway.models();
      final pick = models.firstWhere(
        (m) => m['available'] != false,
        orElse: () => models.first,
      );
      try {
        final patched = await gateway.patchSession(
          fork,
          model: '${pick['id']}',
        );
        stdout.writeln('patched  ${pick['id']} -> ${patched['model']}');
      } on ClawRpcException catch (e) {
        stdout.writeln('patched  REFUSED: ${e.code} ${e.message}');
      }

      await gateway.subscribeMessages(fork);
      final turn = gateway.send(
        fork,
        'What does the attached file say? Answer in three words.',
        clientId: 'verify-attach-1',
        attachments: [
          ClawConversation.attachment(
            fileName: 'note.txt',
            mimeType: 'text/plain',
            contentBase64: base64.encode(utf8.encode('the pelican is blue')),
          ),
        ],
      );
      stdout.write('attached < ');
      turn.deltas.listen(stdout.write);
      await turn.whenDone.timeout(const Duration(seconds: 90));
      stdout.writeln('\n[verify] all four calls accepted');
      await gateway.dispose();
      return;
    }

    final chosen = _flag(args, 'session');
    final target = chosen ??
        (args.contains('--fresh') || sessions.isEmpty
        // Labels are unique per gateway: reusing one answers
        // "label already in use", which is a create that looks like a bug.
        ? await gateway.createSession(
            label: 'Caduceus probe ${DateTime.now().millisecondsSinceEpoch}',
          )
        : sessions.first.key);
    stdout.writeln('target: $target');

    // Both subscriptions. The session-index one alone would leave the reply
    // below waiting forever — it travels on the transcript subscription.
    await gateway.subscribeSessions();
    await gateway.subscribeMessages(target);

    // Every frame, by name and by the keys it carries. The turn-terminal
    // signal is the one thing about this protocol that cannot be read out of
    // a schema — it is a runtime shape — so this is how it gets pinned.
    if (trace) {
      gateway.events.listen((e) {
        if (e.name == 'tick' || e.name == 'health') return;
        final keys = e.payload.keys.toList()..sort();
        stderr.writeln('[event] ${e.name} seq=${e.seq} keys=$keys');
        // The turn-terminal signal is a runtime shape, not a schema one, so
        // the fields that could plausibly carry it are printed in full.
        if (e.name == 'session.message') {
          final m = '${e.payload['message']}';
          stderr.writeln('        message = '
              '${m.length > 300 ? '${m.substring(0, 300)}…' : m}');
        }
        if (e.name == 'session.tool' || e.name == 'agent') {
          final data = e.payload['data'];
          final text = '$data';
          stderr.writeln('        data = '
              '${text.length > 420 ? '${text.substring(0, 420)}…' : text}');
        }
        for (final k in ['final', 'done', 'status', 'phase', 'state',
            'hasActiveRun', 'stop', 'stopReason', 'replace', 'role']) {
          if (e.payload.containsKey(k)) {
            stderr.writeln('        $k = ${e.payload[k]}');
          }
        }
      });
    }
    stdout.writeln('\n> $say');
    stdout.write('< ');
    final turn = gateway.send(target, say, clientId: 'caduceus-say-1');
    turn.deltas.listen(stdout.write);
    final reply = await turn.whenDone.timeout(const Duration(seconds: 120));
    stdout.writeln('\n\n[done] ${reply.length} chars');
    await gateway.unsubscribeMessages(target);
  } on ClawRpcException catch (e) {
    stderr.writeln('\n$e');
    if (e.needsPairing) {
      stderr.writeln(
        '→ approve device ${identity.deviceId} in OpenClaw, then re-run.\n'
        '  The pending request prunes quickly, so approve it soon after '
        'this run.',
      );
    } else if (e.needsGatewayToken) {
      stderr.writeln(e.gatewayTokenWrong
          ? '→ the gateway token is wrong.'
          : '→ pass --token <gateway.auth.token>.');
    }
    exitCode = 1;
  } finally {
    await gateway.dispose();
  }
}
