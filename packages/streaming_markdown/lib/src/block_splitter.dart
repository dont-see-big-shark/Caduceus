/// Splits a partially-received Markdown buffer into blocks that are known to be
/// complete, plus the one trailing block that may still be growing.
///
/// This is what makes incremental rendering possible. A completed block can be
/// parsed once and never looked at again; only the tail has to be re-parsed as
/// tokens arrive. Getting the boundary wrong is not a performance bug, it is a
/// correctness bug — freeze a block too early and the rest of its content
/// renders as a separate, wrongly-formatted block.
library;

import 'dart:collection';

class BlockSplit {
  const BlockSplit(this.stable, this.tail);

  /// Blocks that cannot change no matter what arrives next.
  final List<String> stable;

  /// The trailing region, which may still be extended by future tokens.
  final String tail;

  @override
  String toString() =>
      'BlockSplit(stable: ${stable.length}, tail: ${tail.length} chars)';
}

/// Streaming splitter that processes only newly-arrived text.
///
/// [splitMarkdown] below re-scans the whole buffer on every call, which makes
/// the splitter itself quadratic — on the benchmark corpus it scans 21,329,133
/// characters, the same volume the naive renderer hands to the Markdown parser.
/// Segmenting blocks is pointless if the segmentation costs what it saves.
///
/// This class keeps the scan position, fence state, and settled blocks across
/// calls, so [append] is O(len(chunk)) amortised. `splitMarkdown` is retained
/// as the reference implementation the differential test checks this against.
class IncrementalSplitter {
  final List<String> _blocks = [];
  final List<String> _currentLines = [];
  String _partial = '';
  bool _inFence = false;
  String? _fenceMarker;

  /// Running length of `_blocks.join('\n\n')`, maintained as blocks settle.
  ///
  /// See [textLength] for why the length is tracked but the text is not.
  int _settledLength = 0;

  /// Blocks that cannot change no matter what arrives next.
  ///
  /// An unmodifiable *view*, not a copy: this getter sits on the per-frame
  /// render path, where `List.unmodifiable` allocated a fresh list of every
  /// settled block on every frame — cost that grew with the length of the
  /// conversation, for a list the caller only ever reads.
  late final List<String> blocks = UnmodifiableListView(_blocks);

  /// Number of settled blocks, for callers that only need to know what is new.
  int get blockCount => _blocks.length;

  /// The trailing region, which may still be extended.
  String get tail {
    if (_currentLines.isEmpty) return _partial;
    return '${_currentLines.join('\n')}\n$_partial';
  }

  /// Everything received so far, normalized to one blank line between blocks.
  String get text {
    if (_blocks.isEmpty) return tail;
    return '${_blocks.join('\n\n')}\n\n$tail';
  }

  /// `text.length`, without building `text`.
  ///
  /// The streaming path needs this on the first answer token of every turn, to
  /// record where the answer begins. Materialising the whole transcript to
  /// read one integer allocated megabytes mid-stream on a long session, which
  /// is the allocation this exists to avoid.
  int get textLength {
    final tailLength = tail.length;
    if (_blocks.isEmpty) return tailLength;
    return _settledLength + 2 + tailLength;
  }

  /// Discards all state, as if nothing had ever been appended.
  void reset() {
    _blocks.clear();
    _currentLines.clear();
    _settledLength = 0;
    _partial = '';
    _inFence = false;
    _fenceMarker = null;
  }

  void append(String chunk) {
    _partial += chunk;
    var start = 0;
    var idx = _partial.indexOf('\n', start);
    while (idx >= 0) {
      _consumeLine(_partial.substring(start, idx));
      start = idx + 1;
      idx = _partial.indexOf('\n', start);
    }
    if (start > 0) {
      _partial = _partial.substring(start);
    }
  }

  /// Only ever called with a line whose terminating newline has arrived, so a
  /// blank line here is a real blank line and not a `split('\n')` artefact.
  void _consumeLine(String line) {
    final trimmed = line.trimLeft();

    if (_inFence) {
      _currentLines.add(line);
      if (_isFenceEnding(trimmed, _fenceMarker)) {
        _inFence = false;
        _fenceMarker = null;
        _flushBlock();
      }
      return;
    }

    final fence = _openingFence(trimmed);
    if (fence != null) {
      _flushBlock();
      _inFence = true;
      _fenceMarker = fence;
      _currentLines.add(line);
      return;
    }

    if (line.trim().isEmpty) {
      _flushBlock();
    } else {
      _currentLines.add(line);
    }
  }

