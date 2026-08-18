import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'block_splitter.dart';
import 'render_block_splitter.dart';

/// Renders Markdown that is still arriving, without re-parsing what already
/// settled.
///
/// The naive approach — hand the whole accumulated buffer to a Markdown widget
/// on every update — is quadratic in response length. Measured on an Android
/// device at 60 tok/s: 15,100,091 characters parsed, versus 357,507 here for
/// identical output. See `docs/BENCHMARKS.md`.
///
/// Three mechanisms, in order of how much they contribute:
///
///  1. **Block segmentation** — only the trailing, still-growing block is
///     re-parsed; [IncrementalSplitter] keeps scan position across appends so
///     the segmentation itself stays linear too. (An earlier version re-scanned
///     the whole buffer per flush and cost exactly what it saved.)
///  2. **Widget identity** — each settled block's widget is built once and the
///     *same instance* returned thereafter, so Flutter skips the subtree and
///     the parser never runs on it again.
///  3. **Frame pacing** — at most one rebuild per frame.
///
/// Known limit: a still-growing oversized tail is throttled by
/// [maxTailChars] until its logical block settles.
class StreamingMarkdownView extends StatefulWidget {
  const StreamingMarkdownView({
    required this.controller,
    this.padding = const EdgeInsets.all(16),
    this.styleSheet,
    this.imageBuilder,
    this.maxTailChars = 8000,
    this.maxRenderBlockLines = 80,
    this.slowTailInterval = const Duration(milliseconds: 250),
    this.beforeTail,
    this.afterBlock,
    this.afterTail,
    this.blockDecorator,
    this.onTapLink,
    super.key,
  });

  final StreamingMarkdownController controller;
  final EdgeInsets padding;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownImageBuilder? imageBuilder;

  /// Above this tail size, re-parse the tail on [slowTailInterval] rather than
  /// every frame.
  ///
  /// Degrades update smoothness instead of frame rate for the one case
  /// segmentation cannot help — a very large single block. Tokens still arrive
  /// and still land; the tail just repaints less often while it is oversized.
  final int maxTailChars;

  /// Maximum content lines in one settled render segment.
  ///
  /// Oversized paragraphs, fenced code, tables, and top-level lists are split
  /// at safe Markdown boundaries. This is deliberately separate from logical
  /// This is deliberately separate from Markdown block splitting: controller
  /// indices and message anchors continue to address logical blocks, while the
  /// list lazily renders only the visible portions of a giant block.
  final int maxRenderBlockLines;

  final Duration slowTailInterval;

  /// Rendered between the settled blocks and the still-growing tail.
  ///
  /// That position is the whole point: the settled blocks end with the user's
  /// prompt, and the tail is the answer being written. Anything belonging to
  /// the turn *in between* — what the model thought, what it ran — goes here
  /// and reads in the order it happened. Pinning it above the transcript
  /// instead puts the model's reasoning permanently above the conversation,
  /// where it neither scrolls with the turn it belongs to nor leaves room for
  /// the answer.
  final Widget? beforeTail;

  /// Rendered directly after settled block [index], if it returns anything.
  ///
  /// This is how a turn's thinking lands under *its own* question: the prompt
  /// settles into a block, the turn remembers that index, and its record
  /// renders right there. Anchoring everything at the tail instead piled every
  /// turn's reasoning under the newest question and left history bare.
  final Widget? Function(int index)? afterBlock;

  /// Rendered after the still-growing tail — the caret, in practice.
  ///
  /// Kept out of the document deliberately. A caret appended to the Markdown
  /// text would settle into a block the moment the paragraph closed, and would
  /// be selected and copied along with the answer.
  final Widget? afterTail;

  /// Wraps a settled block, given its raw Markdown.
  ///
  /// The transcript is one document, so there is no message object to hang a
  /// bubble off. This lets the caller recognise its own markers — a user
  /// prompt, say — and give that block a different shape without the renderer
  /// knowing anything about chat.
  final Widget Function(int index, String data, Widget child)? blockDecorator;

  /// Invoked when a link in the transcript is tapped.
  ///
  /// Without it `MarkdownBody` renders links in link colours and does nothing
  /// on tap, which is worse than rendering them as plain text: it promises
  /// something it does not do.
  final MarkdownTapLinkCallback? onTapLink;

  @override
  State<StreamingMarkdownView> createState() => _StreamingMarkdownViewState();
}

class _StreamingMarkdownViewState extends State<StreamingMarkdownView> {
  final List<Widget> _settled = [];

