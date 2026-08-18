/// A staggered entrance must not replay when a row is scrolled back.
///
/// `ListView.builder` disposes children that leave the viewport and builds
/// them fresh on the way back, so an entrance animation attached to a row runs
/// *again* every time it is recycled: scroll a session list up and down and
/// every row fades in under your finger. A list is not a menu.
library;

import 'package:caduceus/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _opacityOf(WidgetTester tester, String text) {
  final fades = tester.widgetList<FadeTransition>(
    find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)),
  );
  return fades.isEmpty ? 1.0 : fades.first.opacity.value;
}

void main() {
  testWidgets('a recycled row is not re-animated', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: StaggerScope(
              child: ListView.builder(
                itemCount: 60,
                itemBuilder: (context, i) => Staggered(
                  index: i,
                  child: SizedBox(height: 60, child: Text('row $i')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacityOf(tester, 'row 0'), 1.0);

    // Away and back — far enough that row 0 is disposed and rebuilt.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pump();

    expect(
      _opacityOf(tester, 'row 0'),
      1.0,
      reason: 'scrolling back must not make the row fade in again',
    );
  });
}
