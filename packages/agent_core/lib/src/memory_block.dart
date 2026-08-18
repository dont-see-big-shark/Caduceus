/// The one part of a memory file this app owns.
///
/// `agents.files.set` replaces a whole file — there is no patch method — and
/// that file is one a person edits by hand and the agent edits with its own
/// tools. Writing a whole file from a stale read destroys both. So Caduceus
/// claims exactly one delimited block and splices into it, and the invariant
/// every test in `memory_block_test.dart` exists to hold is:
///
/// > **every byte outside the markers is identical before and after.**
///
/// See `MEMORY_BRIDGE.md` §4 R1.
library;

import 'package:meta/meta.dart';

/// Where the app's block starts and ends in a memory file.
///
/// HTML comments because both files are markdown: they render as nothing in
/// every viewer, and the agent reading the file sees no instruction it might
/// act on.
const memoryBlockBegin = '<!-- caduceus:begin -->';
const memoryBlockEnd = '<!-- caduceus:end -->';

/// A memory file, split into the part this app owns and the parts it does not.
@immutable
class MemoryBlock {
  const MemoryBlock({
    required this.before,
    required this.body,
    required this.after,
    required this.hadMarkers,
  });

  /// Everything above [memoryBlockBegin]. Passed through untouched.
  final String before;

  /// What lies between the markers — the only thing a write may change.
  final String body;

  /// Everything below [memoryBlockEnd]. Passed through untouched.
  final String after;

  /// False when the file had no block yet, in which case [before] is the whole
  /// file and a write appends rather than replacing.
  final bool hadMarkers;

  /// Reads [content], finding the app's block if there is one.
  ///
  /// Three cases are deliberately *not* treated as a block, because each of
  /// them would otherwise cause a write to eat text it does not own:
  ///
  ///  * a begin marker with no end marker — truncating from the opener to EOF
  ///    is the worst possible reading of a half-written file;
  ///  * an end marker before the begin marker;
  ///  * markers inside a fenced code block, which is text *about* the format
  ///    rather than an instance of it — this very file's documentation would
  ///    otherwise be parsed as a block if it were ever pasted into a memory.
  factory MemoryBlock.parse(String content) {
    final fenced = _fencedRanges(content);
    bool outside(int at) => !fenced.any((r) => at >= r.$1 && at < r.$2);

    final begin = _indexOutside(content, memoryBlockBegin, outside);
    if (begin < 0) return _unmarked(content);

    final endFrom = begin + memoryBlockBegin.length;
    final end = _indexOutside(content, memoryBlockEnd, outside, from: endFrom);
    if (end < 0) return _unmarked(content);

    return MemoryBlock(
      before: content.substring(0, begin),
      body: content.substring(endFrom, end),
      after: content.substring(end + memoryBlockEnd.length),
      hadMarkers: true,
    );
  }

  static MemoryBlock _unmarked(String content) => MemoryBlock(
    before: content,
    body: '',
    after: '',
    hadMarkers: false,
  );

  /// The first [needle] at or after [from] that [outside] accepts.
  static int _indexOutside(
    String content,
    String needle,
    bool Function(int) outside, {
    int from = 0,
  }) {
    var at = content.indexOf(needle, from);
    while (at >= 0 && !outside(at)) {
      at = content.indexOf(needle, at + 1);
    }
    return at;
  }

  /// Half-open ranges covering every fenced code block.
  ///
  /// Tracks the fence *length* so a ``` inside a ```` block does not close it,
  /// which is how a memory containing an example of a memory file would
  /// otherwise confuse the parser.
  static List<(int, int)> _fencedRanges(String content) {
    final ranges = <(int, int)>[];
    final lines = content.split('\n');
    var offset = 0;
    int? openAt;
    var openLength = 0;
    for (final line in lines) {
      final trimmed = line.trimLeft();
      final match = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed);
      if (match != null) {
        final fence = match.group(1)!;
        if (openAt == null) {
          openAt = offset;
          openLength = fence.length;
        } else if (fence[0] == content[openAt + (line.length - trimmed.length)]
            ? fence.length >= openLength
            : false) {
          ranges.add((openAt, offset + line.length));
          openAt = null;
        }
      }
      offset += line.length + 1;
    }
    // An unclosed fence runs to the end — text inside it is still not markup.
    if (openAt != null) ranges.add((openAt, content.length));
    return ranges;
  }

  /// [content] with the app's block replaced by [body].
  ///
  /// Appends a block when there was none, so a first write to a file someone
  /// has been keeping by hand adds to it rather than replacing it.
  static String write(String content, String body) {
    final block = MemoryBlock.parse(content);
    final rendered = '$memoryBlockBegin\n${body.trim()}\n$memoryBlockEnd';
    if (block.hadMarkers) {
      return '${block.before}$rendered${block.after}';
    }
    if (content.trim().isEmpty) return '$rendered\n';
    final separator = content.endsWith('\n\n')
        ? ''
        : (content.endsWith('\n') ? '\n' : '\n\n');
    return '$content$separator$rendered\n';
  }

  /// [content] with the app's block removed entirely, markers and all.
  ///
  /// The way to stop managing a file without leaving its markers behind for a
  /// future version to mistake for an empty block.
  static String clear(String content) {
    final block = MemoryBlock.parse(content);
    if (!block.hadMarkers) return content;
    final joined = '${block.before}${block.after}';
    // The block usually sits on its own lines; collapse the blank pair it
    // leaves rather than growing a gap every time it is cleared.
    return joined.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  @override
  String toString() =>
      'MemoryBlock(${hadMarkers ? '${body.length} chars' : 'no block'})';
}
