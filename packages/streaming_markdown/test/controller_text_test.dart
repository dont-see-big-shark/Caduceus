import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

void main() {
  test('text is empty before any content arrives', () {
    final controller = StreamingMarkdownController();

    expect(controller.text, isEmpty);
  });

  test('text combines settled blocks and the active tail', () {
    final controller = StreamingMarkdownController();

    controller
      ..append('First paragraph.\n\n')
      ..append('Second paragraph.');

    expect(controller.text, 'First paragraph.\n\nSecond paragraph.');
  });

  test('text keeps a block boundary available after a reset-and-rebuild', () {
    final controller = StreamingMarkdownController();
    controller.append('Prompt.\n\n');
    final boundary = controller.text;

    controller
      ..reset()
      ..append(boundary)
      ..append('Corrected answer.');

    expect(controller.text, 'Prompt.\n\nCorrected answer.');
  });

  test('reset clears both settled blocks and text', () {
    final controller = StreamingMarkdownController(initialText: 'Old text.');

    controller.reset();

    expect(controller.text, isEmpty);
    expect(controller.settledBlockCount, isZero);
  });
}
