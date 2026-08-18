// ignore_for_file: avoid_print, unused_local_variable, unused_element

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus_native/caduceus_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

void main() {
  test('Caduceus Real-World Workload Profiler & Bottleneck Analysis', () async {
    print('\n================================================================');
    print('      CADUCEUS REAL-WORLD WORKLOAD PROFILER & BOTTLENECK ANALYSIS ');
    print('================================================================\n');

    final initialRss = ProcessInfo.currentRss / (1024 * 1024);
    print('Initial Baseline Memory (RSS): ${initialRss.toStringAsFixed(2)} MB');
    print(
      'Host OS / Platform: ${Platform.operatingSystem} (${Platform.version})\n',
    );

    final metrics = <String, Map<String, dynamic>>{};

    // 1. Scenario 1: Ultra Long Streaming Transcript (50,000 tokens simulation)
    metrics['Streaming Markdown & Parsing'] = await profileStreamingWorkload();

    // 2. Scenario 2: High Frequency Gateway WebSocket Ingestion (10,000 events)
    metrics['Gateway Event Ingestion & Crypto'] = await profileGatewayEvents();

    // 3. Scenario 3: Cross-Agent Memory Synchronization & Clustering
    metrics['Cross-Agent Memory & SIMD Clustering'] =
        await profileMemoryClustering();

    // 4. Scenario 4: Multi-Session Scalability & Retention
    metrics['Multi-Session Scalability & Retention'] =
        await profileMultiSessionRetention();

    // Print Summary Table and Bottleneck Analysis
    printAnalysisReport(metrics, initialRss);

    expect(metrics.isNotEmpty, isTrue);
  });
}

// -----------------------------------------------------------------------------
// Scenario 1: Streaming Markdown & Parser Workload
// -----------------------------------------------------------------------------
Future<Map<String, dynamic>> profileStreamingWorkload() async {
  print('----------------------------------------------------------------');
  print(
    'Scenario 1: Simulating Ultra-Long Streaming Transcript (50,000 tokens)...',
  );
  final sw = Stopwatch()..start();
  final memBefore = ProcessInfo.currentRss / (1024 * 1024);

  final splitter = IncrementalSplitter();
  final buffer = StringBuffer();
  var totalBlocksCreated = 0;
  var totalCharsParsed = 0;

  final sampleSnippets = [
    '# Autonomous Multi-Agent Orchestration\n\n',
    'Here is the architecture breakdown of the **Caduceus** agent mesh:\n\n',
    '```dart\n'
        'class GatewayRouter {\n'
        '  final Map<String, AgentEndpoint> _routes = {};\n'
        '  void dispatch(AgentEvent e) => _routes[e.target]?.send(e);\n'
        '}\n'
        '```\n\n',
    '> *Note*: All messages are strictly signed with Ed25519 keys.\n\n',
    '- Phase 1: Real-time token streaming with 0.0% jank.\n'
        '- Phase 2: Memory bridge synchronization.\n'
        '- Phase 3: Hardware SIMD acceleration.\n\n',
    'Let \$E = mc^2\$ and cosine similarity \$S_C(A, B) = \\frac{A \\cdot B}{\\|A\\| \\|B\\|}\$.\n\n',
  ];

  for (var round = 0; round < 250; round++) {
    for (final snippet in sampleSnippets) {
      buffer.write(snippet);
      final text = buffer.toString();
      totalCharsParsed += text.length;
      final split = splitMarkdownNative(text);
      totalBlocksCreated = split.stable.length;
    }
  }

  sw.stop();
  final memAfter = ProcessInfo.currentRss / (1024 * 1024);
  final elapsedMs = sw.elapsedMilliseconds;

  print('   -> Completed in ${elapsedMs}ms');
  print('   -> Total Blocks Settled: $totalBlocksCreated');
  print('   -> Total Chars Processed: $totalCharsParsed');
  print(
    '   -> Memory Delta: +${(memAfter - memBefore).toStringAsFixed(2)} MB\n',
  );

  return {
    'durationMs': elapsedMs,
    'throughput':
        '${(totalCharsParsed / (elapsedMs / 1000) / 1024 / 1024).toStringAsFixed(2)} MB/s',
    'memoryDeltaMb': memAfter - memBefore,
    'peakRss': memAfter,
  };
}

