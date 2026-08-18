/// Splits a partially-received Markdown buffer into blocks that are known to be
/// complete, plus the one trailing block that may still be growing.
///
/// This is what makes incremental rendering possible. A completed block can be
/// parsed once and never looked at again; only the tail has to be re-parsed as
/// tokens arrive. Getting the boundary wrong is not a performance bug, it is a
/// correctness bug — freeze a block too early and the rest of its content
/// renders as a separate, wrongly-formatted block.
library;

class BlockSplit {
  const BlockSplit(this.stable, this.tail);

  /// Blocks that cannot change no matter what arrives next.
  final List<String> stable;

  /// The trailing region, which may still be extended by future tokens.
  final String tail;

  @override
  String toString() => 'BlockSplit(stable: ${stable.length}, tail: ${tail.length} chars)';
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

  /// Blocks that cannot change no matter what arrives next.
  List<String> get blocks => List.unmodifiable(_blocks);

  /// Number of settled blocks, for callers that only need to know what is new.
  int get blockCount => _blocks.length;

  /// The trailing region, which may still be extended.
  String get tail {
    if (_currentLines.isEmpty) return _partial;
    return '${_currentLines.join('\n')}\n$_partial';
  }

  void append(String chunk) {
    _partial += chunk;
    var idx = _partial.indexOf('\n');
    while (idx >= 0) {
      _consumeLine(_partial.substring(0, idx));
      _partial = _partial.substring(idx + 1);
      idx = _partial.indexOf('\n');
    }
  }

  /// Only ever called with a line whose terminating newline has arrived, so a
  /// blank line here is a real blank line and not a `split('\n')` artefact.
  void _consumeLine(String line) {
    final trimmed = line.trimLeft();

    if (_inFence) {
      _currentLines.add(line);
      final marker = _fenceMarker;
      if (marker != null &&
          trimmed.startsWith(marker) &&
          trimmed.substring(marker.length).trim().isEmpty) {
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
    if (block.isNotEmpty) _blocks.add(block);
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
      // A fence closes on a line whose marker is at least as long as the opener
      // and which contains nothing else.
      if (fenceMarker != null &&
          trimmed.startsWith(fenceMarker) &&
          trimmed.substring(fenceMarker.length).trim().isEmpty) {
        inFence = false;
        fenceMarker = null;
        // A closed fence is a complete leaf block — no later text can extend
        // it — so it settles immediately rather than waiting for a blank line.
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
      if (fenceMarker != null &&
          trimmed.startsWith(fenceMarker) &&
          trimmed.substring(fenceMarker.length).trim().isEmpty) {
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
