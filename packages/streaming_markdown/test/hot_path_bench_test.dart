/// Measures the per-frame cost of the getters that sit on the streaming hot
/// path, so a regression that reintroduces a full copy shows up as a number
/// rather than as "the transcript feels sluggish on long sessions".
///
/// These are not assertions about wall-clock time — CI machines are too noisy
/// for that. They assert the *shape* of the cost: accessing settled blocks
/// must not scale with how many blocks have already settled.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/src/block_splitter.dart';

/// A transcript of [blocks] paragraphs, in the shape the splitter sees it:
/// appended in small chunks with blank lines between blocks.
IncrementalSplitter _transcriptOf(int blocks) {
  final splitter = IncrementalSplitter();
  for (var i = 0; i < blocks; i++) {
    splitter.append(
      'Paragraph number $i with enough text to be realistic.\n\n',
    );
  }
  return splitter;
}

/// Nanoseconds per [blocks] access, averaged over [reps].
double _nsPerAccess(IncrementalSplitter splitter, int reps) {
  // Warm up, so JIT compilation is not attributed to the first size measured.
  for (var i = 0; i < 200; i++) {
    splitter.blocks.length;
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < reps; i++) {
    splitter.blocks.length;
  }
  sw.stop();
  return sw.elapsedMicroseconds * 1000 / reps;
}

void main() {
  group('blocks getter', () {
    test('does not copy: cost is flat in the number of settled blocks', () {
      const reps = 20000;
      final small = _transcriptOf(10);
      final large = _transcriptOf(2000);

      final smallNs = _nsPerAccess(small, reps);
      final largeNs = _nsPerAccess(large, reps);

      printOnFailure(
        'blocks getter: ${smallNs.toStringAsFixed(1)} ns @10 blocks, '
        '${largeNs.toStringAsFixed(1)} ns @2000 blocks',
      );

      // A copying getter is ~200x slower at 2000 blocks than at 10. A view is
      // within noise. The threshold is loose enough for a loaded CI box and
      // still an order of magnitude below the copying behaviour.
      expect(
        largeNs,
        lessThan(smallNs * 10 + 500),
        reason: 'blocks getter appears to copy the backing list',
      );
    });

    test('exposes a live view that still refuses mutation', () {
      final splitter = _transcriptOf(3);
      final view = splitter.blocks;

      expect(view.length, 3);
      expect(() => view.add('nope'), throwsUnsupportedError);
      expect(() => view.removeLast(), throwsUnsupportedError);

      // A view, not a snapshot: later appends are visible through it. This is
      // the behaviour change a copy was hiding, and every caller reads the
      // getter fresh, so it is the cheaper contract.
      splitter.append('One more block here.\n\n');
      expect(view.length, 4);
    });
  });

  group('textLength', () {
    test('agrees with materialising the text, across fences and blanks', () {
      final splitter = IncrementalSplitter();
      final chunks = [
        'First paragraph.\n\n',
        '```dart\nvoid main() {}\n```\n\n',
        'Trailing text that is still growing',
      ];
      for (final chunk in chunks) {
        splitter.append(chunk);
        expect(
          splitter.textLength,
          splitter.text.length,
          reason: 'diverged after appending ${chunk.length} chars',
        );
      }
    });

    test('is flat in transcript size, unlike materialising the text', () {
      const reps = 20000;
      final large = _transcriptOf(2000);

      for (var i = 0; i < 200; i++) {
        large.textLength;
      }
      final sw = Stopwatch()..start();
      for (var i = 0; i < reps; i++) {
        large.textLength;
      }
      sw.stop();
      final ns = sw.elapsedMicroseconds * 1000 / reps;

      printOnFailure('textLength: ${ns.toStringAsFixed(1)} ns @2000 blocks');

      // Joining 2000 blocks costs tens of microseconds. Reading a counter is
      // tens of nanoseconds. Anything under a microsecond proves no join.
      expect(
        ns,
        lessThan(1000),
        reason: 'textLength appears to materialise the transcript',
      );
    });

    test('resets with the splitter', () {
      final splitter = _transcriptOf(5);
      expect(splitter.textLength, greaterThan(0));
      splitter.reset();
      expect(splitter.textLength, 0);
      expect(splitter.text, isEmpty);
    });
  });
}
