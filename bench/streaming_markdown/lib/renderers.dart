/// The two render strategies under comparison.
///
/// Both use the same Markdown package (`flutter_markdown_plus`) so the only
/// variable is the strategy. Swapping the package would confound the result.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'block_splitter.dart';
import 'metrics.dart';

/// Drives exactly one rebuild per frame, coalescing every token that arrived
/// since the last one.
///
/// **Both** strategies use this. An earlier version let the naive renderer call
/// `setState` per token and let the framework coalesce as it saw fit, which
/// produced 221 frames against the incremental renderer's 2,777 on the same
/// stream. The two were not doing equal visual work, so comparing their wall
/// clocks measured nothing. Holding frame cadence constant makes frame count a
/// control rather than a confound, leaving per-frame cost as the only variable.
///
/// This is generous to the naive strategy — it is a fairer opponent than the
/// one real clients ship — which is the right direction for a comparison whose
/// conclusion is "the incremental one is better".
mixin _FramePaced<T extends StatefulWidget> on State<T> {
  bool _framePending = false;
  bool _dirty = false;

  void markDirty() {
    _dirty = true;
    if (_framePending) return;
    _framePending = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _framePending = false;
      flushIfDirty();
    });
  }

  void flushIfDirty() {
    if (!mounted || !_dirty) return;
    _dirty = false;
    onFlush();
  }

  /// Apply whatever accumulated since the last frame.
  void onFlush();
}

/// Wraps [MarkdownBody] and records how much text was handed to the parser.
class _CountingMarkdown extends StatelessWidget {
  const _CountingMarkdown({required this.data, required this.cost});

  final String data;
  final ParseCost cost;

  @override
  Widget build(BuildContext context) {
    cost.record(data.length);
    return MarkdownBody(data: data, selectable: false);
  }
}

// ---------------------------------------------------------------------------
// Strategy A — naive
// ---------------------------------------------------------------------------

/// Mirrors what `rusty4444/hermes-android` does today (`chat_screen.dart:377`):
/// one `setState` per token, and the whole accumulated buffer re-parsed on
/// every rebuild.
///
/// Total parse work is `sum(1..n)` characters for an n-character response —
/// quadratic. This is not a strawman; it is the straightforward implementation
/// and it is what most clients ship.
class NaiveRenderer extends StatefulWidget {
  const NaiveRenderer({
    required this.tokens,
    required this.cost,
    required this.onDone,
    super.key,
  });

  final Stream<String> tokens;
  final ParseCost cost;
  final VoidCallback onDone;

  @override
  State<NaiveRenderer> createState() => _NaiveRendererState();
}

class _NaiveRendererState extends State<NaiveRenderer> with _FramePaced {
  final StringBuffer _buffer = StringBuffer();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<String>? _sub;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _sub = widget.tokens.listen(
      (token) {
        _buffer.write(token);
        markDirty();
      },
      onDone: () {
        flushIfDirty();
        widget.onDone();
      },
    );
  }

  /// The defining property of this strategy: the entire accumulated buffer goes
  /// back to the Markdown parser, every time.
  @override
  void onFlush() {
    setState(() => _text = _buffer.toString());
    _autoScroll();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      child: _CountingMarkdown(data: _text, cost: widget.cost),
    );
  }
}

// ---------------------------------------------------------------------------
// Strategy B — incremental
// ---------------------------------------------------------------------------

/// Three changes, each addressing a distinct cost:
///
///  1. **Frame-budget coalescing.** Tokens accumulate in a buffer and trigger at
///     most one rebuild per frame. At 60 tok/s this changes little; under a
///     fast local model it is the difference between 60 and 900 rebuilds.
///
///  2. **Block segmentation.** Only the trailing, still-growing block is
///     re-parsed. Everything above it is finished and is not touched again.
///
///  3. **Widget identity for settled blocks.** Each completed block's widget is
///     built exactly once and stored. Returning the *identical* instance on
///     subsequent builds makes Flutter skip the subtree entirely — the element
///     is not rebuilt, so the Markdown parser never runs on it again.
///     `RepaintBoundary` additionally keeps it out of the repaint region.
///
/// Total parse work becomes linear in response length.
class IncrementalRenderer extends StatefulWidget {
  const IncrementalRenderer({
    required this.tokens,
    required this.cost,
    required this.onDone,
    super.key,
  });

  final Stream<String> tokens;
  final ParseCost cost;
  final VoidCallback onDone;

  @override
  State<IncrementalRenderer> createState() => _IncrementalRendererState();
}

class _IncrementalRendererState extends State<IncrementalRenderer>
    with _FramePaced {
  /// Keeps scan position and fence state across tokens, so appending is
  /// O(len(token)) rather than O(len(response)). Re-scanning the whole buffer
  /// per token made the splitter cost as much as the parsing it was avoiding.
  final IncrementalSplitter _splitter = IncrementalSplitter();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<String>? _sub;

  /// Built once each, then reused by identity.
  final List<Widget> _settled = [];

  String _tail = '';

  @override
  void initState() {
    super.initState();
    _sub = widget.tokens.listen(
      (token) {
        _splitter.append(token);
        markDirty();
      },
      onDone: () {
        // Make sure the last partial frame is not dropped.
        flushIfDirty();
        widget.onDone();
      },
    );
  }

  @override
  void onFlush() {
    // Promote any newly-settled blocks into permanent widgets. Each is parsed
    // once, here, and never again.
    final blocks = _splitter.blocks;
    for (var i = _settled.length; i < blocks.length; i++) {
      _settled.add(
        RepaintBoundary(
          key: ValueKey('block-$i'),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CountingMarkdown(data: blocks[i], cost: widget.cost),
          ),
        ),
      );
    }

    setState(() => _tail = _splitter.tail);
    _autoScroll();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ListView.builder keeps offscreen settled blocks out of the build phase
    // altogether; returning cached instances keeps the onscreen ones out of the
    // parse phase.
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: _settled.length + 1,
      itemBuilder: (context, index) {
        if (index < _settled.length) return _settled[index];
        if (_tail.trim().isEmpty) return const SizedBox.shrink();
        return _CountingMarkdown(data: _tail, cost: widget.cost);
      },
    );
  }
}
