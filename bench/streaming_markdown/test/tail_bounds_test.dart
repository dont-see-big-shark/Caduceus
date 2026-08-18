/// Stress-tests the claim the framework recommendation rests on:
/// *per-frame parse cost is bounded, so it does not grow with response length.*
///
/// That claim is only as good as the assumption that blocks stay small. The
/// mixed corpus has a blank line every few lines, which makes it true almost by
/// construction. Agent transcripts do not: "show me the file" emits one fence
/// hundreds of lines long, and a fence has no internal boundary, so the tail
/// grows to the size of the whole block.
///
/// These tests find where the bound actually holds and where it breaks, and
/// attach absolute microsecond costs so "bounded" can be judged against a frame
/// budget rather than against another ratio.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:streaming_markdown_bench/block_splitter.dart';
import 'package:streaming_markdown_bench/corpus.dart';

/// Median microseconds to parse [text], over [reps] runs after a warm-up.
double parseMicros(String text, {int reps = 40}) {
  final doc = md.Document(extensionSet: md.ExtensionSet.gitHubWeb);
  List<String> lines() => text.split('\n');
  for (var i = 0; i < 5; i++) {
    doc.parseLines(lines());
  }
  final samples = <int>[];
  for (var i = 0; i < reps; i++) {
    final sw = Stopwatch()..start();
    md.Document(extensionSet: md.ExtensionSet.gitHubWeb).parseLines(lines());
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2].toDouble();
}

/// Largest tail the splitter ever holds while streaming [document].
({int maxTail, int blocks}) streamMaxTail(String document) {
  final splitter = IncrementalSplitter();
  var maxTail = 0;
  for (final token in tokenize(document)) {
    splitter.append(token);
    final t = splitter.tail.length;
    if (t > maxTail) maxTail = t;
  }
  return (maxTail: maxTail, blocks: splitter.blockCount);
}

void main() {
  test('absolute parse cost by input size', () {
    // The recommendation assumed ~500 chars is "microseconds". Check it.
    final sizes = <String, String>{
      'typical tail (492 ch)': buildDocument(targetChars: 492),
      '2 KB': buildDocument(targetChars: 2000),
      '8 KB': buildDocument(targetChars: 8000),
      '16 KB': buildDocument(targetChars: 16000),
      '32 KB': buildDocument(targetChars: 32000),
    };
    // ignore: avoid_print
    print('\n--- parse cost vs input size (median of 40) ---');
    for (final entry in sizes.entries) {
      final us = parseMicros(entry.value);
      // ignore: avoid_print
      print('${entry.key.padRight(24)} ${entry.value.length.toString().padLeft(6)} ch  '
          '${us.toStringAsFixed(0).padLeft(7)} us  '
          '${(us / 16670 * 100).toStringAsFixed(2)}% of a 60fps frame');
    }
  });

  test('mixed corpus keeps the tail small', () {
    final r = streamMaxTail(buildDocument());
    // ignore: avoid_print
    print('mixed corpus     — max tail ${r.maxTail} ch across ${r.blocks} blocks');
    expect(r.maxTail, lessThan(1500));
  });

  test('ONE BIG CODE FENCE — the bound does not hold', () {
    final doc = buildPathologicalDocument(lines: 400);
    final r = streamMaxTail(doc);
    final us = parseMicros('```dart\n${'x' * r.maxTail}\n```');

    // ignore: avoid_print
    print('400-line fence   — doc ${doc.length} ch, max tail ${r.maxTail} ch, '
        '${r.blocks} blocks, tail parse ~${us.toStringAsFixed(0)} us '
        '(${(us / 16670 * 100).toStringAsFixed(1)}% of a frame)');

    // The tail grows to the whole fence: segmentation buys nothing here.
    expect(r.maxTail, greaterThan(doc.length * 0.8),
        reason: 'a fence has no internal boundary, so the tail is the block');
  });

  test('LONG TABLE — same failure mode', () {
    final doc = buildWideTableDocument(rows: 300);
    final r = streamMaxTail(doc);
    // ignore: avoid_print
    print('300-row table    — doc ${doc.length} ch, max tail ${r.maxTail} ch, '
        '${r.blocks} blocks');
    expect(r.maxTail, greaterThan(doc.length * 0.8));
  });

  test('worst-case per-frame cost against the frame budget', () {
    // Bounded is meaningless without a number. What does the worst realistic
    // block actually cost per frame, and how much of 16.67 ms does it eat?
    for (final lines in const [100, 200, 400, 800]) {
      final doc = buildPathologicalDocument(lines: lines);
      final r = streamMaxTail(doc);
      final us = parseMicros(doc);
      // ignore: avoid_print
      print('fence ${lines.toString().padLeft(3)} lines — tail ${r.maxTail.toString().padLeft(6)} ch  '
          'parse ${us.toStringAsFixed(0).padLeft(7)} us  '
          '${(us / 16670 * 100).toStringAsFixed(1)}% of a frame');
    }
  });
}
