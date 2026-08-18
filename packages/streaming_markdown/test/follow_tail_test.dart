/// The answer being written has to stay on screen.
///
/// `scrollToBottom` existed but was only ever called when the user sent
/// something. Nothing followed the tail while tokens arrived, so on a phone
/// the reply was written below the fold and the user watched a static screen.
///
/// Following unconditionally is the opposite mistake: it makes reading back
/// through a long answer impossible, because every token yanks the view down.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

Future<void> _pumpView(
  WidgetTester tester,
  StreamingMarkdownController controller,
) async {
  tester.view.physicalSize = const Size(393, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: StreamingMarkdownView(controller: controller)),
    ),
  );
}

/// Enough blocks to overflow the viewport several times.
Future<void> _fill(
  WidgetTester tester,
  StreamingMarkdownController c, {
  int blocks = 40,
}) async {
  for (var i = 0; i < blocks; i++) {
    c.append(
      'Paragraph number $i with enough words to take a line or two.\n\n',
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('new content pulls the view down with it', (tester) async {
    final controller = StreamingMarkdownController();
    await _pumpView(tester, controller);
    await _fill(tester, controller);

    final position = controller.scrollController.position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'the fixture has to overflow, or this proves nothing',
    );
    expect(
      position.pixels,
      0,
      reason: 'a reversed list keeps offset zero at the newest content',
    );

    // And it keeps up as more arrives.
    controller.append('One more paragraph arriving later.\n\n');
    await tester.pumpAndSettle();
    expect(controller.scrollController.position.pixels, 0);

    controller.dispose();
  });

  testWidgets('scrolling up detaches the follow', (tester) async {
    // Reading back through a long answer is impossible if every token drags
    // the viewport to the end.
    final controller = StreamingMarkdownController();
    await _pumpView(tester, controller);
    await _fill(tester, controller);

    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    final parked = controller.scrollController.position.pixels;
    expect(
      parked,
      greaterThan(0),
      reason: 'the drag has to actually move away from the bottom',
    );

    controller.append('Text arriving while the user reads history.\n\n');
    await tester.pumpAndSettle();

    expect(
      controller.scrollController.position.pixels,
      closeTo(parked, 1),
      reason: 'the view must stay where the user put it',
    );

    controller.dispose();
  });

  testWidgets('returning to the bottom re-arms the follow', (tester) async {
    final controller = StreamingMarkdownController();
    await _pumpView(tester, controller);
    await _fill(tester, controller);

    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    // Back to the end, the way a user flicks down.
    controller.scrollController.jumpTo(0);
    await tester.pumpAndSettle();

    controller.append('Newest line after coming back.\n\n');
    await tester.pumpAndSettle();

    expect(
      controller.scrollController.position.pixels,
      0,
      reason: 'coming back to the bottom opts back into following',
    );

    controller.dispose();
  });

  testWidgets('dragging the transcript dismisses the keyboard', (tester) async {
    final controller = StreamingMarkdownController();
    await _pumpView(tester, controller);
    final view = tester.widget<ListView>(find.byType(ListView));
    expect(
      view.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
      reason:
          'on a phone this is the gesture people already use, and '
          'without it the keyboard covers the answer with no way out',
    );
    controller.dispose();
  });
}
