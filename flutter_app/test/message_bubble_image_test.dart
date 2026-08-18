import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/widgets/message_bubble.dart';
import 'package:caduceus/transcript_blobs.dart';
import 'package:caduceus/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A tiny 1x1 transparent GIF base64 encoded
  final tinyGifBase64 = base64Encode(
    Uint8List.fromList([
      0x47,
      0x49,
      0x46,
      0x38,
      0x39,
      0x61,
      0x01,
      0x00,
      0x01,
      0x00,
      0x80,
      0x00,
      0x00,
      0xff,
      0xff,
      0xff,
      0x00,
      0x00,
      0x00,
      0x21,
      0xf9,
      0x04,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x2c,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x00,
      0x02,
      0x02,
      0x44,
      0x01,
      0x00,
      0x3b,
    ]),
  );

  testWidgets('UserBubble renders plain text without images', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UserBubble(text: '你好')),
      ),
    );

    expect(find.text('你好'), findsOneWidget);
    expect(find.byType(ChatImageView), findsNothing);
  });

  testWidgets('UserBubble renders image and text together', (tester) async {
    final markdown =
        '![caduceus.gif](data:image/gif;base64,$tinyGifBase64)\n\n你好';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UserBubble(text: markdown)),
      ),
    );

    expect(find.text('你好'), findsOneWidget);
    expect(find.byType(ChatImageView), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('UserBubble renders image alone', (tester) async {
    final markdown = '![caduceus.gif](data:image/gif;base64,$tinyGifBase64)';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UserBubble(text: markdown)),
      ),
    );

    expect(find.byType(ChatImageView), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  test('appendLocalPrompt appends image attachments into markdown', () {
    final console = SessionConsole(persistedId: 'test_session');
    final attachment = Attachment(
      name: 'caduceus.png',
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'image/png',
    );

    console.appendLocalPrompt('你好', attachments: [attachment]);

    expect(console.markdown.text, contains('**You:** '));
    // A reference, not the bytes: the transcript stays text-sized however
    // large the attachment is, and the bytes live in the session's blob store.
    expect(console.markdown.text, contains('![caduceus.png]($blobUriScheme:'));
    expect(console.markdown.text, isNot(contains('base64')));
    expect(console.markdown.text, contains('你好'));

    // The bytes are still reachable through the reference the transcript got.
    final ref = RegExp(
      r'\((caduceus-blob:\d+)\)',
    ).firstMatch(console.markdown.text)!.group(1)!;
    expect(console.blobs.resolve(ref)!.bytes, [1, 2, 3]);

    console.dispose();
  });

  testWidgets('UserBubble parses @image: directive line and hides raw path', (
    tester,
  ) async {
    const raw =
        '你好\n@image:/home/ubuntu/.hermes/images/upload_20260818_000654_1.png';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UserBubble(text: raw)),
      ),
    );

    // Text "你好" is shown, but raw path line is stripped from text and turned into an image widget
    expect(find.text('你好'), findsOneWidget);
    expect(
      find.textContaining('@image:/home/ubuntu/.hermes/images/'),
      findsNothing,
    );
    expect(find.byType(ChatImageView), findsOneWidget);

    // Verify "你好" is above ChatImageView
    final textPos = tester.getTopLeft(find.text('你好'));
    final imagePos = tester.getTopLeft(find.byType(ChatImageView));
    expect(textPos.dy < imagePos.dy, isTrue);
  });

  test(
    'appendLocalPrompt places text before image attachment in single block',
    () {
      final console = SessionConsole(persistedId: 'test_session');
      final attachment = Attachment(
        name: 'caduceus.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );

      console.appendLocalPrompt('你好', attachments: [attachment]);

      // Check that **You:** contains text followed by image in one block without \n\n splitting
      expect(
        console.markdown.text,
        contains('**You:** 你好\n![caduceus.png]($blobUriScheme:'),
      );
      console.dispose();
    },
  );
}