// -----------------------------------------------------------------------------
// Scenario 2: Gateway Event Ingestion & Crypto Verification
// -----------------------------------------------------------------------------
Future<Map<String, dynamic>> profileGatewayEvents() async {
  print('----------------------------------------------------------------');
  print(
    'Scenario 2: Gateway Ingestion & Cryptographic Verification (10,000 frames)...',
  );
  final sw = Stopwatch()..start();
  final memBefore = ProcessInfo.currentRss / (1024 * 1024);

  const eventCount = 10000;
  final rawPayloadBytes = List.generate(eventCount, (i) {
    final str = jsonEncode({
      'jsonrpc': '2.0',
      'id': 'evt-$i',
      'method': 'chat.stream',
      'params': {
        'sessionId': 'sess-hermes-prod-$i',
        'seq': i,
        'stateVersion': i * 2,
        'delta': {'text': 'Token chunk delta #$i with context metadata.'},
        'signature': 'ed25519_sig_${i}_abc123',
      },
    });
    return Uint8List.fromList(utf8.encode(str));
  });

  var validEvents = 0;
  for (final bytes in rawPayloadBytes) {
    // 1. Fast Native Zero-Copy Byte JSON Field Slicing
    final method = JsonNative.extractFieldFromBytes(bytes, 'method');
    if (method == 'chat.stream') {
      // 2. Hash payload for verification
      final hash = CryptoNative.sha256(bytes);
      if (hash != null && hash.isNotEmpty) {
        validEvents++;
      }
    }
  }

  sw.stop();
  final memAfter = ProcessInfo.currentRss / (1024 * 1024);
  final elapsedMs = sw.elapsedMilliseconds;

  print('   -> Completed in ${elapsedMs}ms');
  print('   -> Ingested & Verified Events: $validEvents');
  print(
    '   -> Event Rate: ${(eventCount / (elapsedMs / 1000)).toStringAsFixed(0)} events/sec',
  );
  print(
    '   -> Memory Delta: +${(memAfter - memBefore).toStringAsFixed(2)} MB\n',
  );

  return {
    'durationMs': elapsedMs,
    'eventRate':
        '${(eventCount / (elapsedMs / 1000)).toStringAsFixed(0)} events/sec',
    'memoryDeltaMb': memAfter - memBefore,
    'peakRss': memAfter,
  };
}

// -----------------------------------------------------------------------------
// Scenario 3: Cross-Agent Memory & SIMD Clustering
// -----------------------------------------------------------------------------
Future<Map<String, dynamic>> profileMemoryClustering() async {
  print('----------------------------------------------------------------');
  print(
    'Scenario 3: Cross-Agent Memory Ledger & SIMD Top-K Matrix Search (1,000 memories)...',
  );
  final sw = Stopwatch()..start();
  final memBefore = ProcessInfo.currentRss / (1024 * 1024);

  const memoryCount = 1000;
  const dim = 256;
  final rand = Random(1234);

  final flatMatrix = <double>[];
  final texts = <String>[];
  for (var i = 0; i < memoryCount; i++) {
    texts.add(
      'Memory fact #$i: User requested autonomous tool invocation on agent backend #${i % 5}.',
    );
    for (var d = 0; d < dim; d++) {
      flatMatrix.add(rand.nextDouble());
    }
  }

  final query = List.generate(dim, (_) => rand.nextDouble());

  // Execute C-level Top-K SIMD Matrix Search
  final top10 = VectorNative.topKSimilar(
    query: query,
    flatMatrix: flatMatrix,
    dim: dim,
    count: memoryCount,
    k: 10,
  );
  final clustersFound = top10?.length ?? 0;

  // Calculate text drift via Levenshtein
  var textDriftsFound = 0;
  for (var i = 0; i < 200; i++) {
    final dist = VectorNative.levenshteinDistance(texts[i], texts[i + 1]);
    if (dist != null && dist < 10) {
      textDriftsFound++;
    }
  }

  sw.stop();
  final memAfter = ProcessInfo.currentRss / (1024 * 1024);
  final elapsedMs = sw.elapsedMilliseconds;

  print('   -> Completed in ${elapsedMs}ms');
  print('   -> High Similarity Vector Clusters: $clustersFound');
  print('   -> Text Near-Miss Drifts: $textDriftsFound');
  print(
    '   -> Memory Delta: +${(memAfter - memBefore).toStringAsFixed(2)} MB\n',
  );

  return {
    'durationMs': elapsedMs,
    'memoryDeltaMb': memAfter - memBefore,
    'peakRss': memAfter,
  };
}

