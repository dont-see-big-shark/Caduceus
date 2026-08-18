/// 分段与开关 — 开关旋钮过冲 3px，轨道颜色用 lerp 而不是切换.
///
/// Both halves are claims a switch can fail silently: Material's switch settles
/// straight onto its mark and cross-fades its track, and it looks fine. What is
/// worth pinning is that the thumb really goes *past* — by the stated three
/// points, at both ends — and that the track is genuinely somewhere in between
/// while it travels rather than one of its two colours.
library;

import 'package:caduceus/design/components.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The thumb's offset inside the track, in points.
double _thumbX(WidgetTester tester) => tester
    .widget<Positioned>(
      find.descendant(
        of: find.byType(GlassSwitch),
        matching: find.byType(Positioned),
      ),
    )
    .left!;

Color _trackColour(WidgetTester tester) {
  // The track encloses the thumb, so it is the first Container in the tree.
  final box = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(GlassSwitch),
          matching: find.byType(Container),
        )
        .first,
  );
  return (box.decoration! as BoxDecoration).color!;
}

Future<void> _pump(WidgetTester tester, ValueNotifier<bool> on) =>
    tester.pumpWidget(
      MaterialApp(
        theme: caduceusTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: on,
              builder: (context, value, _) =>
                  GlassSwitch(value: value, onChanged: (v) => on.value = v),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('the thumb overshoots the on position by 3 points', (
    tester,
  ) async {
    final on = ValueNotifier(false);
    await _pump(tester, on);

    final off = _thumbX(tester);
    on.value = true;
    await tester.pump();

    // Sample the whole throw and keep the furthest the thumb ever gets.
    var furthest = off;
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      furthest = furthest > _thumbX(tester) ? furthest : _thumbX(tester);
    }
    await tester.pumpAndSettle();
    final settled = _thumbX(tester);

    expect(
      settled - off,
      moreOrLessEquals(_GlassSwitchGeometry.travel, epsilon: 0.01),
      reason: 'it ends where it should',
    );
    expect(
      furthest - settled,
      moreOrLessEquals(3, epsilon: 0.15),
      reason: '过冲 3px — not the 1.8 that easeOutBack gives away for free',
    );
  });

  testWidgets('and overshoots the off position on the way back', (
    tester,
  ) async {
    final on = ValueNotifier(true);
    await _pump(tester, on);
    final start = _thumbX(tester);

    on.value = false;
    await tester.pump();

    var least = start;
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      least = least < _thumbX(tester) ? least : _thumbX(tester);
    }
    await tester.pumpAndSettle();

    expect(
      _thumbX(tester) - least,
      moreOrLessEquals(3, epsilon: 0.15),
      reason:
          'the throw is symmetric — an overshoot only one way reads as a '
          'bug in the other direction',
    );
  });

  testWidgets('the track lerps rather than switching', (tester) async {
    final on = ValueNotifier(false);
    await _pump(tester, on);
    final offColour = _trackColour(tester);

    on.value = true;
    await tester.pumpAndSettle();
    final onColour = _trackColour(tester);
    expect(onColour, isNot(offColour));

    // Halfway through the throw the track must be neither of its two
    // colours — that is the whole difference between a lerp and a switch.
    on.value = false;
    await tester.pump();
    await tester.pump(Motion.standard ~/ 2);
    final middle = _trackColour(tester);

    expect(middle, isNot(offColour));
    expect(middle, isNot(onColour));
    expect(
      middle,
      isSameColorAs(Color.lerp(offColour, onColour, .5)!),
      reason: 'and it is the midpoint, not some other in-between',
    );
  });

  testWidgets('tapping it reports the new value', (tester) async {
    final on = ValueNotifier(false);
    await _pump(tester, on);

    await tester.tap(find.byType(GlassSwitch));
    await tester.pumpAndSettle();

    expect(on.value, isTrue);
    expect(
      tester.getSize(find.byType(GlassSwitch)).height,
      greaterThanOrEqualTo(44),
      reason: 'a 28pt switch still needs a 44pt target',
    );
  });
}

/// The geometry the test asserts against, kept here so a change to the
/// switch's size fails loudly instead of quietly relaxing the assertion.
abstract final class _GlassSwitchGeometry {
  static const travel = 46.0 - 22.0 - 3.0 * 2;
}
