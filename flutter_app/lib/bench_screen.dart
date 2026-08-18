/// In-app render benchmark.
///
/// Measures the production widget stack — [StreamingMarkdownView] driven by a
/// [SessionConsole], the same objects a real session uses — rather than a lab
/// harness. The earlier standalone harness measured a simplified copy; this
/// measures what ships.
///
///   flutter run -d macos --profile --dart-define=BENCH=true
///
/// Profile mode only. Debug numbers are meaningless (unoptimised Dart,
/// assertions on).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:streaming_markdown/streaming_markdown.dart';
import 'package:streaming_markdown/test_corpus.dart';

import 'backends/hermes_mapping.dart';
import 'console_view.dart';
import 'workspace.dart';

class BenchScreen extends StatefulWidget {
  const BenchScreen({super.key});

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> {
  final _console = SessionConsole(persistedId: 'bench', liveId: 'bench');
  final _results = <Map<String, Object>>[];
  final _frames = <double>[];

  /// Build (UI thread) and raster (GPU thread) halves of each frame, so an
  /// over-budget frame can be attributed instead of guessed at.
  final _build = <double>[];
  final _raster = <double>[];
  String _status = 'starting…';
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _console.historyLoaded = true;
    SchedulerBinding.instance.addTimingsCallback(_onFrames);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  void _onFrames(List<FrameTiming> timings) {
    if (!_recording) return;
    for (final t in timings) {
      // totalSpan runs from vsync to raster end and therefore includes time
      // the frame spent *waiting* — scheduling latency, not work. A frame with
      // 4 ms of build and 16 ms of raster was measured at 167 ms of totalSpan
      // here, which says something about the compositor and nothing about the
      // renderer. Work is build and raster; totalSpan is kept alongside so the
      // difference stays visible.
      _frames.add(t.totalSpan.inMicroseconds / 1000.0);
      _build.add(t.buildDuration.inMicroseconds / 1000.0);
      _raster.add(t.rasterDuration.inMicroseconds / 1000.0);
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrames);
    _console.dispose();
    super.dispose();
  }

  /// Feeds tokens as `message.delta` events — the exact path a live turn takes,
  /// including the envelope unwrap and the answer/reasoning split.
  Future<void> _stream(List<String> tokens, Duration delay) async {
    for (final token in tokens) {
      await Future<void>.delayed(delay);
      _console.handle(
        agentEventFromHermes(
          'bench',
          GatewayEvent(
            type: 'message.delta',
            sessionId: 'bench',
            payload: {'text': token},
          ),
        )!,
      );
    }
  }

  /// Preloads a transcript the size of a long working session.
  ///
  /// Every settled block is kept alive as a cached widget for the life of the
  /// session — the trade that makes streaming cheap. Whether it is still the
  /// right trade after a few hundred messages is a different question, and it
  /// is the one nobody had measured.
  Future<int> _preload(int messages) async {
    _console.markdown.reset();
    final corpus = defaultTokenStream().join();
    for (var i = 0; i < messages; i++) {
      _console.markdown.append('\n\n---\n\n**You:** question $i\n\n');
      _console.markdown.append(corpus);
    }
    // Let the view settle the whole backlog before measuring anything.
    await Future<void>.delayed(const Duration(seconds: 2));
    return _console.markdown.settledBlockCount;
  }

  Future<void> _runOne(
    String label,
    Duration delay,
    int expectedMs, {
    int preloadMessages = 0,
  }) async {
    setState(() => _status = 'running $label…');
    // Fresh console per run so block caching starts empty.
    _console.markdown.reset();
    var preloaded = 0;
    if (preloadMessages > 0) {
      preloaded = await _preload(preloadMessages);
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Resident set before and after. Not a heap measurement — RSS includes
    // the Flutter engine, textures and the Dart heap together — but it is the
    // number that decides whether a long session is a problem on a real
    // machine, and it needs no external tooling to read.
    final rssBefore = ProcessInfo.currentRss;

    _frames.clear();
    _build.clear();
    _raster.clear();
    _recording = true;
    final clock = Stopwatch()..start();
    await _stream(defaultTokenStream(), delay);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    clock.stop();
    _recording = false;

    // Where the worst frame lands matters more than its value: at the start
    // it is leftover setup bleeding into the window, spread through the run it
    // is something the renderer does periodically.
    var worstAt = 0;
    for (var i = 0; i < _frames.length; i++) {
      if (_frames[i] > _frames[worstAt]) worstAt = i;
    }
    final overBudget = <int>[];
    for (var i = 0; i < _frames.length; i++) {
      if (_frames[i] > 16.67) overBudget.add(i);
    }

    // Attribute the over-budget frames: UI-thread work is ours to fix, raster
    // is the GPU or the compositor and a different problem entirely.
    var uiBound = 0, rasterBound = 0;
    var worstBuild = 0.0, worstRaster = 0.0;
    for (var i = 0; i < _frames.length; i++) {
      if (_frames[i] <= 16.67) continue;
      final b = i < _build.length ? _build[i] : 0.0;
      final r = i < _raster.length ? _raster[i] : 0.0;
      if (b > r) {
        uiBound++;
      } else {
        rasterBound++;
      }
      if (b > worstBuild) worstBuild = b;
      if (r > worstRaster) worstRaster = r;
    }

    // The frame's cost is the larger of its two halves: build and raster run
    // on different threads and either one blowing the budget drops a frame.
    // This — not totalSpan — is what "jank" has to mean.
    final work = <double>[
      for (var i = 0; i < _frames.length; i++)
        (i < _build.length ? _build[i] : 0.0) >
                (i < _raster.length ? _raster[i] : 0.0)
            ? _build[i]
            : _raster[i],
    ];
    final sorted = List<double>.from(work)..sort();
    double pct(double p) =>
        sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()];
    final jank = sorted.where((m) => m > 16.67).length;
    final severe = sorted.where((m) => m > 33.34).length;
    final wall = List<double>.from(_frames)..sort();
    final drift = expectedMs == 0
        ? 1.0
        : clock.elapsedMilliseconds / expectedMs;
    // At 60 Hz a window that is actually being drawn produces roughly this
    // many frames in the time the run took.
    final expectedFrames = (clock.elapsedMilliseconds / 16.67).round();

    setState(() {
      _results.add({
        'run': label,
        'frames': sorted.length,
        'jankPct': sorted.isEmpty
            ? 0
            : double.parse((jank / sorted.length * 100).toStringAsFixed(1)),
        'severeJank': severe,
        'p50': double.parse(pct(0.50).toStringAsFixed(2)),
        'p95': double.parse(pct(0.95).toStringAsFixed(2)),
        'p99': double.parse(pct(0.99).toStringAsFixed(2)),
        'worst': double.parse(
          (sorted.isEmpty ? 0 : sorted.last).toStringAsFixed(2),
        ),
        // Wall-clock span of the slowest frame, including time spent waiting.
        'worstSpanMs': double.parse(
          (wall.isEmpty ? 0 : wall.last).toStringAsFixed(2),
        ),
        'wallMs': clock.elapsedMilliseconds,
        'expectedMs': expectedMs,
        'drift': double.parse(drift.toStringAsFixed(2)),
        'blocks': _console.markdown.settledBlockCount,
        'preloadedBlocks': preloaded,
        'rssBeforeMb': (rssBefore / 1048576).round(),
        'rssAfterMb': (ProcessInfo.currentRss / 1048576).round(),
        'rssPeakMb': (ProcessInfo.maxRss / 1048576).round(),
        // Position of the worst frame, and of every frame over budget, as a
        // fraction through the run.
        'overBudgetUi': uiBound,
        'overBudgetRaster': rasterBound,
        'worstBuildMs': double.parse(worstBuild.toStringAsFixed(2)),
        'worstRasterMs': double.parse(worstRaster.toStringAsFixed(2)),
        'worstAtPct': _frames.isEmpty
            ? 0
            : (worstAt / _frames.length * 100).round(),
        'overBudgetAtPct': overBudget
            .map((i) => (i / _frames.length * 100).round())
            .take(12)
            .toList(),
        // A run whose wall clock ran long while frames stayed cheap was
        // throttled by the OS, not by the renderer.
        //
        // The second clause is the one that matters more. macOS stops
        // producing frames for a window that is occluded or not frontmost,
        // and the resumption is reported as one enormous frame — 628 ms at
        // exactly 100 % through a run, or in one case a run that recorded no
        // frames at all. Reading that as a renderer stall is how a
        // measurement artefact gets published as a GC pause. A run that
        // produced far fewer frames than its duration allows was not being
        // drawn, and its maximum means nothing. 0.8 rather than 0.5: a run at
        // 55 % of the expected frames still carried a 73 ms outlier at frame
        // zero, which is the same artefact in smaller form.
        'framesExpected': expectedFrames,
        'valid':
            (expectedMs == 0 || drift <= 1.25 || pct(0.50) > 8.0) &&
            sorted.length >= expectedFrames * 0.8,
      });
    });
  }

  Future<void> _runAll() async {
    final tokens = defaultTokenStream().length;
    // Discarded. The first measured run used to absorb shader compilation and
    // first-frame setup — one 625 ms frame in an otherwise 1 ms run, which is
    // startup cost attributed to the renderer. Warm the same code path first
    // and throw the numbers away.
    setState(() => _status = 'warming up…');
    _console.markdown.reset();
    await _stream(defaultTokenStream().take(400).toList(), Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _runOne(
      '60 tok/s',
      const Duration(microseconds: 16667),
      (tokens * 16.667).round(),
    );
    await _runOne('200 tok/s', const Duration(milliseconds: 5), tokens * 5);
    await _runOne('unthrottled', Duration.zero, 0);
    // The question this answers: does an hour-long session make the next
    // token slower than the first one did?
    await _runOne(
      '60 tok/s after 200 messages',
      const Duration(microseconds: 16667),
      (tokens * 16.667).round(),
      preloadMessages: 200,
    );

    final payload = const JsonEncoder.withIndent('  ').convert({
      'corpus': {'tokens': tokens},
      'results': _results,
    });
    // ignore: avoid_print
    print('\n===BENCH_START===\n$payload\n===BENCH_END===');
    setState(() => _status = 'done');
    await Future<void>.delayed(const Duration(seconds: 2));
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Render benchmark · $_status')),
      body: Column(
        children: [
          if (_results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _results
                    .map(
                      (r) =>
                          '${r['run']}: p95 ${r['p95']}ms · '
                          'jank ${r['jankPct']}% · ${r['blocks']} blocks',
                    )
                    .join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          Expanded(
            child: ConsoleView(workspace: _BenchWorkspace(), console: _console),
          ),
        ],
      ),
    );
  }
}

/// Minimal stand-in so [ConsoleView] can be exercised without a server.
class _BenchWorkspace extends Workspace {
  _BenchWorkspace() : super(HermesGateway(_offline, connector: _never));

  static final _offline = HermesEndpoint.tunnelled(token: 'bench', port: 1);

  static Future<GatewayTransport> _never(Uri _) =>
      Completer<GatewayTransport>().future;
}
