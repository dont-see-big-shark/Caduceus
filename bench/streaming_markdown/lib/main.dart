/// Caduceus — P0 Spike A
///
/// Compares two Markdown streaming-render strategies on an identical token
/// stream and reports frame timings and parser workload.
///
/// Run in profile mode. Debug-mode numbers are meaningless — the Dart VM is
/// running unoptimised and assertions are on:
///
///   `flutter run --profile -d <device>`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'corpus.dart';
import 'metrics.dart';
import 'renderers.dart';

/// Run every combination on launch, print the results JSON, and exit.
///
///   `flutter run --profile -d DEVICE --dart-define=AUTORUN=true`
///
/// Without this the harness waits for a button press, which is fine for poking
/// at it by hand but useless for a reproducible measurement.
const bool kAutorun = bool.fromEnvironment('AUTORUN');

void main() => runApp(const BenchApp());

enum Strategy {
  naive('naive', 'Naive (per-token setState, full reparse)'),
  incremental('incremental', 'Incremental (frame coalescing + block caching)');

  const Strategy(this.id, this.label);
  final String id;
  final String label;
}

enum StreamRate {
  realistic('60 tok/s', Duration(microseconds: 16667)),
  fast('200 tok/s', Duration(milliseconds: 5)),
  unthrottled('unthrottled', Duration.zero);

  const StreamRate(this.label, this.delay);
  final String label;
  final Duration delay;
}

/// Emits [tokens] at the given rate. `Duration.zero` still yields to the event
/// loop between tokens, so the frame pipeline is never fully starved — the
/// point is to saturate it, not to deadlock it.
Stream<String> emit(List<String> tokens, Duration delay) async* {
  for (final token in tokens) {
    if (delay == Duration.zero) {
      await Future<void>.delayed(Duration.zero);
    } else {
      await Future<void>.delayed(delay);
    }
    yield token;
  }
}

class BenchApp extends StatelessWidget {
  const BenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Caduceus Spike A',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFB8860B),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const BenchHome(),
    );
  }
}

class BenchHome extends StatefulWidget {
  const BenchHome({super.key});

  @override
  State<BenchHome> createState() => _BenchHomeState();
}

class _BenchHomeState extends State<BenchHome> {
  late final List<String> _tokens = defaultTokenStream();

  Strategy _strategy = Strategy.naive;

  final List<RunResult> _results = [];
  final FrameRecorder _recorder = FrameRecorder();
  ParseCost _cost = ParseCost();

  Key _rendererKey = UniqueKey();
  Stream<String>? _active;
  Completer<void>? _completion;
  bool _running = false;
  String _status = 'idle';

  int get _corpusChars =>
      _tokens.fold<int>(0, (sum, token) => sum + token.length);

