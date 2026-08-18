/// A turn's entries arrive once, and only once.
///
/// The timeline lives inside the transcript's `ListView`, so its widgets are
/// destroyed and rebuilt every time the turn scrolls out of view and back.
/// Anything that remembers "I have already animated this" in the widget tree
/// is reset by that, and a finished turn replays every thought and tool call
/// under the reader's thumb. The set that remembers belongs to the turn.
library;

import 'package:caduceus/design/components.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _opacityOf(WidgetTester tester, String text) {
  final fades = tester.widgetList<FadeTransition>(
    find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)),
  );
  return fades.isEmpty ? 1.0 : fades.first.opacity.value;
}

void main() {
  test('a turn remembers which entries have been shown', () {
    final turn = Turn(anchorBlock: 0);
    expect(turn.revealed, isEmpty);
    turn.revealed.add(0);
    expect(turn.revealed.contains(0), isTrue);
  });

  testWidgets('an entry arrives the first time and not the second', (
    tester,
  ) async {
    final revealed = <int>{};

    Widget build() => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Reveal(index: 0, revealed: revealed, child: const Text('thought')),
          ],
        ),
      ),
    );

    await tester.pumpWidget(build());
    // Mid-flight on the first frame: it is arriving.
    expect(_opacityOf(tester, 'thought'), lessThan(1.0));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacityOf(tester, 'thought'), 1.0);

    // Torn down and rebuilt, exactly as a recycled list item is.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(build());

    expect(
      _opacityOf(tester, 'thought'),
      1.0,
      reason: 'scrolling back must not replay a turn that already happened',
    );
  });

  testWidgets('a new entry still arrives after the earlier ones settled', (
    tester,
  ) async {
    // The case the memory must not break: the model is still working, and the
    // thing that just happened should be seen to happen.
    final revealed = <int>{};
    var count = 1;

    Widget build() => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            for (var i = 0; i < count; i++)
              Reveal(index: i, revealed: revealed, child: Text('entry $i')),
          ],
        ),
      ),
    );

    await tester.pumpWidget(build());
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    count = 2;
    await tester.pumpWidget(build());
    expect(
      _opacityOf(tester, 'entry 1'),
      lessThan(1.0),
      reason: 'the entry that just arrived should be seen arriving',
    );
    expect(_opacityOf(tester, 'entry 0'), 1.0);
  });
}
