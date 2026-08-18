/// The degraded material, and the fact that anyone can reach it.
///
/// It was fully implemented and fully tested, and **nothing could turn it
/// on**: `Materials.degraded` was written only by a unit test. A fallback
/// nobody can reach is not a fallback — it is dead code with a passing test
/// standing over it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:caduceus/design/glass.dart';
import 'package:caduceus/design/components.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:caduceus/main.dart' show setReduceEffects, loadReduceEffects;
import 'package:caduceus/settings_page.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Socket implements GatewayTransport {
  final _in = StreamController<String>.broadcast();
  @override
  Stream<String> get inbound => _in.stream;
  @override
  void send(String d) {
    // The Model page opens by default (as the design does) and asks the
    // gateway for the server configuration. Answer it so the call does not
    // leave a 30-second timeout pending for the rest of the test.
    final frame = jsonDecode(d) as Map<String, dynamic>;
    if (frame['id'] != null) {
      _in.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': frame['id'],
          'result': <String, Object>{},
        }),
      );
    }
  }

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }
}

int _blurs(WidgetTester tester) =>
    tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).length;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Materials.degraded.value = false;
  });
  tearDown(() => Materials.degraded.value = false);

  testWidgets('the switch reaches the material', (tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
        theme: caduceusTheme(Brightness.dark),
        home: SettingsPage(workspace: workspace),
      ),
    );
    await tester.pump();

    expect(_blurs(tester), greaterThan(0), reason: 'glass to begin with');

    // It lives under Appearance now — settings drill down rather than being
    // one flat list, so getting there is part of what this checks.
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();

    final glassSwitch = find.byType(GlassSwitch);
    await tester.tap(glassSwitch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      _blurs(tester),
      0,
      reason: 'the switch has to actually reach the material',
    );
    expect(Materials.degraded.value, isTrue);
  });

  testWidgets('the choice survives a restart', (tester) async {
    // A performance setting that resets every launch is one the user has to
    // find again on every launch.
    await setReduceEffects(true);
    Materials.degraded.value = false;

    await loadReduceEffects();
    expect(Materials.degraded.value, isTrue);

    await setReduceEffects(false);
    Materials.degraded.value = true;
    await loadReduceEffects();
    expect(Materials.degraded.value, isFalse);
  });

  testWidgets('degraded keeps the layout it had', (tester) async {
    // 视觉降级但结构完全一致 — the promise that makes this safe to offer. If a
    // panel changed size when the effects went off, the setting would be a
    // different app rather than the same one drawn cheaply.
    Size sizeOfPanel() => tester.getSize(find.byType(GlassPanel).first);

    await tester.pumpWidget(
      MaterialApp(
        theme: caduceusTheme(Brightness.dark),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: GlassPanel(
                padding: EdgeInsets.all(16),
                child: Text('same size either way'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final rich = sizeOfPanel();

    Materials.degraded.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(sizeOfPanel(), rich);
    expect(_blurs(tester), 0);
  });
}
