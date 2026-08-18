import 'dart:convert';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'native_bindings.dart';

class VectorNative {
  /// Computes Cosine Similarity between two float lists using SIMD acceleration.
  /// Returns null if native engine is unavailable.
  static double? cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return null;
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final dim = a.length;
    final aPtr = malloc<ffi.Float>(dim);
    final bPtr = malloc<ffi.Float>(dim);

    for (var i = 0; i < dim; i++) {
      aPtr[i] = a[i];
      bPtr[i] = b[i];
    }

    try {
      return bindings.cosineSimilarity(aPtr, bPtr, dim);
    } finally {
      malloc.free(aPtr);
      malloc.free(bPtr);
    }
  }

  /// Computes Dot Product between two float lists.
  static double? dotProduct(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return null;
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final dim = a.length;
    final aPtr = malloc<ffi.Float>(dim);
    final bPtr = malloc<ffi.Float>(dim);

    for (var i = 0; i < dim; i++) {
      aPtr[i] = a[i];
      bPtr[i] = b[i];
    }

    try {
      return bindings.dotProduct(aPtr, bPtr, dim);
    } finally {
      malloc.free(aPtr);
      malloc.free(bPtr);
    }
  }

  /// Computes Euclidean (L2) distance between two float lists.
  static double? euclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return null;
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final dim = a.length;
    final aPtr = malloc<ffi.Float>(dim);
    final bPtr = malloc<ffi.Float>(dim);

    for (var i = 0; i < dim; i++) {
      aPtr[i] = a[i];
      bPtr[i] = b[i];
    }

    try {
      return bindings.euclideanDistance(aPtr, bPtr, dim);
    } finally {
      malloc.free(aPtr);
      malloc.free(bPtr);
    }
  }

  /// Computes Levenshtein edit distance between two strings.
  static int? levenshteinDistance(String s1, String s2) {
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final b1 = utf8.encode(s1);
    final p1 = malloc<ffi.Uint8>(b1.length + 1);
    for (var i = 0; i < b1.length; i++) {
      p1[i] = b1[i];
    }
    p1[b1.length] = 0;

    final b2 = utf8.encode(s2);
    final p2 = malloc<ffi.Uint8>(b2.length + 1);
    for (var i = 0; i < b2.length; i++) {
      p2[i] = b2[i];
    }
    p2[b2.length] = 0;

    try {
      return bindings.levenshteinDistance(
        p1.cast<Utf8>(),
        b1.length,
        p2.cast<Utf8>(),
        b2.length,
      );
    } finally {
      malloc.free(p1);
      malloc.free(p2);
    }
  }

  /// Computes string similarity ratio in [0.0, 1.0].
  static double? stringSimilarity(String s1, String s2) {
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final b1 = utf8.encode(s1);
    final p1 = malloc<ffi.Uint8>(b1.length + 1);
    for (var i = 0; i < b1.length; i++) {
      p1[i] = b1[i];
    }
    p1[b1.length] = 0;

    final b2 = utf8.encode(s2);
    final p2 = malloc<ffi.Uint8>(b2.length + 1);
    for (var i = 0; i < b2.length; i++) {
      p2[i] = b2[i];
    }
    p2[b2.length] = 0;

    try {
      return bindings.stringSimilarity(
        p1.cast<Utf8>(),
        b1.length,
        p2.cast<Utf8>(),
        b2.length,
      );
    } finally {
      malloc.free(p1);
      malloc.free(p2);
    }
  }

  /// Computes batch cosine similarities between one query vector and N candidate vectors (flattened matrix).
  static List<double>? batchCosineSimilarity({
    required List<double> query,
    required List<double> flatMatrix,
    required int dim,
    required int count,
  }) {
    if (query.length != dim || flatMatrix.length != dim * count || count <= 0) return null;
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final qPtr = malloc<ffi.Float>(dim);
    for (var i = 0; i < dim; i++) {
      qPtr[i] = query[i];
    }

    final mPtr = malloc<ffi.Float>(flatMatrix.length);
    for (var i = 0; i < flatMatrix.length; i++) {
      mPtr[i] = flatMatrix[i];
    }

    final outPtr = malloc<ffi.Float>(count);

    try {
      bindings.batchCosineSimilarity(qPtr, mPtr, dim, count, outPtr);
      return List<double>.generate(count, (i) => outPtr[i]);
    } finally {
      malloc.free(qPtr);
      malloc.free(mPtr);
      malloc.free(outPtr);
    }
  }

  /// Finds the Top-K most similar vectors to query in flatMatrix with SIMD acceleration.
  static List<VectorMatch>? topKSimilar({
    required List<double> query,
    required List<double> flatMatrix,
    required int dim,
    required int count,
    required int k,
  }) {
    if (query.length != dim || flatMatrix.length != dim * count || count <= 0 || k <= 0) return null;
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final qPtr = malloc<ffi.Float>(dim);
    for (var i = 0; i < dim; i++) {
      qPtr[i] = query[i];
    }

    final mPtr = malloc<ffi.Float>(flatMatrix.length);
    for (var i = 0; i < flatMatrix.length; i++) {
      mPtr[i] = flatMatrix[i];
    }

    final targetK = k < count ? k : count;
    final outMatches = malloc<CaduceusVectorMatchNative>(targetK);

    try {
      final actualWritten = bindings.topKSimilarVectors(qPtr, mPtr, dim, count, targetK, outMatches);
      return List<VectorMatch>.generate(actualWritten, (i) {
        return VectorMatch(index: outMatches[i].index, score: outMatches[i].score);
      });
    } finally {
      malloc.free(qPtr);
      malloc.free(mPtr);
      malloc.free(outMatches);
    }
  }
}

class VectorMatch {
  final int index;
  final double score;
  const VectorMatch({required this.index, required this.score});

  @override
  String toString() => 'VectorMatch(index: $index, score: ${score.toStringAsFixed(4)})';
}
