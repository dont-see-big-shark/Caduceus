/// Behaviour of the store that keeps transcript images out of the transcript
/// text.
///
/// The point of the store is a bounded byte budget, so the tests that matter
/// are the ones about what happens at the boundary: what is evicted, what
/// survives, and what a reference to an evicted image does.
library;

import 'dart:typed_data';

import 'package:caduceus/transcript_blobs.dart';
import 'package:flutter_test/flutter_test.dart';

TranscriptBlob _blob(String name, int bytes) =>
    TranscriptBlob(name: name, bytes: Uint8List(bytes), mimeType: 'image/png');

void main() {
  test('a stored image is reachable through the reference it returned', () {
    final store = TranscriptBlobStore();
    final ref = store.put(
      TranscriptBlob(
        name: 'shot.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      ),
    );

    expect(isBlobUri(ref), isTrue);
    final blob = store.resolve(ref);
    expect(blob, isNotNull);
    expect(blob!.bytes, [1, 2, 3]);
    expect(blob.name, 'shot.png');
    expect(blob.mimeType, 'image/png');
  });

  test('each image gets its own reference', () {
    final store = TranscriptBlobStore();
    final first = store.put(_blob('a.png', 10));
    final second = store.put(_blob('b.png', 10));

    expect(first, isNot(second));
    expect(store.resolve(first)!.name, 'a.png');
    expect(store.resolve(second)!.name, 'b.png');
  });

  test('a non-blob src resolves to null rather than throwing', () {
    final store = TranscriptBlobStore();
    expect(store.resolve('https://example.com/a.png'), isNull);
    expect(store.resolve('data:image/png;base64,AQID'), isNull);
    expect(store.resolve('caduceus-blob:999'), isNull);
  });

  test('eviction is by bytes, so one big image outweighs many small', () {
    // Budget fits two 400-byte images; the third must push the first out.
    final store = TranscriptBlobStore(maxBytes: 1000);
    final first = store.put(_blob('first.png', 400));
    final second = store.put(_blob('second.png', 400));
    final third = store.put(_blob('third.png', 400));

    expect(store.resolve(first), isNull, reason: 'oldest should be evicted');
    expect(store.resolve(second), isNotNull);
    expect(store.resolve(third), isNotNull);
    expect(store.retainedBytes, lessThanOrEqualTo(1000));
  });

  test('resolving marks an image as recently used, protecting it', () {
    final store = TranscriptBlobStore(maxBytes: 1000);
    final first = store.put(_blob('first.png', 400));
    final second = store.put(_blob('second.png', 400));

    // Touch the older one: it is now the *most* recently used, so the next
    // insertion must evict `second` instead.
    expect(store.resolve(first), isNotNull);
    final third = store.put(_blob('third.png', 400));

    expect(store.resolve(first), isNotNull, reason: 'was just used');
    expect(store.resolve(second), isNull, reason: 'now least recently used');
    expect(store.resolve(third), isNotNull);
  });

  test('an image larger than the whole budget does not wedge the store', () {
    final store = TranscriptBlobStore(maxBytes: 100);
    final huge = store.put(_blob('huge.png', 5000));

    // It cannot be retained, but the store stays consistent and usable.
    expect(store.resolve(huge), isNull);
    expect(store.retainedBytes, 0);
    expect(store.length, 0);

    final small = store.put(_blob('small.png', 50));
    expect(store.resolve(small), isNotNull);
  });

  test('clear drops every image and its bytes', () {
    final store = TranscriptBlobStore();
    final ref = store.put(_blob('a.png', 500));
    expect(store.retainedBytes, 500);

    store.clear();

    expect(store.resolve(ref), isNull);
    expect(store.retainedBytes, 0);
    expect(store.length, 0);
  });
}
