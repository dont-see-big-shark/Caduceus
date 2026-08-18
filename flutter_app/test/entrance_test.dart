/// Staggered entrances must *finish*.
///
/// On the simulator the command palette rendered as an empty sheet: the box
/// was the right size, the items were in the tree, and nothing was visible.
/// An entrance that never completes looks exactly like a rendering bug, and
/// only a screenshot shows it — so it gets a test that reads the opacity
/// rather than the presence of the widget.
library;

import 'package:caduceus/design/components.dart';
import 'package:caduceus/widgets/console_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The innermost fade wrapping [text] — `find.ancestor` walks outward, and the
/// outer ones belong to the route.
double _opacityOf(WidgetTester tester, String text) {
  final fades = tester.widgetList<FadeTransition>(
    find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)),
  );
  return fades.first.opacity.value;
}

/// Two pumps, not one: the staggered rows arm themselves with a timer, so the
/// frame that fires the timer is not the frame that finishes the animation.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a staggered child ends up fully visible', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (var i = 0; i < 4; i++)
                Staggered(index: i, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );

    await _settle(tester);
    for (var i = 0; i < 4; i++) {
      expect(
        _opacityOf(tester, 'row $i'),
        1.0,
        reason: 'row $i never finished arriving',
      );
    }
  });

  testWidgets('rows past the stagger cap still arrive', (tester) async {
    // The stagger stops at 8 so a long list does not trail. The cap must not
    // mean the ninth row is left at zero.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 14; i++)
                Staggered(index: i, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(_opacityOf(tester, 'row 13'), 1.0);
  });

  testWidgets('the command palette shows its commands', (tester) async {
    // Built the way the console builds it, because the defect was only ever
    // visible in place: the sheet had the right height and nothing in it.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              CompletionOverlay(
                completions: const [
                  CompletionItem(
                    insert: '/undo ',
                    label: '/undo',
                    meta: 'Undo the last exchange',
                  ),
                  CompletionItem(
                    insert: '/model ',
                    label: '/model',
                    meta: 'Switch the model',
                  ),
                ],
                maxHeight: 260,
                onSelect: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('/undo'), findsOneWidget);
    expect(
      _opacityOf(tester, '/undo'),
      1.0,
      reason:
          'a command you cannot see is the same as a command that is '
          'not there',
    );
    expect(_opacityOf(tester, '/model'), 1.0);
  });
}
