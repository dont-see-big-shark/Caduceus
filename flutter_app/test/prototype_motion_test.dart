/// The last three items on the prototype's 动效清单.
///
/// 底部面板从下推入 360ms · 图标提前 40ms 响应 · 气泡从输入条位置向上生长入场.
library;

import 'package:caduceus/design/components.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:caduceus/widgets/panel_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = Size(393, 852);
const _mac = Size(1280, 800);

Future<void> _openPanel(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: caduceusTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showPanel<void>(
                context,
                (_) => const Panel(
                  title: Text('Background processes'),
                  content: PanelFrame(child: Text('nothing running')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
}

void main() {
  testWidgets('a sheet comes up from the edge it is anchored to', (
    tester,
  ) async {
    await _openPanel(tester, _phone);

    // One frame in it must be below where it lands, or it materialised in
    // place — which leaves the pull-down that dismisses it looking like a
    // gesture invented for the occasion rather than the reverse of entering.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final entering = tester.getTopLeft(find.byType(Panel)).dy;

    await tester.pumpAndSettle();
    final landed = tester.getTopLeft(find.byType(Panel)).dy;

    expect(entering, greaterThan(landed), reason: 'it slid up into place');
  });

  testWidgets('and leaves faster than it arrived', (tester) async {
    await _openPanel(tester, _phone);
    await tester.pumpAndSettle();

    expect(
      Motion.exit,
      lessThan(Motion.emphasized),
      reason: 'nobody waits for a dismissal — the rule the route encodes',
    );
  });

  testWidgets('a centred dialog does not slide in from anywhere', (
    tester,
  ) async {
    // It is not attached to an edge, so it has no edge to come from.
    await _openPanel(tester, _mac);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final entering = tester.getTopLeft(find.byType(Panel)).dy;

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(Panel)).dy, entering);
  });

  group('气泡从输入条位置向上生长入场', () {
    Widget bubble(Set<int> revealed, int index) => MaterialApp(
      theme: caduceusTheme(Brightness.dark),
      home: Scaffold(
        body: GrowFromComposer(
          index: index,
          revealed: revealed,
          child: const SizedBox(
            key: ValueKey('bubble'),
            width: 100,
            height: 40,
          ),
        ),
      ),
    );

    testWidgets('it grows on the way in', (tester) async {
      await tester.pumpWidget(bubble(<int>{}, 0));

      // The painted rect, not the widget's own field: a Transform does not
      // change layout, so this is the only place the growth is observable.
      await tester.pump();
      final start = tester.getRect(find.byKey(const ValueKey('bubble')));

      await tester.pumpAndSettle();
      final end = tester.getRect(find.byKey(const ValueKey('bubble')));

      expect(start.width, lessThan(end.width));
      expect(end.width, moreOrLessEquals(100, epsilon: .01));

      // Anchored where the composer is, so the trailing edge stays put and
      // the bubble grows away from it rather than out of its own middle.
      expect(start.right, moreOrLessEquals(end.right, epsilon: .5));
    });

    testWidgets('it never goes fully transparent', (tester) async {
      // A bubble at zero opacity drops out of the semantics tree, and the
      // question you just asked is the last thing that should be unreadable.
      await tester.pumpWidget(bubble(<int>{}, 0));
      await tester.pump();

      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, greaterThan(0));
    });

    testWidgets('and it does not replay when scrolled back to', (tester) async {
      // The trap this codebase has already fallen into once: ListView.builder
      // disposes what leaves the viewport and builds it fresh on return, so an
      // entrance keyed on "is this widget new" plays on every scroll.
      final revealed = <int>{};
      await tester.pumpWidget(bubble(revealed, 7));
      await tester.pumpAndSettle();

      // Same index, rebuilt from scratch.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(bubble(revealed, 7));
      await tester.pump();

      expect(
        find.byType(Opacity),
        findsNothing,
        reason: 'no entrance wrapper at all the second time',
      );
    });
  });
}
