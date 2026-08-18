/// A reversed virtual list must still read from oldest to newest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

void main() {
  testWidgets('settled blocks, attached rows, and tail keep transcript order', (
    tester,
  ) async {
    final controller = StreamingMarkdownController(
      initialText: 'Old prompt\n\nOld answer\n\nNew prompt\n\n',
    );
    addTearDown(controller.dispose);
    controller.append('New answer');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownView(
            controller: controller,
            beforeTail: const Text('before tail'),
            afterBlock: (index) =>
                index == 2 ? const Text('attached row') : null,
            afterTail: const Text('after tail'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final oldPrompt = tester.getTopLeft(find.text('Old prompt')).dy;
    final oldAnswer = tester.getTopLeft(find.text('Old answer')).dy;
    final newPrompt = tester.getTopLeft(find.text('New prompt')).dy;
    final attached = tester.getTopLeft(find.text('attached row')).dy;
    final beforeTail = tester.getTopLeft(find.text('before tail')).dy;
    final newAnswer = tester.getTopLeft(find.text('New answer')).dy;
    final afterTail = tester.getTopLeft(find.text('after tail')).dy;

    expect(oldPrompt, lessThan(oldAnswer));
    expect(oldAnswer, lessThan(newPrompt));
    expect(newPrompt, lessThan(attached));
    expect(attached, lessThan(beforeTail));
    expect(beforeTail, lessThan(newAnswer));
    expect(newAnswer, lessThan(afterTail));
  });
}
