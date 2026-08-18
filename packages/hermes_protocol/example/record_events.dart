/// Records every frame a real agent turn produces, with full payloads.
///
/// Tool and approval event shapes have never been observed — the two test
/// prompts so far used no tools. Everything about how a tool call or an
/// approval gate looks on the wire is currently a guess, and guesses about
/// payload shapes have been wrong every time this session.
///
///   HERMES_TOKEN=... dart run example/record_events.dart <url> "prompt"
///
/// Writes newline-delimited JSON to stdout; `> events.jsonl` to keep it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes_protocol/hermes_protocol.dart';

Future<void> main(List<String> args) async {
  final token = Platform.environment['HERMES_TOKEN'];
  if (token == null || args.isEmpty) {
    stderr.writeln('usage: HERMES_TOKEN=... dart run example/record_events.dart <url> [prompt]');
    exit(2);
  }
  final prompt = args.length > 1
      ? args[1]
      : 'Run `ls ~` and tell me how many entries there are. Do not modify anything.';

  final gateway =
      HermesGateway(HermesEndpoint.parse(args.first, credential: token));

  final counts = <String, int>{};
  final firstOfType = <String, Map<String, dynamic>>{};
  final ordered = <String>[];
  final done = Completer<void>();

  // Raw notifications, so nothing is lost to the event unwrapping.
  gateway.notifications.listen((n) {
    final params = n.params;
    final type = params['type']?.toString() ?? n.method;
    counts.update(type, (v) => v + 1, ifAbsent: () => 1);
    if (ordered.isEmpty || ordered.last != type) ordered.add(type);

    // Keep the first instance of each type at full fidelity. Deltas repeat
    // hundreds of times and one is enough.
    firstOfType.putIfAbsent(type, () => Map<String, dynamic>.from(params));

    if (type == 'message.complete' && !done.isCompleted) done.complete();
  });

  stderr.writeln('connecting…');
  await gateway.connect();
  final created = await gateway.sessionCreate();
  final sessionId = created['session_id'] as String;
  stderr.writeln('session $sessionId');
  stderr.writeln('prompt: $prompt');

  await gateway.promptSubmit(sessionId: sessionId, text: prompt);

  try {
    await done.future.timeout(const Duration(seconds: 180));
  } on TimeoutException {
    stderr.writeln('(no message.complete within 180s — recording what arrived)');
  }
  // Let any trailing frames land.
  await Future<void>.delayed(const Duration(seconds: 2));

  // Dump everything to disk so payload questions can be answered offline
  // instead of costing another live agent turn per question.
  final dump = File('events_dump.json');
  await dump.writeAsString(
      const JsonEncoder.withIndent('  ').convert(firstOfType));
  stderr.writeln('full payloads -> ${dump.path}');

  final encoder = JsonEncoder.withIndent('  ');
  print('=== EVENT TYPES (in first-seen order) ===');
  for (final t in ordered) {
    print('  ${t.padRight(28)} x${counts[t]}');
  }
  print('\n=== FIRST INSTANCE OF EACH TYPE ===');
  for (final entry in firstOfType.entries) {
    // Deltas are noise, and gateway.ready is a large static theme blob.
    if (entry.key.endsWith('.delta')) continue;
    if (entry.key == 'gateway.ready' || entry.key == 'session.info') continue;
    print('\n--- ${entry.key}');
    print(encoder.convert(entry.value));
  }

  await gateway.dispose();
}