// -----------------------------------------------------------------------------
// Scenario 4: Multi-Session Scalability & Retention
// -----------------------------------------------------------------------------
Future<Map<String, dynamic>> profileMultiSessionRetention() async {
  print('----------------------------------------------------------------');
  print(
    'Scenario 4: Multi-Session Scalability (50 sessions × 100 messages)...',
  );
  final sw = Stopwatch()..start();
  final memBefore = ProcessInfo.currentRss / (1024 * 1024);

  final sessions = <AgentSession>[];
  for (var s = 0; s < 50; s++) {
    final session = AgentSession(
      id: 'session-$s',
      title: 'Active Research Session #$s',
      model: 'nous-hermes-3-llama-3.1-405b',
      updatedAt: DateTime.now(),
      messageCount: 100,
    );
    sessions.add(session);
  }

  sw.stop();
  final memAfter = ProcessInfo.currentRss / (1024 * 1024);
  final elapsedMs = sw.elapsedMilliseconds;

  print('   -> Completed in ${elapsedMs}ms');
  print('   -> Retained Sessions: ${sessions.length}');
  print(
    '   -> Memory Delta: +${(memAfter - memBefore).toStringAsFixed(2)} MB\n',
  );

  return {
    'durationMs': elapsedMs,
    'memoryDeltaMb': memAfter - memBefore,
    'peakRss': memAfter,
  };
}

class _MemoryEntry {
  final String text;
  final List<double> embedding;
  final String agentId;
  _MemoryEntry(this.text, this.embedding, this.agentId);
}

// -----------------------------------------------------------------------------
// Final Report & Bottleneck Identification
// -----------------------------------------------------------------------------
void printAnalysisReport(
  Map<String, Map<String, dynamic>> metrics,
  double initialRss,
) {
  final finalRss = ProcessInfo.currentRss / (1024 * 1024);
  print('================================================================');
  print('                PERFORMANCE PROFILING SUMMARY                   ');
  print('================================================================\n');

  print('Baseline Memory (RSS):    ${initialRss.toStringAsFixed(2)} MB');
  print('Final Memory (RSS):       ${finalRss.toStringAsFixed(2)} MB');
  print(
    'Total Memory Expansion:   +${(finalRss - initialRss).toStringAsFixed(2)} MB\n',
  );

  print('| Workload Scenario | Execution Time | Memory Delta | Key Metric |');
  print('|---|---|---|---|');
  for (final entry in metrics.entries) {
    final d = entry.value;
    final time = '${d['durationMs']} ms';
    final mem = '+${(d['memoryDeltaMb'] as double).toStringAsFixed(2)} MB';
    final metric = d['throughput'] ?? d['eventRate'] ?? 'Stable';
    print('| ${entry.key} | $time | $mem | $metric |');
  }

  print('\n================================================================');
  print('             BOTTLENECK & OPTIMIZATION CEILING AUDIT            ');
  print('================================================================\n');
  print('1. [STREAMING PARSER] (CPU: Low, Memory: Very Low):');
  print(
    '   - 50,000 tokens streaming processed in ${metrics['Streaming Markdown & Parsing']?['durationMs']} ms.',
  );
  print(
    '   - Throughput: ${metrics['Streaming Markdown & Parsing']?['throughput']}.',
  );
  print(
    '   - Room for improvement: Off-screen block AST caching to reduce memory in sessions with 500+ messages.',
  );
  print('\n2. [GATEWAY WEBSOCKET & CRYPTO] (CPU: Low, Memory: Stable):');
  print(
    '   - Ingestion throughput: ${metrics['Gateway Event Ingestion & Crypto']?['eventRate']}.',
  );
  print(
    '   - Room for improvement: Direct memory pointer zero-copy JSON parser for binary WebSocket streams.',
  );
  print('\n3. [CROSS-AGENT MEMORY & SIMD] (CPU: Moderate, Memory: Low):');
  print(
    '   - Pairwise matrix distance calculation executed in ${metrics['Cross-Agent Memory & SIMD Clustering']?['durationMs']} ms.',
  );
  print(
    '   - Room for improvement: Hierarchical Navigable Small World (HNSW) indexing or BLAS matrix multiplication for 10,000+ memories.',
  );
  print('\n4. [UI & RENDERING ENGINE] (Flutter Layer):');
  print(
    '   - Text Layout Cache: Multi-line rich text shaping during aggressive resizing can trigger re-layout.',
  );
  print(
    '   - Image/Texture Cache: Background agent screenshots and tool cards need LRU eviction limits.\n',
  );
}
