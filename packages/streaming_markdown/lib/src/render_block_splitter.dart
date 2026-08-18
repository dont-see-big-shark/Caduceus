/// Splits large Markdown blocks into independently renderable segments.
///
/// The data-layer splitter preserves Markdown semantics by never breaking a
/// block early. This class works one level lower: it turns constructs that are
/// safe to present as smaller Markdown documents into separate strings so a
/// lazy list can render only the visible portion.
library;

/// One independently renderable part of a larger logical Markdown block.
abstract interface class RenderBlockSegment {
  /// Markdown for this render segment.
  String get markdown;

  /// First source character represented by this segment.
  int get sourceStart;

  /// Character position just after the source represented by this segment.
  int get sourceEnd;
}

class _RenderBlockSegmentImpl implements RenderBlockSegment {
  const _RenderBlockSegmentImpl(
    this.markdown,
    this.sourceStart,
    this.sourceEnd,
  );

  @override
  final String markdown;
  @override
  final int sourceStart;
  @override
  final int sourceEnd;
}

/// Divides supported oversized Markdown constructs into render segments.
///
/// Segments are presentation-only: callers continue to address the original
/// logical block, which keeps transcript indices and anchors stable.
class RenderBlockSplitter {
  const RenderBlockSplitter({this.maxLines = 80});

  /// Maximum content lines in one rendered segment.
  final int maxLines;

  /// Returns one or more Markdown documents that render the original block.
  List<String> split(String block) =>
      splitSegments(block).map((segment) => segment.markdown).toList();

  /// Returns render segments and their source ranges in [block].
  List<RenderBlockSegment> splitSegments(String block) {
    if (maxLines < 1 || block.isEmpty) {
      return [_RenderBlockSegmentImpl(block, 0, block.length)];
    }

    final lines = block.split('\n');
    if (lines.length <= maxLines) {
      return [_RenderBlockSegmentImpl(block, 0, block.length)];
    }

    final lineStarts = _lineStarts(lines);
    final sourceLength = block.length;
    final code = _splitFencedCode(lines, lineStarts, sourceLength);
    if (code != null) return code;

    final table = _splitTable(lines, lineStarts, sourceLength);
    if (table != null) return table;

    final list = _splitList(lines, lineStarts, sourceLength);
    if (list != null) return list;

    final paragraph = _splitParagraph(lines, lineStarts, sourceLength);
    return paragraph ?? [_RenderBlockSegmentImpl(block, 0, block.length)];
  }

  List<RenderBlockSegment>? _splitFencedCode(
    List<String> lines,
    List<int> lineStarts,
    int sourceLength,
  ) {
    if (lines.length < 3) return null;

    final opening = lines.first.trimLeft();
    final marker = _openingFence(opening);
    if (marker == null) return null;
    if (!_isFenceEnding(lines.last.trimLeft(), marker)) return null;

    final content = lines.sublist(1, lines.length - 1);
    if (content.length <= maxLines) return null;

    final chunks = <RenderBlockSegment>[];
    for (var start = 0; start < content.length; start += maxLines) {
      final end = (start + maxLines).clamp(0, content.length);
      final sourceStart = start == 0 ? 0 : lineStarts[start + 1];
      final sourceEnd = end == content.length
          ? sourceLength
          : lineStarts[end + 1];
      final markdown = [
        lines.first,
        ...content.sublist(start, end),
        marker,
      ].join('\n');
      chunks.add(_RenderBlockSegmentImpl(markdown, sourceStart, sourceEnd));
    }
    return chunks;
  }

  List<RenderBlockSegment>? _splitTable(
    List<String> lines,
    List<int> lineStarts,
    int sourceLength,
  ) {
    if (lines.length < 3) return null;

    final header = lines[0].trimLeft();
    final delimiter = lines[1].trimLeft();
    final rows = lines.sublist(2);
    final isTable =
        header.startsWith('|') &&
        RegExp(r'^\|?\s*:?-{3,}').hasMatch(delimiter) &&
        rows.every((row) => row.trimLeft().startsWith('|'));
    if (!isTable || rows.length <= maxLines) return null;

    final chunks = <RenderBlockSegment>[];
    for (var start = 0; start < rows.length; start += maxLines) {
      final end = (start + maxLines).clamp(0, rows.length);
      final sourceStart = start == 0 ? 0 : lineStarts[start + 2];
      final sourceEnd = end == rows.length ? sourceLength : lineStarts[end + 2];
      final markdown = [
        lines[0],
        lines[1],
        ...rows.sublist(start, end),
      ].join('\n');
      chunks.add(_RenderBlockSegmentImpl(markdown, sourceStart, sourceEnd));
    }
    return chunks;
  }

