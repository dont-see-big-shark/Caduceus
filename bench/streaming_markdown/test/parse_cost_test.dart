/// Device-free measurement of parser workload.
///
/// This is the half of Spike A that needs no phone, no GPU, and no profile
/// build. It models exactly the scheduling each strategy performs and counts
/// characters handed to the Markdown parser. The asymptotic result is a
/// property of the algorithm, not of the hardware, so it is asserted here as a
/// test rather than eyeballed on a device.
///
/// Frame timings still require a real device — see `lib/main.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown_bench/block_splitter.dart';
import 'package:streaming_markdown_bench/corpus.dart';

/// Characters parsed by the naive strategy: one rebuild per token, whole
/// buffer re-parsed each time.
int naiveCost(List<String> tokens) {
  var buffer = 0;
  var cost = 0;
  for (final token in tokens) {
    buffer += token.length;
    cost += buffer;
  }
  return cost;
}

/// Characters parsed by the incremental strategy.
///
/// [tokensPerFrame] models frame-budget coalescing: at 60 tok/s and 60 fps it
/// is ~1, under a fast local model it is much higher. Either way the settled
/// blocks are parsed exactly once.
({int cost, int rebuilds}) incrementalCost(
  List<String> tokens, {
  int tokensPerFrame = 1,
}) {
  final buffer = StringBuffer();
  var cost = 0;
  var rebuilds = 0;
  var settled = 0;
  var pending = 0;

  void flush() {
    final split = splitMarkdown(buffer.toString());
    for (var i = settled; i < split.stable.length; i++) {
      cost += split.stable[i].length; // parsed once, ever
    }
    settled = split.stable.length;
    cost += split.tail.length; // the only text re-parsed
    rebuilds++;
  }

  for (final token in tokens) {
    buffer.write(token);
    if (++pending >= tokensPerFrame) {
      pending = 0;
      flush();
    }
  }
  if (pending > 0) flush();

  return (cost: cost, rebuilds: rebuilds);
}

void main() {
  final tokens = defaultTokenStream();
  final totalChars = tokens.fold<int>(0, (s, t) => s + t.length);

  test('corpus is the expected size', () {
    expect(tokens.length, greaterThan(2500));
    expect(tokens.length, lessThan(4000));
    expect(totalChars, greaterThan(10000));
  });

  test('naive cost matches the analytic model', () {
    final cost = naiveCost(tokens);
    // One rebuild per token, each re-parsing the whole buffer. The buffer grows
    // linearly, so the total is tokens x chars / 2 — not chars^2/2, because
    // rebuilds are counted per token (~3.5 chars) and not per character.
    final expected = tokens.length * totalChars / 2;
    expect(cost, closeTo(expected, expected * 0.05));
  });

  test('naive is quadratic and incremental is linear, under scaling', () {
    // The asymptotic claim, measured rather than asserted from a formula:
    // double the response, and naive should roughly quadruple while
    // incremental should roughly double.
    List<String> streamOf(int chars) => tokenize(buildDocument(targetChars: chars));

    final small = streamOf(6000);
    final large = streamOf(12000);

    final naiveRatio = naiveCost(large) / naiveCost(small);
    final incRatio = incrementalCost(large).cost / incrementalCost(small).cost;

    // ignore: avoid_print
    print('scaling 2x — naive: ${naiveRatio.toStringAsFixed(2)}x, '
        'incremental: ${incRatio.toStringAsFixed(2)}x');

    expect(naiveRatio, greaterThan(3.4)); // ~4x
    expect(incRatio, lessThan(2.6)); // ~2x
  });

  test('incremental strategy is linear in response length', () {
    final result = incrementalCost(tokens, tokensPerFrame: 1);
    // Every character is parsed once as part of a settled block, plus the tail
    // is re-parsed each frame. The tail is bounded by block size, not by
    // response length — that is the whole point.
    expect(result.cost, lessThan(totalChars * 60));
  });

  test('incremental beats naive by a wide margin', () {
    final naive = naiveCost(tokens);
    final incremental = incrementalCost(tokens, tokensPerFrame: 1).cost;
    final ratio = naive / incremental;

    // ignore: avoid_print
    print('parse cost — naive: $naive chars, '
        'incremental: $incremental chars, ratio: ${ratio.toStringAsFixed(1)}x');

    expect(ratio, greaterThan(10));
  });

  test('frame coalescing cuts rebuild count under a fast stream', () {
    final perToken = incrementalCost(tokens, tokensPerFrame: 1);
    final coalesced = incrementalCost(tokens, tokensPerFrame: 15);

    expect(coalesced.rebuilds, lessThan(perToken.rebuilds / 10));
    expect(coalesced.cost, lessThan(perToken.cost));

    // ignore: avoid_print
    print('rebuilds — per-token: ${perToken.rebuilds}, '
        'coalesced(15): ${coalesced.rebuilds}');
  });

  test('the tail stays bounded regardless of how long the response gets', () {
    // The claim that makes the strategy linear: tail size is a function of
    // block size, not of total length. Verify across the whole stream.
    final buffer = StringBuffer();
    var maxTail = 0;
    for (final token in tokens) {
      buffer.write(token);
      final tail = splitMarkdown(buffer.toString()).tail.length;
      if (tail > maxTail) maxTail = tail;
    }
    expect(maxTail, lessThan(totalChars / 4));

    // ignore: avoid_print
    print('max tail: $maxTail chars of $totalChars total');
  });
}
