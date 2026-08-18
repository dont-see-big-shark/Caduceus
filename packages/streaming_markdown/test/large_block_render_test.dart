import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

String _codeDocument(int lineCount) =>
    '```dart\n${List.generate(lineCount, (i) => 'code line $i').join('\n')}\n'
    '```\n\n';

String _paragraphDocument(int lineCount) =>
    '${List.generate(lineCount, (i) => 'paragraph line $i').join('\n')}\n\n';

Future<void> _pump(
  WidgetTester tester,
  StreamingMarkdownController controller, {
  Widget? Function(int)? afterBlock,
}) {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StreamingMarkdownView(
          controller: controller,
          maxRenderBlockLines: 40,
          afterBlock: afterBlock,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a giant code fence renders lazily by segment', (tester) async {
    final controller = StreamingMarkdownController(
      initialText: _codeDocument(400),
    );
    addTearDown(controller.dispose);

    await _pump(tester, controller);
    await tester.pumpAndSettle();

    final initialBodies = find.byType(MarkdownBody).evaluate().length;
    expect(initialBodies, lessThan(10));
    expect(controller.settledBlockCount, 1);

    await tester.drag(find.byType(ListView), const Offset(0, 4000));
    await tester.pumpAndSettle();

    expect(
      find.byType(MarkdownBody).evaluate().length,
      greaterThan(initialBodies),
    );
  });

  testWidgets('an attached row renders once after the final code segment', (
    tester,
  ) async {
    final controller = StreamingMarkdownController(
      initialText: _codeDocument(200),
    );
    addTearDown(controller.dispose);

    await _pump(
      tester,
      controller,
      afterBlock: (index) => index == 0 ? const Text('attached row') : null,
    );
    await tester.pumpAndSettle();

    final newestCode = tester
        .getTopLeft(find.textContaining('code line 199'))
        .dy;
    final attached = tester.getTopLeft(find.text('attached row')).dy;
    expect(newestCode, lessThan(attached));
    expect(find.text('attached row'), findsOneWidget);
  });

  testWidgets('a giant table renders lazily by row segment', (tester) async {
    final rows = List.generate(300, (i) => '| $i | service-$i |').join('\n');
    final controller = StreamingMarkdownController(
      initialText: '| id | name |\n|---:|---|\n$rows\n\n',
    );
    addTearDown(controller.dispose);

    await _pump(tester, controller);
    await tester.pumpAndSettle();

    final initialBodies = find.byType(MarkdownBody).evaluate().length;
    expect(initialBodies, lessThan(8));
    expect(controller.settledBlockCount, 1);

    await tester.drag(find.byType(ListView), const Offset(0, 5000));
    await tester.pumpAndSettle();

    expect(
      find.byType(MarkdownBody).evaluate().length,
      greaterThan(initialBodies),
    );
  });

  testWidgets('a giant paragraph renders lazily by line segment', (
    tester,
  ) async {
    final controller = StreamingMarkdownController(
      initialText: _paragraphDocument(400),
    );
    addTearDown(controller.dispose);

    await _pump(tester, controller);
    await tester.pumpAndSettle();

    final initialBodies = find.byType(MarkdownBody).evaluate().length;
    expect(initialBodies, lessThan(8));
    expect(controller.settledBlockCount, 1);

    await tester.drag(find.byType(ListView), const Offset(0, 5000));
    await tester.pumpAndSettle();

    expect(
      find.byType(MarkdownBody).evaluate().length,
      greaterThan(initialBodies),
    );
  });

  testWidgets('a giant list keeps continuations with their items', (
    tester,
  ) async {
    final list = [
      for (var i = 0; i < 120; i++) ...['- list item $i', '  continuation $i'],
    ].join('\n');
    final controller = StreamingMarkdownController(initialText: '$list\n\n');
    addTearDown(controller.dispose);

    await _pump(tester, controller);
    await tester.pumpAndSettle();

    expect(controller.settledBlockCount, 1);
    expect(find.textContaining('list item 0'), findsNothing);

    controller.scrollToBlock(0, characterOffset: list.indexOf('item 0'));
    await tester.pumpAndSettle();

    expect(find.textContaining('list item 0'), findsOneWidget);
    expect(find.textContaining('continuation 0'), findsOneWidget);
  });

  testWidgets('new logical blocks append after a split code block', (
    tester,
  ) async {
    final controller = StreamingMarkdownController(
      initialText: _codeDocument(400),
    );
    addTearDown(controller.dispose);

    await _pump(
      tester,
      controller,
      afterBlock: (index) => index == 0 ? const Text('attached row') : null,
    );
    await tester.pumpAndSettle();
    controller.append('New paragraph.\n\n');
    await tester.pumpAndSettle();

    expect(controller.settledBlockCount, 2);
    expect(find.text('New paragraph.'), findsOneWidget);
    expect(find.text('attached row'), findsOneWidget);

    final attached = tester.getTopLeft(find.text('attached row')).dy;
    final newParagraph = tester.getTopLeft(find.text('New paragraph.')).dy;
    expect(attached, lessThan(newParagraph));
  });

  testWidgets('reset invalidates split render segments immediately', (
    tester,
  ) async {
    final controller = StreamingMarkdownController(
      initialText: _codeDocument(400),
    );
    addTearDown(controller.dispose);

    await _pump(tester, controller);
    await tester.pumpAndSettle();
    controller
      ..reset()
      ..append('Fresh paragraph.\n\nSecond paragraph.\n\n');
    await tester.pumpAndSettle();

    expect(controller.settledBlockCount, 2);
    expect(find.textContaining('code line'), findsNothing);
    expect(find.text('Fresh paragraph.'), findsOneWidget);
    expect(find.text('Second paragraph.'), findsOneWidget);
  });
}
