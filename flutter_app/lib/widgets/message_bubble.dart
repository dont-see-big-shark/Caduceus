import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../transcript_blobs.dart';

/// The marker a user prompt carries in the transcript.
///
/// The transcript is one Markdown document rather than a list of message
/// objects — that is what makes the incremental renderer possible — so the
/// only thing distinguishing a question from an answer is this prefix. It is
/// written by `SessionConsole.appendLocalPrompt` and recognised here.
const userPromptMarker = '**You:** ';

/// Whether a settled block is something the user said.
bool isUserBlock(String data) => data.trimLeft().startsWith(userPromptMarker);

/// Strips the marker so the bubble shows the question, not the label.
String userBlockText(String data) {
  final t = data.trimLeft();
  return t.startsWith(userPromptMarker)
      ? t.substring(userPromptMarker.length).trim()
      : t.trim();
}

sealed class _UserMessagePart {}

class _TextPart extends _UserMessagePart {
  _TextPart(this.text);
  final String text;
}

class _ImagePart extends _UserMessagePart {
  _ImagePart({required this.alt, required this.src});
  final String alt;
  final String src;
}

List<_UserMessagePart> _parseUserParts(String raw) {
  final imageDirectiveRegex = RegExp(r'^@image:[^\n]*\n?', multiLine: true);
  final fileDirectiveRegex = RegExp(r'^@file:[^\n]*\n?', multiLine: true);
  final screenshotRegex = RegExp(r'^\[screenshot\]\n?', multiLine: true);

  final imageParts = <_ImagePart>[];

  var cleaned = raw.replaceAllMapped(imageDirectiveRegex, (match) {
    final line = match.group(0)!.trim();
    if (line.startsWith('@image:')) {
      final path = line.substring('@image:'.length).trim();
      if (path.isNotEmpty) {
        final name = path.split('/').last.split('\\').last;
        imageParts.add(_ImagePart(alt: name, src: path));
      }
    }
    return '';
  });

  cleaned = cleaned.replaceAllMapped(fileDirectiveRegex, (match) {
    final line = match.group(0)!.trim();
    if (line.startsWith('@file:')) {
      final path = line.substring('@file:'.length).trim();
      final lower = path.toLowerCase();
      if (lower.endsWith('.png') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.svg') ||
          lower.endsWith('.bmp')) {
        final name = path.split('/').last.split('\\').last;
        imageParts.add(_ImagePart(alt: name, src: path));
        return '';
      }
    }
    return match.group(0)!;
  });

  if (imageParts.isNotEmpty) {
    cleaned = cleaned.replaceAll(screenshotRegex, '');
  }

  cleaned = cleaned.trim();

  final markdownImageRegex = RegExp(r'!\[([^\]]*)\]\((.*?)\)', dotAll: true);
  final parts = <_UserMessagePart>[];
  var lastIndex = 0;

  for (final match in markdownImageRegex.allMatches(cleaned)) {
    if (match.start > lastIndex) {
      final text = cleaned.substring(lastIndex, match.start).trim();
      if (text.isNotEmpty) {
        parts.add(_TextPart(text));
      }
    }
    final alt = match.group(1)?.trim() ?? '';
    final src = match.group(2)?.trim() ?? '';
    if (src.isNotEmpty) {
      parts.add(_ImagePart(alt: alt, src: src));
    }
    lastIndex = match.end;
  }

  if (lastIndex < cleaned.length) {
    final text = cleaned.substring(lastIndex).trim();
    if (text.isNotEmpty) {
      parts.add(_TextPart(text));
    }
  }

  if (imageParts.isNotEmpty) {
    parts.addAll(imageParts);
  }

  if (parts.isEmpty && cleaned.isNotEmpty) {
    parts.add(_TextPart(cleaned));
  }

  return parts;
}

final Map<int, List<_UserMessagePart>> _parsedPartsCache = {};

List<_UserMessagePart> _getParsedUserParts(String raw) {
  final key = raw.hashCode;
  final cached = _parsedPartsCache[key];
  if (cached != null) return cached;
  final parts = _parseUserParts(raw);
  if (_parsedPartsCache.length > 100) {
    _parsedPartsCache.clear();
  }
  _parsedPartsCache[key] = parts;
  return parts;
}

/// A question, as a bubble on the trailing side.
///
/// Right-aligned and filled, so the eye can find where each exchange starts
/// without reading. Supports both text and attached/uploaded images.
class UserBubble extends StatelessWidget {
  const UserBubble({required this.text, super.key});

  final String text;