  /// One key per render segment, used by search navigation.
  final List<GlobalKey> _settledKeys = [];

  /// Source ranges for each entry in [_settled].
  final List<int> _settledSourceStarts = [];
  final List<int> _settledSourceEnds = [];

  /// Index of the first render segment for each logical block.
  final List<int> _blockFirstSegments = [];

  /// Logical block index for each entry in [_settled].
  final List<int> _settledBlockIndices = [];

  /// Whether an entry is the final render segment of its logical block.
  ///
  /// Attached rows such as a turn timeline must appear once, after the whole
  /// logical block, rather than after every render segment.
  final List<bool> _settledEndsBlock = [];

  /// Renderer cache generation. A controller reset followed immediately by
  /// enough appends can otherwise look like an ordinary growing stream.
  int _cacheGeneration = -1;

  /// Whether new content should pull the view down with it.
  ///
  /// True until the user scrolls away from the bottom, and true again as soon
  /// as they come back. A transcript that always jumps to the end makes it
  /// impossible to read what scrolled past; one that never does leaves the
  /// answer being written off-screen, which is what happened here.
  bool _following = true;

  /// How close to the bottom still counts as "at the bottom". One line of
  /// slack, so a fingertip's worth of overscroll does not detach the follow.
  static const _followSlack = 40.0;

  int _searchJumpSerial = 0;
  bool _searchJumping = false;

  void _scrollToBlock(int index, int characterOffset) {
    final segmentIndex = _segmentIndexFor(index, characterOffset);
    if (segmentIndex == null) return;

    _searchJumpSerial++;
    final serial = _searchJumpSerial;
    _searchJumping = true;
    _following = false;

    final context = _settledKeys[segmentIndex].currentContext;
    if (context != null) {
      _revealSearchTarget(segmentIndex, serial);
      return;
    }

    if (!_coarseJumpToSegment(segmentIndex)) {
      _finishSearchJump(serial);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _continueSearchJump(segmentIndex, serial, 4),
    );
  }

  int? _segmentIndexFor(int blockIndex, int characterOffset) {
    if (blockIndex < 0 || blockIndex >= _blockFirstSegments.length) {
      return null;
    }

    final start = _blockFirstSegments[blockIndex];
    final end = blockIndex + 1 == _blockFirstSegments.length
        ? _settled.length
        : _blockFirstSegments[blockIndex + 1];
    final offset = characterOffset.clamp(0, _settledSourceEnds[end - 1]);
    for (var i = start; i < end; i++) {
      if (offset >= _settledSourceStarts[i] && offset < _settledSourceEnds[i]) {
        return i;
      }
    }
    return start;
  }

