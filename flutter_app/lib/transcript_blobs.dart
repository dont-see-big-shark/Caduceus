/// Byte storage for images that appear in a transcript.
///
/// The transcript is one Markdown document, which is what makes incremental
/// rendering possible — but it means anything shown inline has to be
/// expressible as text. Attaching an image used to base64-encode it directly
/// into that document, which cost 1.37x the file size in a string that lived
/// as long as the session and was copied by every operation that touched the
/// transcript. A 2 MB screenshot became 2.7 MB of permanently-resident text.
///
/// Instead the document carries a short `caduceus-blob:<id>` reference and the
/// bytes live here, under an explicit budget: images are the one payload a
/// session can accumulate without bound, so this is the place that decides
/// what to forget.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// The URI scheme a transcript uses to point at [TranscriptBlobStore].
const blobUriScheme = 'caduceus-blob';

/// Whether [src] is a reference into a [TranscriptBlobStore].
bool isBlobUri(String src) => src.startsWith('$blobUriScheme:');

/// The id inside a `caduceus-blob:<id>` reference, or null if [src] is not one.
String? blobIdOf(String src) =>
    isBlobUri(src) ? src.substring(blobUriScheme.length + 1) : null;

/// An image held out of the transcript text.
class TranscriptBlob {
  const TranscriptBlob({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;

  int get sizeBytes => bytes.length;
}

/// A per-session, size-bounded store of transcript images.
///
/// Eviction is least-recently-used and driven by total bytes rather than
/// entry count, because the thing being protected is a byte budget and one
/// 8 MB screenshot is not equivalent to eighty 100 KB thumbnails.
///
/// An evicted image does not corrupt the transcript: the reference stays, and
/// the renderer shows a placeholder. That is the intended trade — a session
/// scrolled far enough back loses old screenshots before it loses the ability
/// to keep chatting.
class TranscriptBlobStore {
  TranscriptBlobStore({this.maxBytes = 32 * 1024 * 1024});

  /// Total bytes retained before the least-recently-used image is dropped.
  final int maxBytes;

  /// Insertion-ordered, and reinserted on read, so the first key is always the
  /// least recently used.
  final LinkedHashMap<String, TranscriptBlob> _blobs = LinkedHashMap();

  int _bytes = 0;
  int _nextId = 0;

  /// Bytes currently retained.
  int get retainedBytes => _bytes;

  /// Number of images currently retained.
  int get length => _blobs.length;

  /// Stores [blob] and returns the `caduceus-blob:<id>` reference for it.
  String put(TranscriptBlob blob) {
    final id = '${_nextId++}';
    _blobs[id] = blob;
    _bytes += blob.sizeBytes;
    _evict();
    return '$blobUriScheme:$id';
  }

  /// The image [src] refers to, or null if it was never stored or has been
  /// evicted. Marks the entry as most recently used.
  TranscriptBlob? resolve(String src) {
    final id = blobIdOf(src);
    if (id == null) return null;
    final blob = _blobs.remove(id);
    if (blob == null) return null;
    _blobs[id] = blob;
    return blob;
  }

  /// Drops everything, for a transcript that is being rebuilt from scratch.
  void clear() {
    _blobs.clear();
    _bytes = 0;
  }

  void _evict() {
    while (_bytes > maxBytes && _blobs.isNotEmpty) {
      final oldest = _blobs.keys.first;
      _bytes -= _blobs.remove(oldest)!.sizeBytes;
    }
  }
}

/// Makes the active session's [TranscriptBlobStore] reachable from the widgets
/// that render transcript images.
///
/// Those widgets sit at the bottom of a Markdown render tree built by a
/// package that knows nothing about sessions, so threading the store down as a
/// constructor argument would mean routing it through every intermediate
/// builder. Scoping it to the context instead keeps the renderer generic.
class TranscriptBlobScope extends InheritedWidget {
  const TranscriptBlobScope({
    required this.store,
    required super.child,
    super.key,
  });

  final TranscriptBlobStore store;

  /// The store in scope, or null when rendering outside a session — a preview,
  /// a test, a detached bubble. Callers must handle null by showing a
  /// placeholder rather than assuming a store is present.
  static TranscriptBlobStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TranscriptBlobScope>()?.store;

  @override
  bool updateShouldNotify(TranscriptBlobScope old) => old.store != store;
}
