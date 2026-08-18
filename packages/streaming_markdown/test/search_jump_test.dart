import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

Future<void> _pump(
  WidgetTester tester,
  StreamingMarkdownController controller,
) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StreamingMarkdownView(
          controller: controller,
          maxRenderBlockLines: 40,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search reaches an unbuilt historical block', (tester) async {
    final document = List.generate(
      300,
      (i) => 'Paragraph $i with enough text to occupy a line.\n\n',
    ).join();
    final controller = StreamingMarkdownController(initialText: document);
    addTearDown(controller.dispose);

    await _pump(tester, controller);

    expect(find.textContaining('Paragraph 42'), findsNothing);
    controller.scrollToBlock(42);
    await tester.pumpAndSettle();

    expect(find.textContaining('Paragraph 42'), findsOneWidget);

    final parked = controller.scrollController.position.pixels;
    controller.append('A new tail while reading search history.\n\n');
    await tester.pumpAndSettle();

    expect(
      controller.scrollController.position.pixels,
      closeTo(parked, 1),
      reason: 'a search jump must detach tail-following',
    );
  });

  testWidgets('search lands on the segment containing a deep hit', (
    tester,
  ) async {
    final code = [
      '```dart',
      for (var i = 0; i < 400; i++) 'code line $i',
      '```',
    ].join('\n');
    final laterBlocks = List.generate(
      120,
      (i) => 'Later paragraph $i with enough text to overflow.\n\n',
    ).join();
    final controller = StreamingMarkdownController(
      initialText: '$code\n\n$laterBlocks',
    );
    addTearDown(controller.dispose);

    await _pump(tester, controller);

    expect(find.textContaining('code line 300'), findsNothing);
    controller.scrollToBlock(0, characterOffset: code.indexOf('code line 300'));
    await tester.pumpAndSettle();

    // ignore: avoid_print
    expect(find.textContaining('code line 300'), findsOneWidget);
    expect(find.textContaining('code line 0'), findsNothing);
  });
}
