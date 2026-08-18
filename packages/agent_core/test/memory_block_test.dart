/// The splice, which is the one part of the memory bridge that can lose data.
///
/// `agents.files.set` replaces a whole file. The file belongs to the user and
/// to the agent, both of which edit it. So every test here is a claim about
/// the same invariant, stated once:
///
/// > every byte outside the markers is identical before and after.
///
/// Written before the feature, because the failure mode is not a crash — it is
/// a user's notes quietly disappearing from a file nobody re-reads until they
/// need it.
library;

import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

/// The part of [original] that [MemoryBlock] must never touch.
///
/// Computed by deleting the block from both sides and comparing, rather than
/// by string-matching the expected output — a test that hardcodes the whole
/// expected file passes for the wrong reason the moment the block's rendering
/// changes.
void expectOutsidePreserved(String original, String written) {
  expect(
    MemoryBlock.clear(written).trim(),
    MemoryBlock.clear(original).trim(),
    reason: 'text outside the markers must survive a write byte for byte',
  );
}

void main() {
  group('parse', () {
    test('a file with no markers is all "before", and knows it', () {
      const file = '# Memory\n\n- likes tea\n';
      final block = MemoryBlock.parse(file);

      expect(block.hadMarkers, isFalse);
      expect(block.before, file);
      expect(block.body, isEmpty);
      expect(block.after, isEmpty);
    });

    test('a file with markers splits into three', () {
      const file = 'top\n'
          '$memoryBlockBegin\n'
          'managed\n'
          '$memoryBlockEnd\n'
          'bottom\n';
      final block = MemoryBlock.parse(file);

      expect(block.hadMarkers, isTrue);
      expect(block.before, 'top\n');
      expect(block.body.trim(), 'managed');
      expect(block.after, '\nbottom\n');
    });

    test('an opening marker with no closing one is not a block', () {
      // The dangerous reading: treat everything from the opener to EOF as
      // ours and replace it. A half-written file would take the user's notes
      // with it.
      const file = 'keep me\n$memoryBlockBegin\nhalf written\nand more notes\n';
      final block = MemoryBlock.parse(file);

      expect(block.hadMarkers, isFalse);
      expect(block.before, file, reason: 'the whole file is untouchable');
    });

    test('a closing marker before an opening one is not a block', () {
      const file = '$memoryBlockEnd\nstray\n$memoryBlockBegin\n';
      expect(MemoryBlock.parse(file).hadMarkers, isFalse);
    });

    test('markers inside a fenced code block are text, not markup', () {
      // A memory that documents this very format would otherwise be parsed as
      // an instance of it, and the next write would eat the surrounding note.
      const file = '# How the bridge works\n\n'
          '```markdown\n'
          '$memoryBlockBegin\n'
          'example entry\n'
          '$memoryBlockEnd\n'
          '```\n\n'
          'That is all.\n';
      final block = MemoryBlock.parse(file);

      expect(block.hadMarkers, isFalse);
      expect(block.before, file);
    });

    test('a longer fence is not closed by a shorter one inside it', () {
      const file = '````markdown\n'
          '```\n'
          '$memoryBlockBegin\n'
          '```\n'
          '````\n'
          'after\n';
      expect(
        MemoryBlock.parse(file).hadMarkers,
        isFalse,
        reason: 'the inner ``` does not close the outer ````',
      );
    });

    test('a real block after a fenced example is still found', () {
      const file = '```\n$memoryBlockBegin\n```\n\n'
          '$memoryBlockBegin\nreal\n$memoryBlockEnd\n';
      final block = MemoryBlock.parse(file);

      expect(block.hadMarkers, isTrue);
      expect(block.body.trim(), 'real');
      expect(
        block.before.contains('```'),
        isTrue,
        reason: 'the fenced example stays above, untouched',
      );
    });
  });

  group('write', () {
    test('appends to a file that has no block, keeping every byte', () {
      const file = '# Memory\n\n- likes tea\n- dislikes meetings\n';
      final written = MemoryBlock.write(file, '- prefers Dart');

      expect(written, startsWith(file));
      expect(written, contains('- prefers Dart'));
      expectOutsidePreserved(file, written);
    });

    test('replaces only what is between the markers', () {
      const file = '# Memory\n\n'
          'hand written above\n\n'
          '$memoryBlockBegin\n'
          'old entry\n'
          '$memoryBlockEnd\n\n'
          'hand written below\n';
      final written = MemoryBlock.write(file, 'new entry');

      expect(written, contains('new entry'));
      expect(written, isNot(contains('old entry')));
      expect(written, contains('hand written above'));
      expect(written, contains('hand written below'));
      expectOutsidePreserved(file, written);
    });

    test('the text above and below survives byte for byte', () {
      // Trailing spaces, tabs and CRLF are exactly what a naive
      // line-rejoining implementation silently normalises away.
      const file = 'above with trailing space   \n'
          '\tindented with a tab\n'
          '$memoryBlockBegin\nold\n$memoryBlockEnd\n'
          'below\ttabbed\n   leading spaces\n';
      final written = MemoryBlock.write(file, 'new');

      expect(written, contains('above with trailing space   \n'));
      expect(written, contains('\tindented with a tab\n'));
      expect(written, contains('below\ttabbed\n'));
      expect(written, contains('   leading spaces\n'));
    });

    test('an empty file gets a block and nothing else', () {
      final written = MemoryBlock.write('', '- first thing');
      expect(written.trim(), startsWith(memoryBlockBegin));
      expect(written.trim(), endsWith(memoryBlockEnd));
      expect(written, contains('- first thing'));
    });

    test('writing twice does not nest or duplicate the block', () {
      const file = '# Memory\n\nnotes\n';
      // Distinctive sentinels: a one-letter body collides with the marker
      // text itself, which is a test bug that reads exactly like a real one.
      final once = MemoryBlock.write(file, 'FIRST-BODY');
      final twice = MemoryBlock.write(once, 'SECOND-BODY');

      expect(memoryBlockBegin.allMatches(twice).length, 1);
      expect(memoryBlockEnd.allMatches(twice).length, 1);
      expect(twice, contains('SECOND-BODY'));
      expect(twice, isNot(contains('FIRST-BODY')));
      expectOutsidePreserved(file, twice);
    });

    test('writing an empty body leaves an empty block, not a deleted file', () {
      const file = 'notes\n$memoryBlockBegin\nsomething\n$memoryBlockEnd\n';
      final written = MemoryBlock.write(file, '');

      expect(written, contains('notes'));
      expect(written, contains(memoryBlockBegin));
      expect(written, isNot(contains('something')));
    });

    test('a file that is only a block round-trips', () {
      final once = MemoryBlock.write('', 'ONLY-BODY');
      final twice = MemoryBlock.write(once, 'ONLY-BODY');
      expect(twice.trim(), once.trim());
    });
  });

  group('clear', () {
    test('removes the block and its markers, keeping the rest', () {
      const file = 'above\n\n$memoryBlockBegin\nmanaged\n$memoryBlockEnd\n\nbelow\n';
      final cleared = MemoryBlock.clear(file);

      expect(cleared, contains('above'));
      expect(cleared, contains('below'));
      expect(cleared, isNot(contains('managed')));
      expect(cleared, isNot(contains('caduceus')));
    });

    test('does not grow a gap each time it runs', () {
      const file = 'above\n\n$memoryBlockBegin\nx\n$memoryBlockEnd\n\nbelow\n';
      final once = MemoryBlock.clear(file);
      final twice = MemoryBlock.clear(once);
      expect(twice, once);
      expect(once, isNot(contains('\n\n\n')));
    });

    test('leaves a file with no block alone', () {
      const file = '# Memory\n\nnotes\n';
      expect(MemoryBlock.clear(file), file);
    });
  });

  group('the invariant, over awkward inputs', () {
    // Table-driven because the failure is always the same shape — something
    // outside the block changed — and the interesting part is which input
    // provokes it.
    const files = <String, String>{
      'empty': '',
      'whitespace only': '   \n\n\t\n',
      'no trailing newline': '# Memory\n- one',
      'CRLF line endings': '# Memory\r\n\r\n- one\r\n',
      'unicode': '# 记忆\n\n- 喜欢喝茶 ☕\n- émoji: 🧠\n',
      'a fenced example of the format':
          '```\n$memoryBlockBegin\n$memoryBlockEnd\n```\n',
      'already blocked': 'a\n$memoryBlockBegin\nb\n$memoryBlockEnd\nc\n',
      'block at the very start': '$memoryBlockBegin\nb\n$memoryBlockEnd\ntail\n',
      'block at the very end': 'head\n$memoryBlockBegin\nb\n$memoryBlockEnd',
      'markdown that looks like a marker': '<!-- caduceus -->\nnot a marker\n',
    };

    for (final entry in files.entries) {
      test('outside is preserved — ${entry.key}', () {
        final written = MemoryBlock.write(entry.value, '- managed entry');
        expectOutsidePreserved(entry.value, written);
        expect(
          written,
          contains('- managed entry'),
          reason: 'the write must actually have happened',
        );
      });

      test('write is idempotent for the same body — ${entry.key}', () {
        final once = MemoryBlock.write(entry.value, '- managed entry');
        final twice = MemoryBlock.write(once, '- managed entry');
        expect(
          twice,
          once,
          reason: 'pushing the same ledger twice must not change the file, '
              'or every push looks like a change on the next diff',
        );
      });
    }
  });
}
