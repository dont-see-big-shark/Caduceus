/// 提交形变 — the button is the progress container.
///
/// 宽度收成圆形 320ms，转子跑完后勾号弹入并把圆撑回胶囊，全程同一个 widget，
/// 不做页面级 loading. The claim worth pinning is the *geometry*: it really
/// collapses to a circle and really comes back, at any text size, without a
/// second spinner appearing anywhere else.
library;

import 'package:caduceus/design/components.dart';
import 'package:caduceus/design/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Size> _pump(
  WidgetTester tester,
  Morph state, {
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: caduceusTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: MorphButton(
              label: 'Connect',
              state: state,
              onPressed: () {},
            ),
          ),
        ),
      ),
    ),
  );
  // Past the 320 ms collapse and the switcher's cross-fade.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return tester.getSize(find.byType(AnimatedContainer));
}

void main() {
  testWidgets('working collapses the pill to a circle', (tester) async {
    final idle = await _pump(tester, Morph.idle);
    expect(idle.width, greaterThan(idle.height), reason: 'a pill to start');

    final working = await _pump(tester, Morph.working);
    expect(
      working.width,
      working.height,
      reason: 'the circle is the point — 宽度收成圆形',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
  });

  testWidgets('done springs the tick in and pushes it back to a pill', (
    tester,
  ) async {
    final done = await _pump(tester, Morph.done);
    expect(done.width, greaterThan(done.height));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'the spinner is gone once it has finished',
    );
  });

  testWidgets('the circle stays a circle at a raised text size', (
    tester,
  ) async {
    // The pill width is measured from the label, so a bigger label must not
    // drag the collapsed state into an oval.
    final working = await _pump(tester, Morph.working, textScale: 1.8);
    expect(working.width, working.height);

    final idle = await _pump(tester, Morph.idle, textScale: 1.8);
    expect(
      idle.width,
      greaterThan((await _pump(tester, Morph.idle)).width),
      reason: 'and the pill grows with the text it holds',
    );
  });

  testWidgets('it cannot be pressed twice while it is working', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: caduceusTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: MorphButton(
              label: 'Connect',
              state: Morph.working,
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(MorphButton));
    await tester.pump();

    expect(taps, 0, reason: 'a second connect while one is in flight');
  });
}
