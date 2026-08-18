import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:caduceus_native/caduceus_native.dart';
import 'package:crypto/crypto.dart' as crypto;

void main() {
  print('================================================================');
  print('          CADUCEUS NATIVE C vs PURE DART BENCHMARKS             ');
  print('================================================================\n');

  if (!CaduceusNativeLoader.isAvailable) {
    print('ERROR: Native library not loaded!');
    return;
  }

  benchSha256();
  benchJsonExtraction();
  benchVectorCosineSimilarity();
  benchLevenshteinDistance();
  benchMarkdownFingerprint();
}

// -----------------------------------------------------------------------------
// 1. SHA-256 Hashing Benchmark
// -----------------------------------------------------------------------------
void benchSha256() {
  const iterations = 50000;
  final payload = utf8.encode('OpenClaw_Device_Auth_Payload_Challenge_Nonce_Token_2026_xYz1234567890');
  final uint8Payload = Uint8List.fromList(payload);

  // Warmup
  for (var i = 0; i < 1000; i++) {
    crypto.sha256.convert(payload);
    CryptoNative.sha256(uint8Payload);
  }

  // Pure Dart
  final swDart = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final _ = crypto.sha256.convert(payload);
  }
  swDart.stop();

  // Native C
  final swNative = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final _ = CryptoNative.sha256(uint8Payload);
  }
  swNative.stop();

  final dartUs = swDart.elapsedMicroseconds / iterations;
  final nativeUs = swNative.elapsedMicroseconds / iterations;
  final speedup = dartUs / nativeUs;

  print('1. SHA-256 Hashing ($iterations ops, 70B payload):');
  print('   - Pure Dart (package:crypto): ${dartUs.toStringAsFixed(2)} µs/op (${(1000000 / dartUs).toStringAsFixed(0)} ops/sec)');
  print('   - Native C Engine:             ${nativeUs.toStringAsFixed(2)} µs/op (${(1000000 / nativeUs).toStringAsFixed(0)} ops/sec)');
  print('   => Speedup: ${speedup.toStringAsFixed(1)}x faster\n');
}

// -----------------------------------------------------------------------------
// 2. JSON Key Extraction Benchmark
// -----------------------------------------------------------------------------
void benchJsonExtraction() {
  const iterations = 30000;
  const jsonStr = '''
  {
    "jsonrpc": "2.0",
    "id": "req-998822",
    "method": "sessions.create",
    "params": {
      "sessionKey": "sess_apple_m3_2026_caduceus_mas",
      "model": "nous-hermes-3-llama-3.1-405b",
      "scopes": ["read", "write", "tools", "subagents"],
      "metadata": {"source": "mobile_client", "platform": "macos"}
    }
  }
  ''';

  // Warmup
  for (var i = 0; i < 500; i++) {
    final _ = (jsonDecode(jsonStr) as Map)['method'];
    JsonNative.extractField(jsonStr, 'method');
  }

  // Pure Dart jsonDecode
  final swDart = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final _ = decoded['method'] as String?;
  }
  swDart.stop();

  // Native C In-Situ Field Scanner
  final swNative = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final _ = JsonNative.extractField(jsonStr, 'method');
  }
  swNative.stop();

  final dartUs = swDart.elapsedMicroseconds / iterations;
  final nativeUs = swNative.elapsedMicroseconds / iterations;
  final speedup = dartUs / nativeUs;

  print('2. JSON Field Extraction ($iterations ops, 300B JSON frame):');
  print('   - Pure Dart (dart:convert jsonDecode): ${dartUs.toStringAsFixed(2)} µs/op (${(1000000 / dartUs).toStringAsFixed(0)} ops/sec)');
  print('   - Native C In-situ Extractor:          ${nativeUs.toStringAsFixed(2)} µs/op (${(1000000 / nativeUs).toStringAsFixed(0)} ops/sec)');
  print('   => Speedup: ${speedup.toStringAsFixed(1)}x faster (Zero heap Map/List GC allocation)\n');
}

// -----------------------------------------------------------------------------
// 3. High-Dim Vector Cosine Similarity (1536-dim Embedding)
// -----------------------------------------------------------------------------
void benchVectorCosineSimilarity() {
  const dim = 1536;
  const iterations = 20000;
  final rand = Random(42);
  final v1 = List.generate(dim, (_) => rand.nextDouble());
  final v2 = List.generate(dim, (_) => rand.nextDouble());

  double dartCosine(List<double> a, List<double> b) {
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return dot / (sqrt(na) * sqrt(nb));
  }

  // Warmup
  for (var i = 0; i < 500; i++) {
    dartCosine(v1, v2);
    VectorNative.cosineSimilarity(v1, v2);
  }

  // Pure Dart Loop
  final swDart = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final _ = dartCosine(v1, v2);
  }
  swDart.stop();

  // Native C SIMD (ARM NEON)
  final swNative = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final _ = VectorNative.cosineSimilarity(v1, v2);
  }
  swNative.stop();

  final dartUs = swDart.elapsedMicroseconds / iterations;
  final nativeUs = swNative.elapsedMicroseconds / iterations;
  final speedup = dartUs / nativeUs;

  print('3. Vector Cosine Similarity ($iterations ops, 1536-dim embedding vector):');
  print('   - Pure Dart scalar loop:     ${dartUs.toStringAsFixed(2)} µs/op (${(1000000 / dartUs).toStringAsFixed(0)} ops/sec)');
  print('   - Native C (ARM NEON SIMD):   ${nativeUs.toStringAsFixed(2)} µs/op (${(1000000 / nativeUs).toStringAsFixed(0)} ops/sec)');
  print('   => Speedup: ${speedup.toStringAsFixed(1)}x faster\n');
}

