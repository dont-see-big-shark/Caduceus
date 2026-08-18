import 'dart:typed_data';

import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('Attachment', () {
    test('isImage true for an image/* mime type', () {
      final attachment = Attachment(
        name: 'photo.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      );
      expect(attachment.isImage, isTrue);
    });

    test('isImage false for a non-image mime type', () {
      final attachment = Attachment(
        name: 'notes.txt',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'text/plain',
      );
      expect(attachment.isImage, isFalse);
    });

    test('sizeBytes reflects the byte length', () {
      final attachment = Attachment(
        name: 'file.bin',
        bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
      );
      expect(attachment.sizeBytes, 5);
    });
  });
}