  bool _coarseJumpToSegment(int segmentIndex) {
    final controller = widget.controller.scrollController;
    if (!controller.hasClients) return false;
    final position = controller.position;
    if (!position.hasContentDimensions) return false;

    final itemCount = _settled.length + (widget.beforeTail == null ? 1 : 2);
    final targetListIndex = _listIndexForSegment(segmentIndex);
    final ratio = targetListIndex / (itemCount - 1);
    controller.jumpTo(
      (position.maxScrollExtent * ratio).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    _following = false;
    return true;
  }

  void _continueSearchJump(
    int segmentIndex,
    int serial,
    int attemptsRemaining,
  ) {
    if (!mounted || serial != _searchJumpSerial) return;

    final context = _settledKeys[segmentIndex].currentContext;
    if (context != null) {
      _revealSearchTarget(segmentIndex, serial);
      return;
    }
    if (attemptsRemaining <= 0) {
      _finishSearchJump(serial);
      return;
    }
    if (!_correctSearchJump(segmentIndex)) {
      _finishSearchJump(serial);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _continueSearchJump(segmentIndex, serial, attemptsRemaining - 1),
    );
  }

  bool _correctSearchJump(int segmentIndex) {
    final controller = widget.controller.scrollController;
    if (!controller.hasClients) return false;
    final position = controller.position;
    if (!position.hasContentDimensions) return false;

    final targetListIndex = _listIndexForSegment(segmentIndex);
    final anchors = <int, double>{};
    for (var i = 0; i < _settledKeys.length; i++) {
      final context = _settledKeys[i].currentContext;
      if (context == null) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final viewport = RenderAbstractViewport.of(box);
      anchors[_listIndexForSegment(i)] = viewport
          .getOffsetToReveal(box, 0)
          .offset;
    }
    if (anchors.isEmpty) return false;

    final target = _estimateListOffset(anchors, targetListIndex);

    if (target.isNaN || target.isInfinite) return false;
    controller.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    _following = false;
    return true;
  }

  int _listIndexForSegment(int segmentIndex) {
    final beforeTailCount = widget.beforeTail == null ? 0 : 1;
    return beforeTailCount + 1 + (_settled.length - 1 - segmentIndex);
  }

  double _estimateListOffset(Map<int, double> anchors, int target) {
    final indices = anchors.keys.toList()..sort();
    if (indices.length == 1) {
      final itemCount = _settled.length + (widget.beforeTail == null ? 1 : 2);
      final extent =
          widget.controller.scrollController.position.maxScrollExtent;
      final pixelsPerIndex = extent / (itemCount - 1);
      return anchors[indices.first]! +
          (target - indices.first) * pixelsPerIndex;
    }

    var lower = indices[0];
    var upper = indices[1];
    for (var i = 1; i < indices.length; i++) {
      lower = indices[i - 1];
      upper = indices[i];
      if (target <= upper) break;
    }

    final fraction = (target - lower) / (upper - lower);
    return anchors[lower]! + fraction * (anchors[upper]! - anchors[lower]!);
  }

  void _revealSearchTarget(int segmentIndex, int serial) {
    final context = _settledKeys[segmentIndex].currentContext;
    if (context == null) {
      _finishSearchJump(serial);
      return;
    }

    unawaited(
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 200),
        alignment: 0.1,
      ).whenComplete(() {
        _finishSearchJump(serial);
      }),
    );
  }

  void _finishSearchJump(int serial) {
    if (!mounted || serial != _searchJumpSerial) return;
    _searchJumping = false;
    _onScroll();
  }

  String _tail = '';

  /// Cached widget for the tail, keyed by the exact text it renders.
  ///
  /// The tail is the one block that is re-created on every rebuild — unlike
  /// settled blocks it has no stable widget identity — so without this cache
  /// a giant tail (a multi-hundred-KB base64 blob, say) is re-parsed on every
  /// rebuild. During a history load that is quadratic: each message that
  /// arrives re-parses the whole tail, and the tail keeps growing. One parse
  /// per *distinct* tail text is all the parser needs.
  Widget? _tailBlock;
  String _tailBlockData = '';
  bool _framePending = false;
  bool _dirty = false;
  Timer? _slowTailTimer;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(_listener);
    widget.controller._attachScroll(_scrollToBlock);
    widget.controller._attachFollow(_followTail);
    widget.controller.scrollController.addListener(_onScroll);
    _rebuildFromController();
  }

  /// The user's own scrolling decides whether new content pulls the view.
  void _onScroll() {
    if (_searchJumping) return;
    final controller = widget.controller.scrollController;
    if (!controller.hasClients) return;
    final position = controller.position;
    if (!position.hasContentDimensions) return;
    _following = position.pixels <= _followSlack;
  }

  /// Keeps the newest content in view after a rebuild.
  ///
  /// The list is reversed, so offset zero is the transcript's visual bottom.
  /// The post-frame callback still covers attached UI growing below the list's
  /// newest Markdown block.
  void _followTail() {
    if (!_following) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_following) return;
      final controller = widget.controller.scrollController;
      if (!controller.hasClients) return;
      final position = controller.position;
      if (!position.hasContentDimensions) return;
      if (position.pixels <= 0) return;
      controller.jumpTo(0);
    });
  }

  @override
  void didUpdateWidget(StreamingMarkdownView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._detach(_listener);
      old.controller._attachScroll(null);
      old.controller._attachFollow(null);
      old.controller.scrollController.removeListener(_onScroll);
      widget.controller.scrollController.addListener(_onScroll);
      _clearSettledCache();
      _cacheGeneration = -1;
      widget.controller._attach(_listener);
      widget.controller._attachScroll(_scrollToBlock);
      widget.controller._attachFollow(_followTail);
      _rebuildFromController();
    } else if (old.maxRenderBlockLines != widget.maxRenderBlockLines) {
      _clearSettledCache();
      _rebuildFromController();
    }
  }

  /// Captured once so [StreamingMarkdownController._detach] can compare it.
  /// A repeated `_onChanged` tear-off is `==`-equal but not guaranteed to be
  /// the identical object, and the comparison there must be reliable.
  late final VoidCallback _listener = _onChanged;

  void _onChanged() {
    _dirty = true;
    _schedule();
  }

  void _schedule() {
    if (_framePending) return;
    _framePending = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _framePending = false;
      _watchdog?.cancel();
      _flush();
    });
    // If frame production is suspended — the window is minimised, the app is
    // backgrounded — the frame callback never fires and _framePending would
    // latch forever, freezing the transcript even after the app returns. The
    // watchdog guarantees the buffer still drains.
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(milliseconds: 500), () {
      _framePending = false;
      _flush();
    });
  }

  void _flush() {
    if (!mounted || !_dirty) return;
    _dirty = false;
    _rebuildFromController();
  }

  void _rebuildFromController() {
    final splitter = widget.controller._splitter;
    final blocks = splitter.blocks;
    final generation = widget.controller._generation;

    if (generation != _cacheGeneration ||
        blocks.length < _blockFirstSegments.length) {
      _clearSettledCache();
      _cacheGeneration = generation;
    }

    // Parsed once each, here, and never again.
    for (var i = _blockFirstSegments.length; i < blocks.length; i++) {
      _appendSettledBlock(i, blocks[i]);
    }

    final tail = splitter.tail;
    if (tail.length > widget.maxTailChars) {
      // Oversized single block: throttle instead of dropping frames.
      _slowTailTimer ??= Timer(widget.slowTailInterval, () {
        _slowTailTimer = null;
        if (mounted) setState(() => _tail = widget.controller._splitter.tail);
      });
      if (mounted) {
        setState(() {});
        _followTail();
      }
      return;
    }

    if (mounted) {
      setState(() => _tail = tail);
      _followTail();
    }
  }

  void _clearSettledCache() {
    _settled.clear();
    _settledKeys.clear();
    _settledSourceStarts.clear();
    _settledSourceEnds.clear();
    _blockFirstSegments.clear();
    _settledBlockIndices.clear();
    _settledEndsBlock.clear();
    _tail = '';
    _tailBlock = null;
    _tailBlockData = '';
  }

  void _appendSettledBlock(int index, String data) {
    _blockFirstSegments.add(_settled.length);

    if (widget.blockDecorator != null) {
      final key = GlobalKey();
      final probe = _SettledBlock(
        key: key,
        data: data,
        styleSheet: widget.styleSheet,
        imageBuilder: widget.imageBuilder,
        onTapLink: widget.onTapLink,
      );
      final decorated = widget.blockDecorator?.call(index, data, probe);
      if (decorated != null) {
        _settled.add(decorated);
        _settledKeys.add(key);
        _settledSourceStarts.add(0);
        _settledSourceEnds.add(data.length);
        _settledBlockIndices.add(index);
        _settledEndsBlock.add(true);
        return;
      }
    }

    // A decorator may replace the child entirely (the user bubble does), so a
    // decorated logical block remains one item to preserve its contract.
    final segments = RenderBlockSplitter(
      maxLines: widget.maxRenderBlockLines,
    ).splitSegments(data);
    for (var i = 0; i < segments.length; i++) {
      final segmentKey = GlobalKey();
      _settled.add(
        _SettledBlock(
          key: segmentKey,
          data: segments[i].markdown,
          styleSheet: widget.styleSheet,
          imageBuilder: widget.imageBuilder,
          onTapLink: widget.onTapLink,
        ),
      );
      _settledKeys.add(segmentKey);
      _settledSourceStarts.add(segments[i].sourceStart);
      _settledSourceEnds.add(segments[i].sourceEnd);
      _settledBlockIndices.add(index);
      _settledEndsBlock.add(i == segments.length - 1);
    }
  }

  /// The tail's rendered block, parsed once per distinct text.
  ///
  /// Caching the *instance* (not just the text) is what keeps the parser
  /// quiet: `_SettledBlock` is a plain widget, so an unchanged instance makes
  /// `MarkdownBody`'s `didUpdateWidget` see identical `data` and skip the
  /// re-parse. The ListView item for the tail is rebuilt on every flush, and
  /// without this a growing tail re-parses on every flush — quadratic over a
  /// history load.
  Widget _tailBlockFor(String data) {
    if (data == _tailBlockData && _tailBlock != null) return _tailBlock!;
    _tailBlockData = data;
    _tailBlock = _SettledBlock(
      data: data,
      styleSheet: widget.styleSheet,
      imageBuilder: widget.imageBuilder,
      onTapLink: widget.onTapLink,
    );
    return _tailBlock!;
  }

  @override
  void dispose() {
    _slowTailTimer?.cancel();
    _watchdog?.cancel();
    widget.controller.scrollController.removeListener(_onScroll);
    widget.controller._detach(_listener);
    widget.controller._attachScroll(null);
    widget.controller._attachFollow(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The list is reversed so offset zero is already the newest message. A
    // forward list must measure its full extent before jumping to the bottom,
    // which defeats builder laziness for every restored long transcript.
    return ListView.builder(
      controller: widget.controller.scrollController,
      reverse: true,
      padding: widget.padding,
      // Dragging the transcript puts the keyboard away. On a phone this is
      // the gesture people already use, and without it the keyboard covers
      // half the answer with no way to dismiss it.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _settled.length + (widget.beforeTail == null ? 1 : 2),
      itemBuilder: (context, index) {
        if (index > 0) {
          final beforeTailCount = widget.beforeTail == null ? 0 : 1;
          if (index == 1 && beforeTailCount == 1) {
            return widget.beforeTail!;
          }
          final settledIndex =
              _settled.length - 1 - (index - 1 - beforeTailCount);
          if (settledIndex >= 0) return _settledItemAt(settledIndex);
        }
        if (_tail.trim().isEmpty) {
          final after = widget.afterTail;
          if (after == null) return const SizedBox.shrink();
          // Aligned, not returned bare. A list item is given a *tight* width,
          // and a `Container` with a width of its own resolves that against
          // the incoming constraint rather than overriding it — so an 8-point
          // caret handed straight to the list came out as a brass bar the
          // full width of the transcript. This is the common path: a turn
          // that has run a tool and not yet written a word.
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: after,
          );
        }
        final block = _tailBlockFor(_tail);
        final after = widget.afterTail;
        if (after == null) return block;
        // Column, not a Row: the tail is a rendered Markdown block of unknown
        // height, and the caret belongs after the last *line*, which is where
        // a Column with a trailing child that hugs the left edge puts it in
        // the only case that matters — text still arriving.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [block, after],
        );
      },
    );
  }

  Widget _settledItemAt(int index) {
    final attached = _settledEndsBlock[index]
        ? widget.afterBlock?.call(_settledBlockIndices[index])
        : null;
    if (attached == null) return _settled[index];

    // Column, not a separate list entry: the block and what it anchors belong
    // together, so they scroll and measure as one item.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_settled[index], attached],
    );
  }
}

