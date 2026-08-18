/// Opening a large transcript should stay bottom-anchored and lazy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

class _BuildCounter extends StatefulWidget {
  const _BuildCounter({required this.child});

  final Widget child;

  @override
  State<_BuildCounter> createState() => _BuildCounterState();
}

class _BuildCounterState extends State<_BuildCounter> {
  @override
  void initState() {
    super.initState();
    builds++;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

var builds = 0;

void main() {
  testWidgets('a long document opens at the bottom without building history', (
    tester,
  ) async {
    builds = 0;
    final paragraph = List.filled(12, 'word').join(' ');
    final document = List.generate(
      1000,
      (i) => 'Message $i\n\n$paragraph\n\n',
    ).join();

    final dataClock = Stopwatch()..start();
    final controller = StreamingMarkdownController(initialText: document);
    dataClock.stop();

    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final renderClock = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownView(
            controller: controller,
            blockDecorator: (_, _, child) => _BuildCounter(child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    renderClock.stop();

    // Diagnostic output, deliberately not an assertion: CI machines differ.
    // Local runs tell us which phase owns the wall clock.
    // ignore: avoid_print
    print(
      'large-document-open: data=${dataClock.elapsedMilliseconds}ms '
      'render=${renderClock.elapsedMilliseconds}ms '
      'blocks=${controller.settledBlockCount} builds=$builds',
    );

    expect(controller.settledBlockCount, 2000);
    expect(builds, lessThan(40));
    expect(find.text('Message 999'), findsOneWidget);

    final initialBuilds = builds;
    expect(find.text('Message 0'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(
      builds,
      greaterThan(initialBuilds),
      reason: 'older history should render only as the user scrolls to it',
    );

    controller.dispose();
  });
}
