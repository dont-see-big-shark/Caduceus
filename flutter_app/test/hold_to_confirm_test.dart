/// Holding to confirm something that cannot be undone.
///
/// This replaced a Continue button on session deletion, so the thing that has
/// to be true is not "it can confirm" but "it cannot confirm *early*". A hold
/// that fires at 300 ms is a worse dialog, not a better one.
library;

import 'package:caduceus/design/press.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, VoidCallback onConfirmed) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: HoldToConfirm(
              label: 'Hold to delete',
              confirmedLabel: 'Deleted',
              onConfirmed: onConfirmed,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a full hold confirms', (tester) async {
    var fired = 0;
    await _pump(tester, () => fired++);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hold to delete')),
    );
    // A frame to deliver the press: the gesture arena resolves on the next
    // pump, so a single long pump would start the clock before the hold.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(Motion.hold + const Duration(milliseconds: 50));

    expect(fired, 1);
    expect(find.text('Deleted'), findsOneWidget);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('letting go early confirms nothing', (tester) async {
    // The whole point. Half a hold is not a decision.
    var fired = 0;
    await _pump(tester, () => fired++);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hold to delete')),
    );
    // A frame to deliver the press: the gesture arena resolves on the next
    // pump, so a single long pump would start the clock before the hold.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump(Motion.holdRewind + const Duration(milliseconds: 50));

    expect(fired, 0);
    expect(find.text('Hold to delete'), findsOneWidget);
  });

  testWidgets('a tap confirms nothing', (tester) async {
    // The reflex the dialog trained: press, move on. It must do nothing here.
    var fired = 0;
    await _pump(tester, () => fired++);

    await tester.tap(find.text('Hold to delete'));
    await tester.pump(Motion.hold + const Duration(milliseconds: 100));

    expect(fired, 0);
  });

  testWidgets('holding twice does not fire twice', (tester) async {
    var fired = 0;
    await _pump(tester, () => fired++);

    final first = await tester.startGesture(
      tester.getCenter(find.text('Hold to delete')),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(Motion.hold + const Duration(milliseconds: 50));
    await first.up();
    await tester.pump(const Duration(milliseconds: 100));

    final second = await tester.startGesture(
      tester.getCenter(find.text('Deleted')),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(Motion.hold + const Duration(milliseconds: 50));
    await second.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fired, 1, reason: 'a deletion must not be issued twice');
  });
}