/// A line longer than this is terminated with an invisible break before the
/// Markdown parser sees it. The inline plain-text syntax
/// `[ \tA-Za-z0-9]*[A-Za-z0-9](?=\s)` backtracks quadratically over an
/// unbroken run with no following whitespace, so a single mega-line (a base64
/// blob, a giant URL) can stall the main thread for seconds on load.
/// U+FEFF (zero-width no-break space) is whitespace to that lookahead — the
/// run then parses in linear time — and it is invisible in the rendered text.
const _maxLineChars = 1500;

/// Terminates oversized lines with an invisible whitespace character, without
/// touching fenced code (blank lines inside a fence would change the code) or
/// data URIs / markdown image lines (where insertion would corrupt the image payload).
String _boundedMarkdown(String data) {
  final lines = data.split('\n');
  if (!lines.any((l) => l.length > _maxLineChars)) return data;
  final first = data.trimLeft();
  if (first.startsWith('```') || first.startsWith('~~~')) return data;
  final out = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.length <= _maxLineChars ||
        line.contains('data:image/') ||
        line.contains('![')) {
      out.write(line);
    } else {
      var j = 0;
      while (j < line.length) {
        final end = (j + _maxLineChars).clamp(0, line.length);
        out.write(line.substring(j, end));
        j = end;
        if (j < line.length) out.write('\uFEFF');
      }
    }
    if (i < lines.length - 1) out.write('\n');
  }
  return out.toString();
}