  @override
  void initState() {
    super.initState();
    if (kAutorun) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Let the first frames settle before measuring anything.
        await Future<void>.delayed(const Duration(seconds: 1));
        await _runAll();
        await _emitResults();
        exit(0);
      });
    }
  }

  /// Emits the results one line at a time, paced.
  ///
  /// On Android the output reaches the host through logcat forwarding, which
  /// silently drops data when a single write is large or arrives too fast — a
  /// 4 KB blob truncates mid-object. Line-at-a-time with a small gap survives.
  Future<void> _emitResults() async {
    // ignore: avoid_print
    print('===BENCH_JSON_START===');
    for (final line in _resultsJson().split('\n')) {
      // ignore: avoid_print
      print(line);
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    // ignore: avoid_print
    print('===BENCH_JSON_END===');
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  String _resultsJson() => const JsonEncoder.withIndent('  ').convert({
        'corpus': {
          'tokens': _tokens.length,
          'chars': _corpusChars,
          'seed': 42,
        },
        'results': _results.map((r) => r.toJson()).toList(),
      });

  Future<void> _runOne(Strategy strategy, StreamRate rate) async {
    setState(() {
      _running = true;
      _status = 'running ${strategy.id} @ ${rate.label}…';
      _strategy = strategy;
      _cost = ParseCost();
      _completion = Completer<void>();
      _active = emit(_tokens, rate.delay);
      _rendererKey = UniqueKey();
    });

    // Let the fresh renderer mount before the recorder starts, so mount cost is
    // not attributed to the stream.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _recorder.start();

    await _completion!.future;
    // Drain the trailing frames the last tokens caused.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final frames = _recorder.stop();
    if (!mounted) return;

    final result = RunResult(
      strategy: strategy.id,
      rateLabel: rate.label,
      frames: frames,
      parse: _cost,
      expectedMs: rate.delay == Duration.zero
          ? 0
          : (_tokens.length * rate.delay.inMicroseconds) ~/ 1000,
    );

    if (!result.valid) {
      // ignore: avoid_print
      print('INVALID RUN — ${strategy.id} @ ${rate.label}: '
          '${result.invalidReason}');
    }

    setState(() {
      _results.add(result);
      _running = false;
      _status = result.valid
          ? 'done: ${strategy.id} @ ${rate.label}'
          : 'INVALID: ${result.invalidReason}';
    });
  }

  Future<void> _runAll() async {
    setState(_results.clear);
    for (final rate in StreamRate.values) {
      for (final strategy in Strategy.values) {
        await _runOne(strategy, rate);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    if (mounted) setState(() => _status = 'all runs complete');
  }

  void _copyJson() {
    Clipboard.setData(ClipboardData(text: _resultsJson()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Results JSON copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caduceus · Spike A'),
        actions: [
          IconButton(
            onPressed: _results.isEmpty ? null : _copyJson,
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy results JSON',
          ),
        ],
      ),
      body: Column(
        children: [
          _controls(),
          const Divider(height: 1),
          Expanded(
            flex: 3,
            child: _active == null
                ? const Center(child: Text('Pick a strategy and run.'))
                : _renderer(),
          ),
          const Divider(height: 1),
          Expanded(flex: 2, child: _resultsTable()),
        ],
      ),
    );
  }

  Widget _renderer() {
    void done() {
      if (!(_completion?.isCompleted ?? true)) _completion!.complete();
    }

    return switch (_strategy) {
      Strategy.naive => NaiveRenderer(
          key: _rendererKey,
          tokens: _active!,
          cost: _cost,
          onDone: done,
        ),
      Strategy.incremental => IncrementalRenderer(
          key: _rendererKey,
          tokens: _active!,
          cost: _cost,
          onDone: done,
        ),
    };
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'corpus: ${_tokens.length} tokens / $_corpusChars chars · $_status',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rate in StreamRate.values)
                for (final strategy in Strategy.values)
                  OutlinedButton(
                    onPressed:
                        _running ? null : () => _runOne(strategy, rate),
                    child: Text('${strategy.id} @ ${rate.label}'),
                  ),
              FilledButton.icon(
                onPressed: _running ? null : _runAll,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run all 6'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultsTable() {
    if (_results.isEmpty) {
      return const Center(child: Text('No results yet.'));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 18,
          columns: const [
            DataColumn(label: Text('ok')),
            DataColumn(label: Text('strategy')),
            DataColumn(label: Text('rate')),
            DataColumn(label: Text('rebuilds'), numeric: true),
            DataColumn(label: Text('chars parsed'), numeric: true),
            DataColumn(label: Text('frames'), numeric: true),
            DataColumn(label: Text('jank %'), numeric: true),
            DataColumn(label: Text('p95 ms'), numeric: true),
            DataColumn(label: Text('worst ms'), numeric: true),
          ],
          rows: [
            for (final r in _results)
              DataRow(cells: [
                DataCell(Icon(
                  r.valid ? Icons.check_circle : Icons.error,
                  color: r.valid ? Colors.green : Colors.red,
                  size: 18,
                )),
                DataCell(Text(r.strategy)),
                DataCell(Text(r.rateLabel)),
                DataCell(Text('${r.parse.rebuilds}')),
                DataCell(Text('${r.parse.charsParsed}')),
                DataCell(Text('${r.frames.frameCount}')),
                DataCell(Text(
                    (r.frames.jankRatio * 100).toStringAsFixed(1))),
                DataCell(Text(r.frames.p95Ms.toStringAsFixed(1))),
                DataCell(Text(r.frames.worstFrameMs.toStringAsFixed(1))),
              ]),
          ],
        ),
      ),
    );
  }
}
