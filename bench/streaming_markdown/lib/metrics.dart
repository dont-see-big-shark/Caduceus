/// Measurement for the streaming-render benchmark.
///
/// Two independent kinds of number are collected:
///
///  * **Parse cost** — how many characters each strategy hands to the Markdown
///    parser over the run. This is device-independent and deterministic, so it
///    can be asserted in a plain `flutter test` with no GPU involved. It is the
///    direct evidence of quadratic vs linear behaviour.
///
///  * **Frame timings** — what the user actually feels. Requires a real device;
///    numbers from a simulator or a debug build are not meaningful.
library;

import 'package:flutter/scheduler.dart';

/// Counts work handed to the Markdown parser.
class ParseCost {
  int rebuilds = 0;
  int blocksParsed = 0;
  int charsParsed = 0;

  void record(int chars) {
    rebuilds++;
    blocksParsed++;
    charsParsed += chars;
  }

  void reset() {
    rebuilds = 0;
    blocksParsed = 0;
    charsParsed = 0;
  }

  @override
  String toString() =>
      'rebuilds=$rebuilds blocks=$blocksParsed chars=$charsParsed';
}

/// One run's frame statistics.
class FrameStats {
  FrameStats({
    required this.frameCount,
    required this.jankFrames,
    required this.severeJankFrames,
    required this.worstFrameMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.wallClockMs,
  });

  final int frameCount;

  /// Frames over the 60 Hz budget (16.67 ms).
  final int jankFrames;

  /// Frames over two budgets (33.3 ms) — visible stutter.
  final int severeJankFrames;

  final double worstFrameMs;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final int wallClockMs;

  double get jankRatio => frameCount == 0 ? 0 : jankFrames / frameCount;

  Map<String, Object> toJson() => {
        'frameCount': frameCount,
        'jankFrames': jankFrames,
        'severeJankFrames': severeJankFrames,
        'jankRatioPct': double.parse((jankRatio * 100).toStringAsFixed(1)),
        'worstFrameMs': _r(worstFrameMs),
        'p50Ms': _r(p50Ms),
        'p95Ms': _r(p95Ms),
        'p99Ms': _r(p99Ms),
        'wallClockMs': wallClockMs,
      };

  static double _r(double v) => double.parse(v.toStringAsFixed(2));
}

/// Collects [FrameTiming] callbacks for the duration of a run.
///
/// Uses total span (vsync to raster finish) rather than build time alone —
/// a strategy that moves work from the UI thread to the raster thread has not
/// actually made anything faster for the user.
class FrameRecorder {
  final List<double> _totalMs = [];
  Stopwatch? _clock;
  bool _listening = false;

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _totalMs.add(t.totalSpan.inMicroseconds / 1000.0);
    }
  }

  void start() {
    if (_listening) return;
    _totalMs.clear();
    _clock = Stopwatch()..start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _listening = true;
  }

  FrameStats stop() {
    if (_listening) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _listening = false;
    }
    final elapsed = _clock?.elapsedMilliseconds ?? 0;
    _clock?.stop();

    if (_totalMs.isEmpty) {
      return FrameStats(
        frameCount: 0,
        jankFrames: 0,
        severeJankFrames: 0,
        worstFrameMs: 0,
        p50Ms: 0,
        p95Ms: 0,
        p99Ms: 0,
        wallClockMs: elapsed,
      );
    }

    final sorted = List<double>.from(_totalMs)..sort();
    return FrameStats(
      frameCount: sorted.length,
      jankFrames: sorted.where((m) => m > 16.67).length,
      severeJankFrames: sorted.where((m) => m > 33.34).length,
      worstFrameMs: sorted.last,
      p50Ms: _percentile(sorted, 0.50),
      p95Ms: _percentile(sorted, 0.95),
      p99Ms: _percentile(sorted, 0.99),
      wallClockMs: elapsed,
    );
  }

  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0;
    final idx = ((sorted.length - 1) * p).round();
    return sorted[idx];
  }
}

/// A complete result for one (strategy, rate) pair.
class RunResult {
  RunResult({
    required this.strategy,
    required this.rateLabel,
    required this.frames,
    required this.parse,
    required this.expectedMs,
  });

  final String strategy;
  final String rateLabel;
  final FrameStats frames;
  final ParseCost parse;

  /// How long the token stream should have taken, from the emit rate alone.
  /// Zero for the unthrottled rate, where there is no analytic expectation.
  final int expectedMs;

  /// Ratio of actual to expected wall clock. Around 1.0 for a healthy run.
  double get clockDrift =>
      expectedMs == 0 ? 1.0 : frames.wallClockMs / expectedMs;

  /// Whether this run can be trusted.
  ///
  /// This check exists because a background or occluded window on macOS gets
  /// its timers coalesced and its frame production suspended. The run still
  /// completes and still emits perfectly plausible JSON — it is simply not a
  /// measurement of anything. A benchmark that can fail silently is worse than
  /// no benchmark, so every run declares its own validity.
  ///
  /// Two independent signals:
  ///  * the stream took much longer than its own emit rate implies
  ///  * frames were produced far below the rate the rebuild count required
  /// True when the renderer could not keep up with its own token stream.
  ///
  /// This is a *result*, not a fault: the event loop was blocked by build and
  /// raster work, so the emit timer fired late. Distinguished from external
  /// throttling by the frames being expensive — a napped app produces cheap
  /// frames slowly, a saturated one produces expensive frames as fast as it can.
  bool get saturated =>
      expectedMs > 0 && clockDrift > 1.25 && frames.p50Ms > 8.0;

  bool get valid {
    // Saturation is a legitimate measurement — indeed the interesting one.
    if (saturated) return true;
    if (expectedMs > 0 && clockDrift > 1.25) return false;
    // A rebuild can only be shown by a frame. Materially fewer frames than
    // rebuilds means frames were being dropped by the compositor, not by us.
    if (parse.rebuilds > 20 && frames.frameCount < parse.rebuilds * 0.5) {
      return false;
    }
    return true;
  }

  String get invalidReason {
    if (valid) return '';
    if (expectedMs > 0 && clockDrift > 1.25) {
      return 'wall clock ${clockDrift.toStringAsFixed(1)}x expected '
          '(${frames.wallClockMs}ms vs ${expectedMs}ms) with cheap frames '
          '(p50 ${frames.p50Ms}ms) — externally throttled, not saturated';
    }
    if (parse.rebuilds > 20 && frames.frameCount < parse.rebuilds * 0.5) {
      return 'only ${frames.frameCount} frames for ${parse.rebuilds} rebuilds '
          '— frame production suspended; is the window visible?';
    }
    return '';
  }

  Map<String, Object> toJson() => {
        'strategy': strategy,
        'rate': rateLabel,
        'valid': valid,
        'saturated': saturated,
        if (!valid) 'invalidReason': invalidReason,
        'expectedMs': expectedMs,
        'clockDrift': double.parse(clockDrift.toStringAsFixed(2)),
        'parse': {
          'rebuilds': parse.rebuilds,
          'blocksParsed': parse.blocksParsed,
          'charsParsed': parse.charsParsed,
        },
        'frames': frames.toJson(),
      };
}