  void _flushBlock() {
    if (_currentLines.isEmpty) return;
    final block = _currentLines.join('\n').trim();
    if (block.isNotEmpty) {
      // Mirrors the '\n\n' join in [text]: every block but the first is
      // preceded by a separator.
      _settledLength += block.length + (_blocks.isEmpty ? 0 : 2);
      _blocks.add(block);
    }
    _currentLines.clear();
  }
}

/// A line is a safe split point when it is blank *and* we are not inside a
/// fenced code block. Everything before the last such line is stable.
///
/// Deliberately conservative. Setext headings (`Title\n=====`), lazy list
/// continuation, and link reference definitions can all extend a block across
/// what looks like a boundary, so we only split on a blank line — the one
/// separator that CommonMark guarantees terminates a leaf block.
BlockSplit splitMarkdown(String buffer) {
  if (buffer.isEmpty) return const BlockSplit([], '');

  final lines = buffer.split('\n');
  var inFence = false;
  String? fenceMarker;

  // Index of the line after the last confirmed boundary.
  var stableEnd = 0;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();

    if (inFence) {
      if (_isFenceEnding(trimmed, fenceMarker)) {
        inFence = false;
        fenceMarker = null;
        if (i < lines.length - 1) stableEnd = i + 1;
      }
      continue;
    }

    final fence = _openingFence(trimmed);
    if (fence != null) {
      inFence = true;
      fenceMarker = fence;
      continue;
    }

    // Blank line at top level: everything up to and including it is settled.
    //
    // The last element is excluded deliberately. `split('\n')` yields a
    // trailing '' whenever the buffer ends with a newline, and that '' is an
    // artifact of the split, not a blank line we have actually observed — the
    // next token may extend it into ordinary text. Treating it as a boundary
    // settles the preceding paragraph one token too early, and the paragraph
    // then un-settles when the stream continues.
    //
    // Requiring i < lines.length - 1 is also what makes `stableEnd` monotonic:
    // every line before the last is frozen, as is the fence state derived from
    // them, so a boundary once observed can never be retracted.
    if (i < lines.length - 1 && line.trim().isEmpty) {
      stableEnd = i + 1;
    }
  }

  if (stableEnd == 0) return BlockSplit(const [], buffer);

  final stableText = lines.sublist(0, stableEnd).join('\n');
  final tail = lines.sublist(stableEnd).join('\n');

  return BlockSplit(_toBlocks(stableText), tail);
}

/// Splits settled text on blank-line boundaries, preserving fenced regions.
List<String> _toBlocks(String text) {
  final lines = text.split('\n');
  final blocks = <String>[];
  final current = <String>[];
  var inFence = false;
  String? fenceMarker;

  void flush() {
    if (current.isEmpty) return;
    final block = current.join('\n').trim();
    if (block.isNotEmpty) blocks.add(block);
    current.clear();
  }

  for (final line in lines) {
    final trimmed = line.trimLeft();

    if (inFence) {
      current.add(line);
      if (_isFenceEnding(trimmed, fenceMarker)) {
        inFence = false;
        fenceMarker = null;
        flush();
      }
      continue;
    }

    final fence = _openingFence(trimmed);
    if (fence != null) {
      flush();
      inFence = true;
      fenceMarker = fence;
      current.add(line);
      continue;
    }

    if (line.trim().isEmpty) {
      flush();
    } else {
      current.add(line);
    }
  }
  flush();

  return blocks;
}

/// Returns the fence marker (``` or ~~~, possibly longer) if [trimmed] opens a
/// fenced code block, otherwise null.
String? _openingFence(String trimmed) {
  for (final char in const ['`', '~']) {
    if (!trimmed.startsWith(char * 3)) continue;
    var len = 0;
    while (len < trimmed.length && trimmed[len] == char) {
      len++;
    }
    // An info string may not contain a backtick when the fence is backticks.
    final info = trimmed.substring(len);
    if (char == '`' && info.contains('`')) return null;
    return char * len;
  }
  return null;
}

/// Returns true if [trimmed] closes an open fence identified by [marker].
bool _isFenceEnding(String trimmed, String? marker) =>
    marker != null &&
    trimmed.startsWith(marker) &&
    trimmed.substring(marker.length).trim().isEmpty;