// -----------------------------------------------------------------------------
// 4. Levenshtein String Edit Distance
// -----------------------------------------------------------------------------
void benchLevenshteinDistance() {
  const iterations = 5000;
  const strA = 'Autonomous multi-agent system coordinating memory bridge synchronization across Hermes and OpenClaw gateways.';
  const strB = 'Autonomous multi-agent framework managing memory ledger drift detection across Hermes and OpenClaw platforms.';

  int dartLevenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final row = List<int>.generate(s1.length + 1, (i) => i);
    for (var j = 1; j <= s2.length; j++) {
      var prevDiag = row[0];
      row[0] = j;
      for (var i = 1; i <= s1.length; i++) {
        final temp = row[i];
        final cost = (s1.codeUnitAt(i - 1) == s2.codeUnitAt(j - 1)) ? 0 : 1;
        final res = min(row[i - 1] + 1, min(row[i] + 1, prevDiag + cost));
        row[i] = res;
        prevDiag = temp;
      }
    }
    return row[s1.length];
  }

  // Warmup
  for (var i = 0; i < 200; i++) {
    dartLevenshtein(strA, strB);
    VectorNative.levenshteinDistance(strA, strB);
  }

  // Pure Dart
  final swDart = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final _ = dartLevenshtein(strA, strB);
  }
  swDart.stop();

  // Native C
  final swNative = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final _ = VectorNative.levenshteinDistance(strA, strB);
  }
  swNative.stop();

  final dartUs = swDart.elapsedMicroseconds / iterations;
  final nativeUs = swNative.elapsedMicroseconds / iterations;
  final speedup = dartUs / nativeUs;

  print('4. Levenshtein Text Edit Distance ($iterations ops, ~110 chars text diff):');
  print('   - Pure Dart dynamic programming: ${dartUs.toStringAsFixed(2)} µs/op (${(1000000 / dartUs).toStringAsFixed(0)} ops/sec)');
  print('   - Native C memory row buffer:    ${nativeUs.toStringAsFixed(2)} µs/op (${(1000000 / nativeUs).toStringAsFixed(0)} ops/sec)');
  print('   => Speedup: ${speedup.toStringAsFixed(1)}x faster\n');
}

// -----------------------------------------------------------------------------
// 5. Markdown Text Normalization & Fingerprinting
// -----------------------------------------------------------------------------
void benchMarkdownFingerprint() {
  const iterations = 30000;
  const rawText = '  ### *Preference*: User likes **TypeScript**, *Dart*, & C++ for high-performance computing!? \n > Note: Always avoid quadratic string parsing.\n';

  String dartNormalize(String text) {
    var normalised = text.toLowerCase();
    normalised = normalised
        .replaceAll(RegExp(r'^[\s>]*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'[*_`]'), '');
    normalised = normalised.replaceAll(RegExp(r'\s+'), ' ').trim();
    normalised = normalised.replaceAll(RegExp(r'[.,;:!?、。，；：！？]+$'), '');
    return normalised;
  }

  // Warmup
  for (var i = 0; i < 500; i++) {
    dartNormalize(rawText);
    MarkdownNative.normalizeFingerprint(rawText);
  }

  // Pure Dart Regex
  final swDart = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final _ = dartNormalize(rawText);
  }
  swDart.stop();

  // Native C Single-Pass Scanner
  final swNative = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final _ = MarkdownNative.normalizeFingerprint(rawText);
  }
  swNative.stop();

  final dartUs = swDart.elapsedMicroseconds / iterations;
  final nativeUs = swNative.elapsedMicroseconds / iterations;
  final speedup = dartUs / nativeUs;

  print('5. Markdown Fingerprint Normalization ($iterations ops, multi-line prose):');
  print('   - Pure Dart multi-regex replaceAll: ${dartUs.toStringAsFixed(2)} µs/op (${(1000000 / dartUs).toStringAsFixed(0)} ops/sec)');
  print('   - Native C single-pass char scanner: ${nativeUs.toStringAsFixed(2)} µs/op (${(1000000 / nativeUs).toStringAsFixed(0)} ops/sec)');
  print('   => Speedup: ${speedup.toStringAsFixed(1)}x faster (Zero regex engine overhead)\n');
}
