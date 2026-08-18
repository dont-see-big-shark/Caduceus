import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'native_loader.dart';

final class CaduceusBlockSpanNative extends ffi.Struct {
  @ffi.Int32()
  external int startOffset;

  @ffi.Int32()
  external int endOffset;

  @ffi.Int32()
  external int isFence;
}

final class CaduceusVectorMatchNative extends ffi.Struct {
  @ffi.Int32()
  external int index;

  @ffi.Float()
  external double score;
}

// C function type definitions
typedef _SplitBlocksC = ffi.Int32 Function(
  ffi.Pointer<Utf8> text,
  ffi.Int32 textLen,
  ffi.Pointer<CaduceusBlockSpanNative> outSpans,
  ffi.Int32 maxSpans,
  ffi.Pointer<ffi.Int32> outTailStart,
);
typedef _SplitBlocksDart = int Function(
  ffi.Pointer<Utf8> text,
  int textLen,
  ffi.Pointer<CaduceusBlockSpanNative> outSpans,
  int maxSpans,
  ffi.Pointer<ffi.Int32> outTailStart,
);

typedef _NormalizeFingerprintC = ffi.Int32 Function(
  ffi.Pointer<Utf8> input,
  ffi.Int32 inputLen,
  ffi.Pointer<Utf8> outBuf,
  ffi.Int32 outCapacity,
);
typedef _NormalizeFingerprintDart = int Function(
  ffi.Pointer<Utf8> input,
  int inputLen,
  ffi.Pointer<Utf8> outBuf,
  int outCapacity,
);

typedef _Sha256C = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> data,
  ffi.Size len,
  ffi.Pointer<ffi.Uint8> outHash,
);
typedef _Sha256Dart = void Function(
  ffi.Pointer<ffi.Uint8> data,
  int len,
  ffi.Pointer<ffi.Uint8> outHash,
);

typedef _Ed25519KeypairC = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> seed,
  ffi.Pointer<ffi.Uint8> outPublicKey,
  ffi.Pointer<ffi.Uint8> outSecretKey,
);
typedef _Ed25519KeypairDart = void Function(
  ffi.Pointer<ffi.Uint8> seed,
  ffi.Pointer<ffi.Uint8> outPublicKey,
  ffi.Pointer<ffi.Uint8> outSecretKey,
);

typedef _Ed25519SignC = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> message,
  ffi.Size messageLen,
  ffi.Pointer<ffi.Uint8> secretKey,
  ffi.Pointer<ffi.Uint8> outSignature,
);
typedef _Ed25519SignDart = void Function(
  ffi.Pointer<ffi.Uint8> message,
  int messageLen,
  ffi.Pointer<ffi.Uint8> secretKey,
  ffi.Pointer<ffi.Uint8> outSignature,
);

typedef _JsonExtractStringC = ffi.Int32 Function(
  ffi.Pointer<Utf8> jsonStr,
  ffi.Int32 jsonLen,
  ffi.Pointer<Utf8> fieldName,
  ffi.Pointer<ffi.Int32> outValStart,
  ffi.Pointer<ffi.Int32> outValEnd,
);
typedef _JsonExtractStringDart = int Function(
  ffi.Pointer<Utf8> jsonStr,
  int jsonLen,
  ffi.Pointer<Utf8> fieldName,
  ffi.Pointer<ffi.Int32> outValStart,
  ffi.Pointer<ffi.Int32> outValEnd,
);

typedef _JsonExtractFromBytesC = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> bytes,
  ffi.Int32 len,
  ffi.Pointer<Utf8> fieldName,
  ffi.Pointer<ffi.Int32> outValStart,
  ffi.Pointer<ffi.Int32> outValEnd,
);
typedef _JsonExtractFromBytesDart = int Function(
  ffi.Pointer<ffi.Uint8> bytes,
  int len,
  ffi.Pointer<Utf8> fieldName,
  ffi.Pointer<ffi.Int32> outValStart,
  ffi.Pointer<ffi.Int32> outValEnd,
);

typedef _VectorMathC = ffi.Float Function(
  ffi.Pointer<ffi.Float> a,
  ffi.Pointer<ffi.Float> b,
  ffi.Int32 dim,
);
typedef _VectorMathDart = double Function(
  ffi.Pointer<ffi.Float> a,
  ffi.Pointer<ffi.Float> b,
  int dim,
);

typedef _BatchCosineSimilarityC = ffi.Void Function(
  ffi.Pointer<ffi.Float> query,
  ffi.Pointer<ffi.Float> matrix,
  ffi.Int32 dim,
  ffi.Int32 count,
  ffi.Pointer<ffi.Float> outScores,
);
typedef _BatchCosineSimilarityDart = void Function(
  ffi.Pointer<ffi.Float> query,
  ffi.Pointer<ffi.Float> matrix,
  int dim,
  int count,
  ffi.Pointer<ffi.Float> outScores,
);

typedef _TopKSimilarVectorsC = ffi.Int32 Function(
  ffi.Pointer<ffi.Float> query,
  ffi.Pointer<ffi.Float> matrix,
  ffi.Int32 dim,
  ffi.Int32 count,
  ffi.Int32 k,
  ffi.Pointer<CaduceusVectorMatchNative> outMatches,
);
typedef _TopKSimilarVectorsDart = int Function(
  ffi.Pointer<ffi.Float> query,
  ffi.Pointer<ffi.Float> matrix,
  int dim,
  int count,
  int k,
  ffi.Pointer<CaduceusVectorMatchNative> outMatches,
);