  /// The one corner that is not round, marking which side said it.
  static const _shape = BorderRadius.only(
    topLeft: Radius.circular(18),
    topRight: Radius.circular(18),
    bottomLeft: Radius.circular(18),
    bottomRight: Radius.circular(4),
  );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final parts = _getParsedUserParts(text);

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(
          // Not `end` on its own: the bubble must also stop growing before it
          // spans the full width, or a long question is indistinguishable from
          // an answer again.
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 10.5,
                  ),
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF222634)
                        : const Color(0xFFE9ECF2),
                    borderRadius: _shape,
                    border: Border.all(
                      color: dark
                          ? const Color(0xFF2E3346)
                          : const Color(0xFFDCE0EA),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < parts.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        switch (parts[i]) {
                          final _TextPart p => SelectableText(
                            p.text,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.45,
                              color: dark
                                  ? const Color(0xFFF3F4F8)
                                  : const Color(0xFF14161D),
                              letterSpacing: -0.1,
                            ),
                          ),
                          final _ImagePart p => ChatImageView(
                            src: p.src,
                            alt: p.alt,
                          ),
                        },
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A chat image source, resolved from its `src` string exactly once.
///
/// Resolving is not free: a data URI has to be stripped of whitespace and
/// base64-decoded, and a bare path needs a `stat` to tell a local file from a
/// broken link. Doing that inside `build` meant re-decoding megabytes and
/// re-hitting the disk on every frame the bubble was scrolled across.
sealed class _ImageSource {
  const _ImageSource();

  /// Parses [src]. Never throws: an unusable source resolves to
  /// [_UnusableImage] so the caller renders a placeholder instead of failing.
  ///
  /// [blobs] resolves `caduceus-blob:` references, and is null outside a
  /// session — a preview, a test — where such a reference cannot be resolved
  /// and renders as a placeholder.
  factory _ImageSource.parse(String src, {TranscriptBlobStore? blobs}) {
    if (isBlobUri(src)) {
      final blob = blobs?.resolve(src);
      // Null covers both "no store in scope" and "evicted under the byte
      // budget"; neither is recoverable here and both show a placeholder.
      return blob == null
          ? const _UnusableImage()
          : _MemoryImageSource(blob.bytes);
    }
    if (src.startsWith('data:image/')) {
      final commaIdx = src.indexOf(',');
      if (commaIdx == -1) return const _UnusableImage();
      try {
        final b64 = src.substring(commaIdx + 1).replaceAll(RegExp(r'\s+'), '');
        return _MemoryImageSource(base64Decode(b64));
      } catch (_) {
        return const _UnusableImage();
      }
    }
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return _NetworkImageSource(src);
    }
    if (src.startsWith('file://')) {
      try {
        return _FileImageSource(File(Uri.parse(src).toFilePath()));
      } catch (_) {
        return const _UnusableImage();
      }
    }
    // The one case that needs the disk. Checked here, once, rather than on
    // every build.
    if (File(src).existsSync()) return _FileImageSource(File(src));
    return const _UnusableImage();
  }
}

class _MemoryImageSource extends _ImageSource {
  const _MemoryImageSource(this.bytes);
  final Uint8List bytes;
}

class _NetworkImageSource extends _ImageSource {
  const _NetworkImageSource(this.url);
  final String url;
}

class _FileImageSource extends _ImageSource {
  const _FileImageSource(this.file);
  final File file;
}

class _UnusableImage extends _ImageSource {
  const _UnusableImage();
}

/// Renders a chat image from base64 data URI, HTTP URL, or local file.
class ChatImageView extends StatefulWidget {
  const ChatImageView({required this.src, this.alt = '', super.key});

  final String src;
  final String alt;

  @override
  State<ChatImageView> createState() => _ChatImageViewState();
}

class _ChatImageViewState extends State<ChatImageView> {
  _ImageSource? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolved here rather than in initState because a blob reference needs
    // the store from the enclosing scope.
    _resolve();
  }

  @override
  void didUpdateWidget(ChatImageView old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src) _resolve();
  }

  void _resolve() {
    _source = _ImageSource.parse(
      widget.src,
      blobs: TranscriptBlobScope.maybeOf(context),
    );
  }

  Widget _buildImage(BuildContext context, {bool highRes = false}) {
    // Full-resolution decode only for the zoomable dialog; the bubble itself
    // never needs more than its 380 pt box.
    final cacheWidth = highRes ? null : 800;

    return switch (_source) {
      _MemoryImageSource(:final bytes) => Image.memory(
        bytes,
        cacheWidth: cacheWidth,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _errorPlaceholder(context),
      ),
      _NetworkImageSource(:final url) => Image.network(
        url,
        cacheWidth: cacheWidth,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
        errorBuilder: (context, error, stackTrace) =>
            _errorPlaceholder(context),
      ),
      _FileImageSource(:final file) => Image.file(
        file,
        cacheWidth: cacheWidth,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            _errorPlaceholder(context),
      ),
      _UnusableImage() => _errorPlaceholder(context),
      null => _errorPlaceholder(context),
    };
  }

  @override
  Widget build(BuildContext context) {
    final preview = _buildImage(context, highRes: false);

    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320, maxWidth: 380),
          child: preview,
        ),
      ),
    );
  }

  Widget _errorPlaceholder(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Tooltip(
        message: widget.alt.isEmpty ? 'Image' : widget.alt,
        child: const Icon(Icons.broken_image_outlined, size: 24),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    final highResImage = _buildImage(context, highRes: true);
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: highResImage,
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