Widget _defaultMarkdownImageBuilder(Uri uri, String? title, String? alt) {
  final uriStr = uri.toString();
  if (uriStr.startsWith('data:image/')) {
    final commaIdx = uriStr.indexOf(',');
    if (commaIdx != -1) {
      try {
        final b64 = uriStr
            .substring(commaIdx + 1)
            .replaceAll(RegExp(r'\s+'), '');
        final bytes = base64Decode(b64);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380, maxWidth: 440),
              child: Image.memory(bytes, cacheWidth: 800, fit: BoxFit.contain),
            ),
          ),
        );
      } catch (_) {}
    }
  } else if (uri.scheme == 'http' || uri.scheme == 'https') {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380, maxWidth: 440),
          child: Image.network(
            uriStr,
            cacheWidth: 800,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image_outlined, size: 36),
          ),
        ),
      ),
    );
  }
  return const SizedBox.shrink();
}

class _SettledBlock extends StatelessWidget {
  const _SettledBlock({
    required this.data,
    this.styleSheet,
    this.imageBuilder,
    this.onTapLink,
    super.key,
  });
  final String data;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownImageBuilder? imageBuilder;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MarkdownBody(
        data: _boundedMarkdown(data),
        styleSheet: styleSheet,
        imageBuilder: imageBuilder ?? _defaultMarkdownImageBuilder,
        // The transcript is something people quote from — a command, an
        // id, a path. Without this the only way to get text out was Copy
        // transcript, which takes the whole conversation.
        selectable: true,
        onTapLink: onTapLink,
      ),
    ),
  );
}

