/// Exercises a real approval gate, then denies it.
///
/// `smart` approval mode auto-approves reads, so a gate only fires for a write.
/// This asks for one and then **denies** — the payload and the
/// `approval.respond` round trip are observed, and nothing is written on the
/// server.
///
/// Responding matters: a pending approval blocks the agent thread until it is
/// resolved, so a probe that observes and walks away would leave a wedged turn.
///
///   HERMES_TOKEN=... dart run example/approval_probe.dart <url>
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes_protocol/hermes_protocol.dart';

Future<void> main(List<String> args) async {
  final token = Platform.environment['HERMES_TOKEN'];
  if (token == null || args.isEmpty) {
    stderr.writeln('usage: HERMES_TOKEN=... dart run example/approval_probe.dart <url>');
    exit(2);
  }

  final gateway =
      HermesGateway(HermesEndpoint.parse(args.first, credential: token));

  final seen = <String, int>{};
  ApprovalRequest? gate;
  Map<String, dynamic>? rawPayload;
  final gateFired = Completer<void>();
  final finished = Completer<void>();
  final answer = StringBuffer();

  gateway.events.listen((e) {
    seen.update(e.type, (v) => v + 1, ifAbsent: () => 1);

    if (e.isApprovalRequest && !gateFired.isCompleted) {
      rawPayload = e.payload;
      gate = ApprovalRequest.fromEvent(e.sessionId, e.payload);
      gateFired.complete();
    }
    final a = e.answerText;
    if (a != null) answer.write(a);
    if (e.type == 'message.complete' && !finished.isCompleted) {
      finished.complete();
    }
  });

  await gateway.connect();
  final sessionId = (await gateway.sessionCreate())['session_id'] as String;
  stderr.writeln('session $sessionId');

  // A write, so `smart` mode has to ask. It is denied below, so it never runs.
  const prompt = 'Create an empty file at /tmp/caduceus_approval_probe using '
      'the terminal tool.';
  stderr.writeln('prompt: $prompt\n');
  await gateway.promptSubmit(sessionId: sessionId, text: prompt);

  try {
    await gateFired.future.timeout(const Duration(seconds: 120));
  } on TimeoutException {
    print('NO APPROVAL GATE FIRED within 120s.');
    print('events seen: $seen');
    await gateway.dispose();
    return;
  }

  print('=== approval.request RAW PAYLOAD ===');
  print(const JsonEncoder.withIndent('  ').convert(rawPayload));

  final g = gate!;
  print('\n=== PARSED BY ApprovalRequest ===');
  print('  tool        : ${g.tool}');
  print('  command     : ${g.command}');
  print('  choices     : ${g.choices}');
  print('  smartDenied : ${g.smartDenied}');
  print('  labels      : ${g.choices.map(ApprovalRequest.labelFor).toList()}');

  print('\n=== responding: deny (nothing is written) ===');
  final result = await gateway.approvalRespond(
    sessionId: sessionId,
    choice: 'deny',
    reason: 'Caduceus protocol probe — verifying the approval round trip.',
  );
  print('approval.respond -> $result');

  try {
    await finished.future.timeout(const Duration(seconds: 90));
  } on TimeoutException {
    print('\n(agent did not finish within 90s after the denial)');
  }

  print('\n=== agent reply after denial ===');
  print(answer.toString().trim());
  print('\nevents seen: $seen');

  await gateway.dispose();
}
