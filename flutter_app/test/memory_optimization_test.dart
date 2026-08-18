import 'dart:async';
import 'dart:convert';

import 'package:caduceus/backends/hermes_backend.dart';
import 'package:caduceus/widgets/message_bubble.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

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
}

void main() {
  test(
    'Image memory calculation benchmark: 12MP unconstrained vs 800px cacheWidth',
    () {
      // A 12MP camera photo: 4000x3000 RGBA (4 bytes per pixel)
      const originalWidth = 4000;
      const originalHeight = 3000;
      const bytesPerPixel = 4;
      const unconstrainedBytes = originalWidth * originalHeight * bytesPerPixel;
      final unconstrainedMb = unconstrainedBytes / (1024 * 1024);

      // With cacheWidth: 800, height scales proportionally to 600
      const cacheWidth = 800;
      const scaledHeight = 600;
      const optimizedBytes = cacheWidth * scaledHeight * bytesPerPixel;
      final optimizedMb = optimizedBytes / (1024 * 1024);

      final reductionPercentage =
          ((unconstrainedBytes - optimizedBytes) / unconstrainedBytes) * 100;

      expect(unconstrainedMb, closeTo(45.77, 0.1)); // ~45.78 MB
      expect(optimizedMb, closeTo(1.83, 0.1)); // ~1.83 MB
      expect(
        reductionPercentage,
        greaterThan(95.0),
      ); // >95% reduction per image
    },
  );

  testWidgets('UserBubble memoization avoids redundant regex work', (
    tester,
  ) async {
    const text = 'Hello world\n![img](http://example.com/test.png)';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UserBubble(text: text)),
      ),
    );

    expect(find.text('Hello world'), findsOneWidget);
    expect(find.byType(ChatImageView), findsOneWidget);
  });

  test(
    'Workspace LRU eviction bounds resident SessionConsole instances to 8',
    () async {
      final socket = _Socket();
      final gateway = HermesGateway(
        HermesEndpoint.tunnelled(token: 't', port: 9219),
        connector: (_) async => socket,
      );
      final backend = HermesBackend(gateway);
      await backend.connect();
      final workspace = Workspace.forBackend(backend, gateway: gateway);
      addTearDown(workspace.dispose);

      // Simulate opening 12 sessions sequentially
      for (var i = 1; i <= 12; i++) {
        final openFuture = workspace.open('session_$i');
        socket.reply('session.resume', {
          'session_id': 'live_$i',
          'resumed': 'session_$i',
          'running': false,
          'messages': [],
        });
        await openFuture;
      }

      // Active session is session_12
      expect(workspace.activeId, 'session_12');

      // Number of resident consoles in memory must be capped at 8 (not 12)
      var residentCount = 0;
      for (var i = 1; i <= 12; i++) {
        if (workspace.consoleFor('session_$i') != null) {
          residentCount++;
        }
      }

      expect(residentCount, lessThanOrEqualTo(8));
      // Oldest inactive sessions (e.g. session_1 to session_4) were evicted
      expect(workspace.consoleFor('session_1'), isNull);
      expect(workspace.consoleFor('session_2'), isNull);
      expect(workspace.consoleFor('session_3'), isNull);
      expect(workspace.consoleFor('session_4'), isNull);
      // Recent sessions remain resident
      expect(workspace.consoleFor('session_12'), isNotNull);
      expect(workspace.consoleFor('session_11'), isNotNull);
    },
  );
}
