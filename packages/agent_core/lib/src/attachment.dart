/// Something sent alongside a message.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A file or image travelling with a prompt.
///
/// Carries [bytes] rather than a path because the two backends disagree about
/// where a file lives: Hermes uploads it, OpenClaw's gateway may be on another
/// machine entirely, and on a phone the "path" is a security-scoped URL that
/// stops resolving the moment the picker closes. Bytes are the only form all
/// three can use, and reading them is the picker's job, not the adapter's.
@immutable
class Attachment {
  const Attachment({
    required this.name,
    required this.bytes,
    this.mimeType = 'application/octet-stream',
  });

  /// The name to show and to send. A base name — never a device path, which
  /// would leak the local directory layout to the server.
  final String name;

  final Uint8List bytes;
  final String mimeType;

  int get sizeBytes => bytes.length;

  bool get isImage => mimeType.startsWith('image/');

  @override
  String toString() => 'Attachment($name, $sizeBytes bytes, $mimeType)';
}
