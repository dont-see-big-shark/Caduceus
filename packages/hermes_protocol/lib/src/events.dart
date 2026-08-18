import 'package:meta/meta.dart';

import 'jsonrpc.dart';

/// A control-plane event, unwrapped from its envelope.
///
/// Every server push arrives as the *same* JSON-RPC method, `"event"` — the
/// real event name is nested inside. From `_event_frame` in
/// `tui_gateway/server.py`:
///
/// ```json
/// {"jsonrpc":"2.0","method":"event",
///  "params":{"type":"message.delta","session_id":"...","payload":{...}}}
/// ```
///
/// A client that switches on the JSON-RPC method sees only `"event"` for
/// everything and cannot tell a token from an approval request. Unwrapping is
/// mandatory, not a convenience.
@immutable
class GatewayEvent {
  const GatewayEvent({
    required this.type,
    required this.sessionId,
    required this.payload,
  });

  /// The real event name: `message.delta`, `approval.request`, `tool.started`…
  final String type;

  /// Present on nearly every frame. A console showing more than one session at
  /// a time must route on this rather than assuming a single active session.
  final String? sessionId;

  final Map<String, dynamic> payload;

  /// Returns null when [n] is not an event envelope.
  static GatewayEvent? fromNotification(GatewayNotification n) {
    if (n.method != 'event') return null;
    final type = n.params['type'];
    if (type is! String) return null;
    final payload = n.params['payload'];
    return GatewayEvent(
      type: type,
      sessionId: n.params['session_id'] as String?,
      payload: payload is Map<String, dynamic> ? payload : const {},
    );
  }

  /// The high-frequency frames the server coalesces on a 33 ms timer
  /// (`_STREAMING_EVENT_TYPES` in `tui_gateway/ws.py`). Everything else is
  /// flushed ahead of the buffer, so ordering against these is guaranteed.
  static const streamingTypes = {
    'message.delta',
    'reasoning.delta',
    'thinking.delta',
  };

  bool get isStreamingDelta => streamingTypes.contains(type);

  /// Incremental text of the **answer**.
  ///
  /// Only `message.delta`. Reasoning and thinking are deliberately excluded:
  /// they are a different channel and must not be concatenated into the reply.
  /// A live run against a real agent produced 13 `reasoning.delta` frames
  /// against 1 `message.delta`, so treating them alike buries the answer inside
  /// the model's private notes.
  String? get answerText =>
      type == 'message.delta' ? payload['text']?.toString() : null;

  /// Incremental text of the model's reasoning trace.
  ///
  /// Belongs in its own collapsible region, not the transcript body.
  String? get reasoningText =>
      type == 'reasoning.delta' ? payload['text']?.toString() : null;

  /// The server's live status line — *not* reasoning.
  ///
  /// `run_agent.py` is explicit about this: the same callback drives the CLI
  /// spinner text and this event, and its whole purpose is explaining a long
  /// wait ("no first byte yet", "provider overloaded", "reasoning model
  /// thinking for minutes"). This client treated it as reasoning for months,
  /// which put `◉_◉ cogitating...` into the middle of the model's thoughts
  /// and, worse, wasted the one channel that says *why* a 57-second wait is
  /// taking 57 seconds.
  String? get statusText =>
      type == 'thinking.delta' ? payload['text']?.toString() : null;

  /// A whole reasoning trace delivered in one frame rather than streamed.
  ///
  /// The server emits `reasoning.available` with the full preview text
  /// (`server.py`, the `event_type == "reasoning.available"` branch). Some
  /// models produce this *instead of* `reasoning.delta`, so a client that
  /// handles only the delta channel shows such a model as having done no
  /// thinking at all. Kept separate from [reasoningText] because when both
  /// arrive the block restates what the deltas already said, and appending it
  /// would double the trace.
  String? get reasoningBlockText =>
      type == 'reasoning.available' ? payload['text']?.toString() : null;

  /// Any streamed text, regardless of channel. Prefer [answerText] or
  /// [reasoningText]; this exists for tooling that genuinely wants both.
  String? get deltaText =>
      isStreamingDelta ? payload['text']?.toString() : null;

  bool get isReasoningDelta => reasoningText != null;

  /// An approval gate is waiting. Only the control plane emits this — it is the
  /// capability an OpenAI-compatible client structurally cannot offer.
  bool get isApprovalRequest => type == 'approval.request';

  /// A question or credential the agent is *blocked* waiting on.
  ///
  /// Unlike a delta, ignoring one of these does not lose information — it
  /// stalls the agent thread until the server's timeout, which looks exactly
  /// like a hung connection.
  bool get isBlockingPrompt => const {
        'clarify.request',
        'sudo.request',
        'secret.request',
      }.contains(type);

  /// The agent asking for the client's in-app terminal buffer. Blocking, with
  /// a 30 s server-side timeout.
  bool get isTerminalReadRequest => type == 'terminal.read.request';

  /// The server gave up waiting on a blocking prompt. Carries the same
  /// `request_id`, so the matching banner can be withdrawn instead of sitting
  /// there inviting an answer nobody is listening for any more.
  bool get isPromptExpiry => const {
        'clarify.expire',
        'sudo.expire',
        'secret.expire',
        'terminal.read.expire',
      }.contains(type);

  /// Correlates a blocking prompt with its `*.respond` call. Not the session
  /// id — the server keys pending answers on this alone.
  String? get requestId => payload['request_id']?.toString();

  @override
  String toString() =>
      'GatewayEvent($type${sessionId == null ? '' : ', session $sessionId'})';
}
