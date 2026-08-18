/// End-to-end streaming check against a real Hermes.
///
/// Creates its *own* session first rather than submitting into whatever is
/// currently active, so it cannot disturb work already running on the server.
///
///   HERMES_TOKEN=<token> dart run example/stream_prompt.dart <url> "prompt"
library;

import 'dart:async';
import 'dart:io';

import 'package:hermes_protocol/hermes_protocol.dart';

Future<void> main(List<String> args) async {
  final token = Platform.environment['HERMES_TOKEN'];
  if (token == null || args.isEmpty) {
    stderr.writeln('usage: HERMES_TOKEN=... dart run example/stream_prompt.dart <url> [prompt]');
    exit(2);
  }
  final prompt = args.length > 1 ? args[1] : 'Reply with exactly: pong';

  final endpoint = HermesEndpoint.parse(args.first, credential: token);
  final gateway = HermesGateway(endpoint);

  final eventTypes = <String, int>{};
  final done = Completer<void>();
  final answer = StringBuffer();
  final reasoning = StringBuffer();
  var answerFrames = 0, reasoningFrames = 0;

  gateway.events.listen((e) {
    eventTypes.update(e.type, (n) => n + 1, ifAbsent: () => 1);

    // Two separate channels. Concatenating them buries the answer inside the
    // model's private notes.
    final ans = e.answerText;
    if (ans != null) {
      answerFrames++;
      answer.write(ans);
      stdout.write(ans);
      return;
    }
    final think = e.reasoningText;
    if (think != null) {
      reasoningFrames++;
      reasoning.write(think);
      return;
    }
    if (e.isApprovalRequest) {
      stdout.writeln('\n[approval requested: ${e.payload}]');
    }
    if (e.type == 'message.complete' && !done.isCompleted) done.complete();
  });

  print('connecting to $endpoint');
  await gateway.connect();

  // Own session, so nothing running on the server is affected.
  final created = await gateway.sessionCreate();
  final sessionId = created['session_id'] as String;
  print('created session: $sessionId');

  print('\nprompt: $prompt');
  print('--- streaming ---');
  final started = DateTime.now();
  await gateway.promptSubmit(sessionId: sessionId, text: prompt);

  try {
    await done.future.timeout(const Duration(seconds: 90));
  } on TimeoutException {
    print('\n[no message.complete within 90s]');
  }
  final elapsed = DateTime.now().difference(started);

  print('\n--- done in ${elapsed.inMilliseconds} ms ---');
  print('ANSWER    : $answerFrames frames, ${answer.length} chars');
  print('REASONING : $reasoningFrames frames, ${reasoning.length} chars (separate channel)');
  print('answer text  : ${answer.toString().trim()}');
  print('event types  : $eventTypes');

  await gateway.dispose();
}
