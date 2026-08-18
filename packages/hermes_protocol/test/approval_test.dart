/// Approval parsing, checked against the server's own construction logic.
///
/// A live gate has not been observed: the test server runs `smart` mode, which
/// auto-approved both a read (`ls ~`) and a write (creating an empty file in
/// /tmp). Forcing a gate needs either a genuinely dangerous command or a global
/// `approval_mode` change on a production server — neither is acceptable for a
/// test.
///
/// So these payloads are transcribed from `_emit_approval_request` in
/// `tui_gateway/server.py`, which builds them. That is weaker than observing
/// one, and is labelled as such. The one thing it does establish firmly is the
/// set of valid choices — the bug this file exists to prevent.
library;

import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:test/test.dart';

/// Mirrors the branch in `_emit_approval_request` that fills in `choices`.
Map<String, dynamic> payload({
  String command = 'rm -rf /tmp/x',
  bool? allowPermanent,
  bool smartDenied = false,
}) =>
    {
      'command': command,
      'tool': 'terminal',
      if (smartDenied) 'smart_denied': true,
      if (allowPermanent != null) 'allow_permanent': allowPermanent,
      'choices': smartDenied
          ? ['once', 'deny']
          : allowPermanent == false
              ? ['once', 'session', 'deny']
              : allowPermanent == true
                  ? ['once', 'session', 'always', 'deny']
                  : null,
    }..removeWhere((_, v) => v == null);

void main() {
  test('"allow" is not a valid choice', () {
    // The bug this guards. `approvalRespond` previously sent choice: 'allow',
    // and `resolve_gateway_approval` stores the string verbatim without
    // validating — so it would have silently failed to approve while the UI
    // showed success.
    final request = ApprovalRequest.fromEvent('s-1', payload(allowPermanent: true));
    expect(request.choices, isNot(contains('allow')));
    expect(request.choices, containsAll(['once', 'session', 'always', 'deny']));
  });

  test('choices narrow when permanent approval is not offered', () {
    final request =
        ApprovalRequest.fromEvent('s-1', payload(allowPermanent: false));
    expect(request.choices, ['once', 'session', 'deny']);
    expect(request.choices, isNot(contains('always')));
  });

  test('a smart denial offers only override or deny', () {
    final request = ApprovalRequest.fromEvent('s-1', payload(smartDenied: true));
    expect(request.choices, ['once', 'deny']);
    expect(request.smartDenied, isTrue);
  });

  test('missing choices falls back to the safest pair', () {
    final request = ApprovalRequest.fromEvent('s-1', {'command': 'ls'});
    expect(request.choices, ['once', 'deny']);
  });

  test('command and tool are surfaced for display', () {
    final request = ApprovalRequest.fromEvent(
        's-9', payload(command: 'curl https://example.com', allowPermanent: true));
    expect(request.command, 'curl https://example.com');
    expect(request.tool, 'terminal');
    expect(request.sessionId, 's-9');
  });

  test('every choice has a human label and exactly one is a denial', () {
    final request = ApprovalRequest.fromEvent('s-1', payload(allowPermanent: true));
    for (final c in request.choices) {
      expect(ApprovalRequest.labelFor(c), isNotEmpty);
      expect(ApprovalRequest.labelFor(c), isNot(c),
          reason: '$c should map to a human label');
    }
    expect(request.choices.where(ApprovalRequest.isDeny).length, 1);
  });

  test('an unknown choice degrades to showing itself rather than crashing', () {
    // Forward compatibility: a newer server may add a choice this build has
    // never heard of. It must still render as a button.
    expect(ApprovalRequest.labelFor('escalate'), 'escalate');
  });
}
