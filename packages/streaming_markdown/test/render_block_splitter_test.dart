import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/src/render_block_splitter.dart';

void main() {
  test('large fenced code becomes independently valid segments', () {
    final content = List.generate(101, (i) => 'line $i');
    final block = '```dart\n${content.join('\n')}\n```';

    final chunks = const RenderBlockSplitter(maxLines: 40).split(block);

    expect(chunks, hasLength(3));
    expect(chunks.first, startsWith('```dart'));
    expect(chunks.first.trimRight(), endsWith('```'));
    expect(
      chunks.expand((chunk) {
        final lines = chunk.split('\n');
        return lines.sublist(1, lines.length - 1);
      }),
      equals(content),
    );
  });

  test('large tables repeat their header in every segment', () {
    final rows = List.generate(81, (i) => '| $i | row $i |');
    final block = '| id | name |\n|---:|---|\n${rows.join('\n')}';

    final chunks = const RenderBlockSplitter(maxLines: 40).split(block);

    expect(chunks, hasLength(3));
    expect(chunks.every((chunk) => chunk.startsWith('| id | name |')), isTrue);
    expect(chunks.expand((chunk) => chunk.split('\n').skip(2)), equals(rows));
  });

  test('paragraphs and small blocks stay intact', () {
    const block = 'A paragraph\ncontinues here.';

    expect(const RenderBlockSplitter().split(block), [block]);
  });

  test('large plain paragraphs split into line-bounded segments', () {
    final lines = List.generate(101, (i) => 'paragraph line $i');
    final block = lines.join('\n');

    final segments = const RenderBlockSplitter(
      maxLines: 40,
    ).splitSegments(block);

    expect(segments, hasLength(3));
    expect(segments.map((segment) => segment.markdown).join('\n'), block);
    expect(segments.first.sourceStart, 0);
    expect(segments.first.sourceEnd, block.indexOf('paragraph line 40'));
    expect(segments.last.sourceEnd, block.length);
  });

  test('large lists split at top-level item boundaries', () {
    final lines = <String>[
      for (var i = 0; i < 50; i++) ...['- item $i', '  continuation $i'],
    ];
    final block = lines.join('\n');

    final chunks = const RenderBlockSplitter(maxLines: 20).split(block);

    expect(chunks, isNotEmpty);
    expect(chunks.first.split('\n').first, '- item 0');
    expect(
      chunks
          .skip(1)
          .every((chunk) => chunk.split('\n').first.startsWith('- item ')),
      isTrue,
    );
    expect(chunks.expand((chunk) => chunk.split('\n')), equals(lines));
  });

  test('ordered lists preserve their original numbering across segments', () {
    final lines = [for (var i = 8; i < 68; i++) '$i. item $i'];
    final block = lines.join('\n');

    final chunks = const RenderBlockSplitter(maxLines: 20).split(block);

    expect(chunks.first.split('\n').first, '8. item 8');
    expect(chunks[1].split('\n').first, '28. item 28');
    expect(chunks[2].split('\n').first, '48. item 48');
  });
}