typedef _LevenshteinC = ffi.Int32 Function(
  ffi.Pointer<Utf8> s1,
  ffi.Int32 len1,
  ffi.Pointer<Utf8> s2,
  ffi.Int32 len2,
);
typedef _LevenshteinDart = int Function(
  ffi.Pointer<Utf8> s1,
  int len1,
  ffi.Pointer<Utf8> s2,
  int len2,
);

typedef _StringSimilarityC = ffi.Float Function(
  ffi.Pointer<Utf8> s1,
  ffi.Int32 len1,
  ffi.Pointer<Utf8> s2,
  ffi.Int32 len2,
);
typedef _StringSimilarityDart = double Function(
  ffi.Pointer<Utf8> s1,
  int len1,
  ffi.Pointer<Utf8> s2,
  int len2,
);

/// Bound C functions
class CaduceusNativeBindings {
  CaduceusNativeBindings._();

  static final CaduceusNativeBindings? instance = _init();

  static CaduceusNativeBindings? _init() {
    final lib = CaduceusNativeLoader.library;
    if (lib == null) return null;

    try {
      final bindings = CaduceusNativeBindings._();
      bindings._splitBlocks = lib.lookupFunction<_SplitBlocksC, _SplitBlocksDart>(
        'caduceus_markdown_split_blocks',
      );
      bindings._normalizeFingerprint = lib.lookupFunction<_NormalizeFingerprintC, _NormalizeFingerprintDart>(
        'caduceus_normalize_fingerprint',
      );
      bindings._sha256 = lib.lookupFunction<_Sha256C, _Sha256Dart>('caduceus_sha256');
      bindings._ed25519Keypair = lib.lookupFunction<_Ed25519KeypairC, _Ed25519KeypairDart>(
        'caduceus_ed25519_keypair_from_seed',
      );
      bindings._ed25519Sign = lib.lookupFunction<_Ed25519SignC, _Ed25519SignDart>(
        'caduceus_ed25519_sign',
      );
      bindings._jsonExtractString = lib.lookupFunction<_JsonExtractStringC, _JsonExtractStringDart>(
        'caduceus_json_extract_string_field',
      );
      bindings._jsonExtractFromBytes = lib.lookupFunction<_JsonExtractFromBytesC, _JsonExtractFromBytesDart>(
        'caduceus_json_extract_from_bytes',
      );
      bindings._cosineSimilarity = lib.lookupFunction<_VectorMathC, _VectorMathDart>(
        'caduceus_cosine_similarity',
      );
      bindings._batchCosineSimilarity = lib.lookupFunction<_BatchCosineSimilarityC, _BatchCosineSimilarityDart>(
        'caduceus_batch_cosine_similarity',
      );
      bindings._topKSimilarVectors = lib.lookupFunction<_TopKSimilarVectorsC, _TopKSimilarVectorsDart>(
        'caduceus_top_k_similar_vectors',
      );
      bindings._dotProduct = lib.lookupFunction<_VectorMathC, _VectorMathDart>(
        'caduceus_dot_product',
      );
      bindings._euclideanDistance = lib.lookupFunction<_VectorMathC, _VectorMathDart>(
        'caduceus_euclidean_distance',
      );
      bindings._levenshteinDistance = lib.lookupFunction<_LevenshteinC, _LevenshteinDart>(
        'caduceus_levenshtein_distance',
      );
      bindings._stringSimilarity = lib.lookupFunction<_StringSimilarityC, _StringSimilarityDart>(
        'caduceus_string_similarity',
      );
      return bindings;
    } catch (_) {
      return null;
    }
  }

  late final _SplitBlocksDart _splitBlocks;
  late final _NormalizeFingerprintDart _normalizeFingerprint;
  late final _Sha256Dart _sha256;
  late final _Ed25519KeypairDart _ed25519Keypair;
  late final _Ed25519SignDart _ed25519Sign;
  late final _JsonExtractStringDart _jsonExtractString;
  late final _JsonExtractFromBytesDart _jsonExtractFromBytes;
  late final _VectorMathDart _cosineSimilarity;
  late final _BatchCosineSimilarityDart _batchCosineSimilarity;
  late final _TopKSimilarVectorsDart _topKSimilarVectors;
  late final _VectorMathDart _dotProduct;
  late final _VectorMathDart _euclideanDistance;
  late final _LevenshteinDart _levenshteinDistance;
  late final _StringSimilarityDart _stringSimilarity;

  _SplitBlocksDart get splitBlocks => _splitBlocks;
  _NormalizeFingerprintDart get normalizeFingerprint => _normalizeFingerprint;
  _Sha256Dart get sha256 => _sha256;
  _Ed25519KeypairDart get ed25519Keypair => _ed25519Keypair;
  _Ed25519SignDart get ed25519Sign => _ed25519Sign;
  _JsonExtractStringDart get jsonExtractString => _jsonExtractString;
  _JsonExtractFromBytesDart get jsonExtractFromBytes => _jsonExtractFromBytes;
  _VectorMathDart get cosineSimilarity => _cosineSimilarity;
  _BatchCosineSimilarityDart get batchCosineSimilarity => _batchCosineSimilarity;
  _TopKSimilarVectorsDart get topKSimilarVectors => _topKSimilarVectors;
  _VectorMathDart get dotProduct => _dotProduct;
  _VectorMathDart get euclideanDistance => _euclideanDistance;
  _LevenshteinDart get levenshteinDistance => _levenshteinDistance;
  _StringSimilarityDart get stringSimilarity => _stringSimilarity;
}
