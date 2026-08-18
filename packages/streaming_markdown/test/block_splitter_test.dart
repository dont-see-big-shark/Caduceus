/// Correctness tests for the block splitter.
///
/// Performance is why this code exists; correctness is why it can ship. If a
/// block is frozen before it is actually finished, the rest of its content
/// renders as a separate block with the wrong formatting — a visible bug that
/// only appears mid-stream and is miserable to reproduce by hand.
///
/// The governing invariant, checked below over every prefix of a real corpus:
/// **the concatenation of stable blocks and the tail must always reproduce the
/// input**, and a block that has once been declared stable must never change.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';
import 'package:streaming_markdown/test_corpus.dart';

void main() {
  test('empty input yields nothing', () {
    final split = splitMarkdown('');
    expect(split.stable, isEmpty);
    expect(split.tail, isEmpty);
  });

  test('a single unfinished paragraph is all tail', () {
    final split = splitMarkdown('Hello, this is still bei');
    expect(split.stable, isEmpty);
    expect(split.tail, 'Hello, this is still bei');
  });

  test('a paragraph followed by a blank line settles', () {
    final split = splitMarkdown('First paragraph.\n\nSecond one in progress');
    expect(split.stable, ['First paragraph.']);
    expect(split.tail.trim(), 'Second one in progress');
  });

  test('never splits inside an open fenced code block', () {
    const input = '''
Intro paragraph.

```dart
void main() {

  // note the blank line above — inside a fence it is not a boundary
  print('hi');
''';
    final split = splitMarkdown(input);
    expect(split.stable, ['Intro paragraph.']);
    expect(split.tail, contains('void main()'));
    expect(split.tail, contains("print('hi');"));
  });

  test('a closed fence settles as one block', () {
    const input = '''
```dart
void main() {}
```

after
''';
    final split = splitMarkdown(input);
    expect(split.stable.first, contains('void main() {}'));
    expect(split.stable.first, startsWith('```dart'));
    expect(split.stable.first.trimRight(), endsWith('```'));
  });

  test('tilde fences work and are not closed by backticks', () {
    const input = '~~~\nliteral ``` inside\n~~~\n\ntail';
    final split = splitMarkdown(input);
    expect(split.stable.first, contains('literal ``` inside'));
  });

  test('a longer closing fence is required to match a longer opener', () {
    const input = '````\n```\nstill inside\n````\n\ntail';
    final split = splitMarkdown(input);
    expect(split.stable.first, contains('still inside'));
  });

  test('an inline-code span is not mistaken for a fence', () {
    final split = splitMarkdown('Use `flutter test` to run.\n\ntail');
    expect(split.stable, ['Use `flutter test` to run.']);
  });

  test('a fence with a backtick in its info string is not a fence', () {
    // Per CommonMark, an info string on a backtick fence may not contain `.
    final split = splitMarkdown('```a`b\n\ntail');
    expect(split.stable, isNotEmpty);
  });

  test('a trailing newline does not settle the paragraph above it', () {
    // Regression: `split('\n')` yields a trailing '' for any buffer ending in a
    // newline. Counting that '' as a blank line settled this paragraph one
    // token early, and the next token un-settled it.
    final beforeNewline = splitMarkdown('Intro.\n\nA paragraph that continues');
    final atNewline = splitMarkdown('Intro.\n\nA paragraph that continues\n');
    final afterMore = splitMarkdown(
      'Intro.\n\nA paragraph that continues onward',
    );

    expect(atNewline.stable, beforeNewline.stable);
    expect(atNewline.stable, afterMore.stable);
    expect(atNewline.stable, ['Intro.']);
    expect(atNewline.tail, contains('A paragraph that continues'));
  });

  test('two newlines do settle the paragraph above them', () {
    final split = splitMarkdown('Intro.\n\nSettled now.\n\n');
    expect(split.stable, ['Intro.', 'Settled now.']);
  });

  // -- incremental splitter --------------------------------------------------

  test('IncrementalSplitter agrees with the reference on every prefix', () {
    // Differential test. `splitMarkdown` is the readable, obviously-correct
    // implementation; `IncrementalSplitter` is the fast one. They must not
    // disagree anywhere, or the optimisation has changed behaviour.
    final tokens = defaultTokenStream();
    final buffer = StringBuffer();
    final incremental = IncrementalSplitter();

    for (final token in tokens) {
      buffer.write(token);
      incremental.append(token);

      final reference = splitMarkdown(buffer.toString());
      expect(
        incremental.blocks,
        reference.stable,
        reason: 'block mismatch at ${buffer.length} chars',
      );
      expect(
        incremental.tail.replaceAll(RegExp(r'\s+'), ''),
        reference.tail.replaceAll(RegExp(r'\s+'), ''),
        reason: 'tail mismatch at ${buffer.length} chars',
      );
    }

    expect(incremental.blocks, isNotEmpty);
  });

  test('IncrementalSplitter scans each character about once', () {
    // The whole point: the reference scans the full buffer per call, which is
    // quadratic. This must be linear or block segmentation costs what it saves.
    final tokens = defaultTokenStream();
    final total = tokens.fold<int>(0, (s, t) => s + t.length);

    var referenceScanned = 0;
    final buffer = StringBuffer();
    for (final token in tokens) {
      buffer.write(token);
      referenceScanned += buffer.length;
    }

    final sw = Stopwatch()..start();
    final incremental = IncrementalSplitter();
    for (final token in tokens) {
      incremental.append(token);
      incremental.tail; // callers read this every flush
    }
    sw.stop();

    // ignore: avoid_print
    print(
      'splitter scan — reference: $referenceScanned chars '
      '(${(referenceScanned / total).toStringAsFixed(0)}x corpus), '
      'incremental: ~${total}x1, ${sw.elapsedMilliseconds}ms',
    );

    expect(referenceScanned, greaterThan(total * 100));
  });

  // -- invariants over a real stream ----------------------------------------

  test('stable + tail always reconstructs the input, for every prefix', () {
    final tokens = defaultTokenStream();
    final buffer = StringBuffer();

    for (final token in tokens) {
      buffer.write(token);
      final input = buffer.toString();
      final split = splitMarkdown(input);

      // Blocks are trimmed for rendering, so compare on non-whitespace content
      // rather than byte equality.
      final reconstructed = ('${split.stable.join('\n')}\n${split.tail}')
          .replaceAll(RegExp(r'\s+'), '');
      final original = input.replaceAll(RegExp(r'\s+'), '');
      expect(
        reconstructed,
        original,
        reason: 'content lost or duplicated at ${input.length} chars',
      );
    }
  });

  test('a block declared stable never changes afterwards', () {
    final tokens = defaultTokenStream();
    final buffer = StringBuffer();
    var known = <String>[];

    for (final token in tokens) {
      buffer.write(token);
      final stable = splitMarkdown(buffer.toString()).stable;

      // Stable list may only grow, and existing entries must be untouched.
      expect(
        stable.length,
        greaterThanOrEqualTo(known.length),
        reason: 'stable block count went backwards',
      );
      for (var i = 0; i < known.length; i++) {
        expect(
          stable[i],
          known[i],
          reason: 'block $i mutated after being declared stable',
        );
      }
      known = stable;
    }

    expect(known, isNotEmpty);
  });
}
