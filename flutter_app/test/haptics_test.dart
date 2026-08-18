/// The haptic vocabulary, and who is allowed to speak it.
///
/// Four sensations, each meaning one thing. Two rules make them useful rather
/// than noise: a session nobody is looking at does not buzz the phone, and a
/// burst of events does not blur into one long vibration.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/haptics.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

class _Socket implements GatewayTransport {
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

  void reply(String m, Object r) => _in.add(
    jsonEncode({'jsonrpc': '2.0', 'id': lastOf(m)!['id'], 'result': r}),
  );

  void event(String type, String sid, Map<String, dynamic> payload) => _in.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {'type': type, 'session_id': sid, 'payload': payload},
    }),
  );
}

void main() {
  late List<String> fired;

  setUp(() {
    fired = [];
    Haptics.resetThrottle();
    // The design targets a phone; the host running the test is not one.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            fired.add('${call.arguments}');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Cleared inside the test body, not in `tearDown`: the binding verifies
  /// that no foundation debug variable outlives a widget test, and it runs
  /// that check *before* tear-downs.
  void restorePlatform() => debugDefaultTargetPlatformOverride = null;

  test('a burst is throttled to one pulse', () {
    for (var i = 0; i < 8; i++) {
      Haptics.tap();
    }
    expect(
      fired.length,
      1,
      reason: 'eight pulses in a row is one long buzz, not eight signals',
    );
  });

  test('a failure is never throttled away', () {
    Haptics.tap();
    Haptics.warn();
    expect(fired.length, 2, reason: 'the thing that went wrong must land');
  });

  testWidgets('a background session does not buzz the phone', (tester) async {
    // A turn left running in another session finishing a tool call is not
    // something to interrupt someone for.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    final workspace = Workspace(gateway);
    addTearDown(() {
      workspace.dispose();
      unawaited(gateway.dispose());
    });

    for (final id in ['a', 'b']) {
      final opening = workspace.open(id);
      await tester.pump();
      socket.reply('session.resume', {
        'session_id': 'live-$id',
        'resumed': id,
        'running': false,
        'info': const {'model': 'm'},
        'messages': <Object>[],
      });
      await opening;
    }
    // 'b' is the one on screen.
    expect(workspace.activeId, 'b');

    fired.clear();
    Haptics.resetThrottle();
    socket.event('tool.complete', 'live-a', {
      'tool_id': 't1',
      'name': 'read_file',
      'duration_s': 0.2,
      'result': const {'output': 'ok'},
    });
    await tester.pump();
    expect(fired, isEmpty, reason: 'session a is not on screen');

    Haptics.resetThrottle();
    socket.event('tool.complete', 'live-b', {
      'tool_id': 't2',
      'name': 'read_file',
      'duration_s': 0.2,
      'result': const {'output': 'ok'},
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    restorePlatform();
    expect(fired, isNotEmpty, reason: 'session b is what the user is watching');
  });

  testWidgets('an approval buzzes whichever session it came from', (
    tester,
  ) async {
    // The agent is blocked until it is answered. Which session asked is not
    // the point — that nothing is moving until you look is.
    final socket = _Socket();
    final gateway = HermesGateway(
      HermesEndpoint.tunnelled(token: 't', port: 9219),
      connector: (_) async => socket,
    );
    await gateway.connect();
    final workspace = Workspace(gateway);
    addTearDown(() {
      workspace.dispose();
      unawaited(gateway.dispose());
    });

    for (final id in ['a', 'b']) {
      final opening = workspace.open(id);
      await tester.pump();
      socket.reply('session.resume', {
        'session_id': 'live-$id',
        'resumed': id,
        'running': false,
        'info': const {'model': 'm'},
        'messages': <Object>[],
      });
      await opening;
    }

    fired.clear();
    Haptics.resetThrottle();
    socket.event('approval.request', 'live-a', {
      'tool': 'terminal',
      'command': 'rm -rf /tmp/x',
    });
    await tester.pump();

    restorePlatform();
    expect(fired, isNotEmpty);
  });
}
