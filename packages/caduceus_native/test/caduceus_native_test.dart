import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:caduceus_native/caduceus_native.dart';

void main() {
  test('native library is loaded', () {
    expect(CaduceusNativeLoader.isAvailable, isTrue, reason: 'Loader must find dylib');
    expect(CaduceusNativeBindings.instance, isNotNull, reason: 'Bindings must resolve symbols');
  });

  group('CaduceusNative Phase 1: Markdown & Text', () {
    test('splitBlocks identifies fenced code and paragraphs', () {
      const text = '# Heading\n\nParagraph 1\n\n```dart\nvoid main() {}\n```\n\nParagraph 2';
      final result = MarkdownNative.splitBlocks(text);
      expect(result, isNotNull);
      expect(result!.spans.length, greaterThanOrEqualTo(3));
      expect(result.tailStart, greaterThan(0));
    });

    test('normalizeFingerprint strips markdown decoration and trailing punctuation', () {
      const input = '  # Title: Likes Tea, and coffee!  ';
      final norm = MarkdownNative.normalizeFingerprint(input);
      expect(norm, isNotNull);
      expect(norm, equals('title: likes tea, and coffee'));
    });
  });

  group('CaduceusNative Phase 2: Crypto & JSON', () {
    test('sha256 computes standard hash', () {
      final input = utf8.encode('hello world');
      final hash = CryptoNative.sha256(Uint8List.fromList(input));
      expect(hash, isNotNull);
      expect(hash!.length, equals(32));

      // Standard SHA-256 for 'hello world' is b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
      final hex = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex, equals('b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9'));
    });

    test('ed25519 generates keypair and signs message', () {
      final seed = Uint8List(32);
      for (var i = 0; i < 32; i++) seed[i] = i;

      final keyPair = CryptoNative.ed25519KeypairFromSeed(seed);
      expect(keyPair, isNotNull);
      expect(keyPair!.publicKey.length, equals(32));
      expect(keyPair.secretKey.length, equals(64));

      final message = Uint8List.fromList(utf8.encode('challenge_payload'));
      final signature = CryptoNative.ed25519Sign(message, keyPair.secretKey);
      expect(signature, isNotNull);
      expect(signature!.length, equals(64));
    });

    test('jsonExtractField extracts fields without parsing full document', () {
      const jsonStr = '{"id":"req-123","method":"chat.send","params":{"content":"hi"}}';
      final method = JsonNative.extractField(jsonStr, 'method');
      expect(method, equals('chat.send'));

      final id = JsonNative.extractField(jsonStr, 'id');
      expect(id, equals('req-123'));
    });

    test('jsonExtractFieldFromBytes extracts from raw byte list', () {
      final jsonBytes = utf8.encode('{"id":"req-999","method":"sessions.list","result":{"ok":true}}');
      final method = JsonNative.extractFieldFromBytes(jsonBytes, 'method');
      expect(method, equals('sessions.list'));

      final id = JsonNative.extractFieldFromBytes(jsonBytes, 'id');
      expect(id, equals('req-999'));
    });
  });

  group('CaduceusNative Phase 3: SIMD Math & Vector/Diff', () {
    test('cosineSimilarity computes exact alignment', () {
      final v1 = [1.0, 0.0, 0.0, 0.0];
      final v2 = [1.0, 0.0, 0.0, 0.0];
      final sim = VectorNative.cosineSimilarity(v1, v2);
      expect(sim, isNotNull);
      expect(sim, closeTo(1.0, 0.001));

      final v3 = [0.0, 1.0, 0.0, 0.0];
      final simOrtho = VectorNative.cosineSimilarity(v1, v3);
      expect(simOrtho, closeTo(0.0, 0.001));
    });

    test('batchCosineSimilarity and topKSimilar SIMD search', () {
      final query = [1.0, 0.0, 0.0, 0.0];
      // 3 vectors of dim 4
      final matrix = [
        0.0, 1.0, 0.0, 0.0, // cand 0 (orthogonal, score 0.0)
        1.0, 0.0, 0.0, 0.0, // cand 1 (identical, score 1.0)
        0.7071, 0.7071, 0.0, 0.0, // cand 2 (45 deg, score ~0.7071)
      ];

      final scores = VectorNative.batchCosineSimilarity(
        query: query,
        flatMatrix: matrix,
        dim: 4,
        count: 3,
      );
      expect(scores, isNotNull);
      expect(scores!.length, equals(3));
      expect(scores[0], closeTo(0.0, 0.01));
      expect(scores[1], closeTo(1.0, 0.01));
      expect(scores[2], closeTo(0.7071, 0.01));

      final topK = VectorNative.topKSimilar(
        query: query,
        flatMatrix: matrix,
        dim: 4,
        count: 3,
        k: 2,
      );
      expect(topK, isNotNull);
      expect(topK!.length, equals(2));
      expect(topK[0].index, equals(1)); // score 1.0
      expect(topK[0].score, closeTo(1.0, 0.01));
      expect(topK[1].index, equals(2)); // score ~0.7071
      expect(topK[1].score, closeTo(0.7071, 0.01));
    });

    test('dotProduct and euclideanDistance work accurately', () {
      final v1 = [1.0, 2.0, 3.0, 4.0];
      final v2 = [2.0, 3.0, 4.0, 5.0];
      final dot = VectorNative.dotProduct(v1, v2);
      // 1*2 + 2*3 + 3*4 + 4*5 = 2 + 6 + 12 + 20 = 40
      expect(dot, closeTo(40.0, 0.001));

      final dist = VectorNative.euclideanDistance(v1, v2);
      // sqrt(1^2 + 1^2 + 1^2 + 1^2) = 2.0
      expect(dist, closeTo(2.0, 0.001));
    });

    test('levenshteinDistance and stringSimilarity', () {
      final dist = VectorNative.levenshteinDistance('kitten', 'sitting');
      expect(dist, equals(3));

      final sim = VectorNative.stringSimilarity('kitten', 'sitting');
      expect(sim, isNotNull);
      expect(sim!, closeTo(1.0 - (3.0 / 7.0), 0.01));
    });
  });
}
