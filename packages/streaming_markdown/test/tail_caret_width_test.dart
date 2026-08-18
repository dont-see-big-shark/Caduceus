/// The caret is 8 points wide, wherever it lands.
///
/// A ListView gives its items a tight cross-axis constraint, and a `Container`
/// with a width of its own *enforces* that width against the incoming
/// constraint rather than replacing it — so a caret returned bare into the
/// list came out as a brass bar the full width of the transcript. It only
/// happened on the path where the tail is empty, which is the common one: a
/// turn that has called a tool and not yet written a word.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

Widget _caret() => Container(
  key: const ValueKey('caret'),
  width: 8,
  height: 16,
  color: const Color(0xFFC8A96A),
);

Future<void> _pump(WidgetTester tester, StreamingMarkdownController c) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: StreamingMarkdownView(controller: c, afterTail: _caret()),
          ),
        ),
      ),
    );

void main() {
  testWidgets('with no tail text yet', (tester) async {
    final c = StreamingMarkdownController();
    addTearDown(c.dispose);
    await _pump(tester, c);
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey('caret'))).width,
      8,
      reason: 'a caret, not a bar across the whole transcript',
    );
  });

  testWidgets('and with a tail being written', (tester) async {
    final c = StreamingMarkdownController();
    addTearDown(c.dispose);
    await _pump(tester, c);
    c.append('the answer is arri');
    await tester.pump();

    expect(tester.getSize(find.byKey(const ValueKey('caret'))).width, 8);
  });
}