  List<RenderBlockSegment>? _splitList(
    List<String> lines,
    List<int> lineStarts,
    int sourceLength,
  ) {
    if (!_topLevelListMarker.hasMatch(lines.first)) return null;

    final itemStarts = <int>[
      for (var i = 1; i < lines.length; i++)
        if (_topLevelListMarker.hasMatch(lines[i])) i,
    ];

    final chunks = <RenderBlockSegment>[];
    for (var start = 0; start < lines.length;) {
      var end = (start + maxLines).clamp(0, lines.length);
      if (end < lines.length) {
        final boundary = _lastValueNotAfter(itemStarts, end);
        if (boundary > start) end = boundary;
      }

      final sourceStart = lineStarts[start];
      final sourceEnd = end == lines.length ? sourceLength : lineStarts[end];
      final List<String> markdownLines;
      if (_topLevelListMarker.hasMatch(lines[start])) {
        markdownLines = lines.sublist(start, end);
      } else {
        final itemStart = _lastValueNotAfter(itemStarts, start + 1) - 1;
        final markerPrefix = _markerPrefix(lines[itemStart]);
        markdownLines = [markerPrefix, ...lines.sublist(start, end)];
      }
      chunks.add(
        _RenderBlockSegmentImpl(
          markdownLines.join('\n'),
          sourceStart,
          sourceEnd,
        ),
      );
      start = end;
    }
    return chunks;
  }

  List<RenderBlockSegment>? _splitParagraph(
    List<String> lines,
    List<int> lineStarts,
    int sourceLength,
  ) {
    if (!lines.every(_isPlainParagraphLine)) return null;

    final chunks = <RenderBlockSegment>[];
    for (var start = 0; start < lines.length; start += maxLines) {
      final end = (start + maxLines).clamp(0, lines.length);
      chunks.add(
        _RenderBlockSegmentImpl(
          lines.sublist(start, end).join('\n'),
          lineStarts[start],
          end == lines.length ? sourceLength : lineStarts[end],
        ),
      );
    }
    return chunks;
  }

  int _lastValueNotAfter(List<int> values, int limit) {
    var result = -1;
    for (final value in values) {
      if (value > limit) break;
      result = value;
    }
    return result;
  }

  String _markerPrefix(String line) =>
      line.substring(0, _topLevelListMarker.firstMatch(line)!.end);
}

final RegExp _topLevelListMarker = RegExp(
  r'^ {0,3}(?:(?:[-+*])\s+|(?:\d{1,9}[.)])\s+)',
);

bool _isPlainParagraphLine(String line) {
  if (line.startsWith('    ')) return false;
  final trimmed = line.trimLeft();
  return !trimmed.startsWith(RegExp(r'^(?:[#>|]|```|~~~|<)')) &&
      !_topLevelListMarker.hasMatch(trimmed) &&
      trimmed != '---' &&
      trimmed != '***' &&
      trimmed != '___';
}

List<int> _lineStarts(List<String> lines) {
  final starts = List<int>.filled(lines.length, 0);
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    starts[i] = offset;
    offset += lines[i].length + 1;
  }
  return starts;
}

String? _openingFence(String trimmed) {
  for (final char in const ['`', '~']) {
    if (!trimmed.startsWith(char * 3)) continue;
    var length = 0;
    while (length < trimmed.length && trimmed[length] == char) {
      length++;
    }

    final info = trimmed.substring(length);
    if (char == '`' && info.contains('`')) return null;
    return char * length;
  }
  return null;
}

bool _isFenceEnding(String trimmed, String marker) =>
    trimmed.startsWith(marker) &&
    trimmed.substring(marker.length).trim().isEmpty;
