/// 手势跟随 — 卡片下拉 1:1，松手后按速度决定去留.
///
/// A panel on a Mac is a dialog in the middle of a window, which is right:
/// there is a pointer and the window is large. The same card on a phone is a
/// small rectangle floating in the middle of a tall screen, out of reach of
/// the thumb holding the device and dismissable only by a control in its top
/// corner. On a phone it is a sheet, and it comes back down by being pulled.
library;

import 'package:caduceus/design/glass.dart';
import 'package:caduceus/design/press.dart';
import 'package:caduceus/widgets/panel_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = Size(393, 852);
const _mac = Size(1280, 800);

Future<void> _open(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const Panel(
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
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('on a phone it is a sheet at the bottom, with a handle', (
    tester,
  ) async {
    await _open(tester, _phone);

    expect(find.byType(GrabHandle), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    // Anchored to the bottom, not floating in the middle: the whole reason
    // the shape changes is that the thumb is down there.
    final box = tester.getRect(find.byType(PullToDismiss));
    expect(box.bottom, greaterThan(852 - 60));
    expect(box.width, 393, reason: 'full width, like every other sheet');
  });

  testWidgets('pulling it down far enough dismisses it', (tester) async {
    await _open(tester, _phone);
    expect(find.text('Background processes'), findsOneWidget);

    await tester.drag(find.byType(GrabHandle), const Offset(0, 160));
    await tester.pumpAndSettle();

    expect(find.text('Background processes'), findsNothing);
  });

  testWidgets('a short pull springs back instead', (tester) async {
    await _open(tester, _phone);

    // Under the 90-point threshold and slow enough not to read as a flick.
    await tester.timedDrag(
      find.byType(GrabHandle),
      const Offset(0, 40),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Background processes'),
      findsOneWidget,
      reason: 'a hesitant pull is not a dismissal',
    );
  });

  testWidgets('on a Mac it is the shared glass overlay card', (tester) async {
    await _open(tester, _mac);

    // The unified overlay: the same frosted-glass card Settings uses, not a
    // flat AlertDialog and not a bottom sheet.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(GlassPanel), findsWidgets);
    expect(
      find.byType(GrabHandle),
      findsNothing,
      reason: 'there is no thumb at the bottom of a Mac window',
    );
  });
}