/// Feeds text into a [StreamingMarkdownView].
///
/// Owns the splitter so the view can be rebuilt or replaced without losing
/// what already settled.
class StreamingMarkdownController extends ChangeNotifier {
  StreamingMarkdownController({String initialText = ''}) {
    if (initialText.isNotEmpty) _splitter.append(initialText);
  }

  final IncrementalSplitter _splitter = IncrementalSplitter();
  final ScrollController scrollController = ScrollController();
  VoidCallback? _listener;
  int _generation = 0;

  /// Everything received so far, normalized to one blank line between blocks.
  ///
  /// The splitter already owns every settled block and the active tail, so
  /// retaining another complete transcript would double the text memory for
  /// long sessions. This getter is used by clipboard and correction paths, for
  /// which Markdown-equivalent block spacing is sufficient.
  String get text => _splitter.text;

  /// `text.length`, without building `text`.
  ///
  /// Callers that only need the offset — recording where a turn's answer
  /// starts, comparing against a server snapshot — should prefer this: the
  /// streaming path reads it once per turn, and materialising the transcript
  /// there allocated a copy of the whole conversation mid-stream.
  int get textLength => _splitter.textLength;

  int get settledBlockCount => _splitter.blockCount;

  /// The settled blocks, in order. Exposed so a caller can search the
  /// conversation without re-splitting the raw text itself.
  ///
  /// An unmodifiable view rather than a copy; see [IncrementalSplitter.blocks].
  List<String> get blocks => _splitter.blocks;

  /// Brings the source character at [characterOffset] in settled block
  /// [index] into view.
  ///
  /// The target render segment may be outside a lazy viewport. The view first
  /// jumps near its list position, then asks Flutter for a precise reveal
  /// once that segment has been built.
  void scrollToBlock(int index, {int characterOffset = 0}) =>
      _scrollToBlock?.call(index, characterOffset);

  void Function(int, int)? _scrollToBlock;

  /// Clears everything so a fresh stream starts from an empty document.
  /// Used by the render benchmark between runs.
  void reset() {
    _splitter.reset();
    _generation++;
    _listener?.call();
    notifyListeners();
  }

  /// Append newly arrived text. O(len(chunk)).
  void append(String chunk) {
    if (chunk.isEmpty) return;
    _splitter.append(chunk);
    _listener?.call();
    notifyListeners();
  }

  void _attach(VoidCallback listener) => _listener = listener;
  void _attachScroll(void Function(int, int)? scroll) =>
      _scrollToBlock = scroll;

  void Function()? _followRequest;
  void _attachFollow(void Function()? follow) => _followRequest = follow;

  /// Ask the view to stay at the bottom, if it was there.
  ///
  /// The view follows its own tail whenever the document changes, but content
  /// can also be attached to a block — a turn's reasoning, growing while the
  /// model thinks — and that grows without this controller changing at all.
  /// Nothing then told the list to scroll, so a long think wrote itself off
  /// the bottom of the screen: measured at 0 px of scroll against 2,110 px of
  /// content. Whoever owns that attached widget calls this when it grows.
  void requestFollow() => _followRequest?.call();

  /// Unhooks [listener] — but only if it is still the attached one.
  ///
  /// Flutter mounts a replacement element *before* unmounting the one it
  /// replaced, so when a view is rebuilt into a new slot the old state's
  /// `dispose` runs after the new state's `initState`. An unconditional
  /// detach there cleared the listener the new view had just installed and
  /// the transcript froze mid-stream: tokens kept arriving, nothing rendered.
  void _detach(VoidCallback listener) {
    if (_listener == listener) _listener = null;
  }

  void scrollToBottom() {
    if (!scrollController.hasClients) return;
    scrollController.jumpTo(0);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}
