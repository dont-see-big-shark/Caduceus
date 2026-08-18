/// A question the agent is blocked on, and the answer that releases it.
library;

import 'package:meta/meta.dart';

/// Correlates a question with the answer sent back.
///
/// An extension type rather than a bare `String` because the two ids in play
/// around a prompt — the request id and the session id — are both strings, and
/// they were swapped once already. The wrong one costs nothing at compile time
/// and hangs the agent until the server's timeout at run time, which reads
/// exactly like a dead connection.
extension type const PromptId(String value) {
  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
}

/// What kind of answer a question wants.
///
/// The distinction that matters is not what the server calls the event but
/// what the *client* must do differently: mask the field, keep it out of the
/// transcript, and never log it. That is one bit, and [AgentPrompt.isSecret]
/// is it, and [AgentPromptKind.approval] is the one case that is genuinely
/// about something else. The rest exist because the wording differs.
enum AgentPromptKind {
  /// An ordinary question. Free text, or one of [AgentPrompt.choices].
  clarify,

  /// A password for privilege elevation. Hermes calls this `sudo`; the
  /// domain does not, because the concept is "elevate", not "run `sudo`".
  password,

  /// A credential the agent needs and does not have — an API key, a token.
  /// [AgentPrompt.envVar] says where the server will store it.
  secret,

  /// Permission to do something, usually run a command.
  ///
  /// Its own kind rather than a [clarify] with choices, because the answer is
  /// a *policy decision about the agent* rather than information for it: the
  /// choices are a closed set the server sends, one of them is a refusal, and
  /// getting it wrong is not a worse answer but a command that runs when it
  /// should not have. Both backends have it — Hermes as `approval.request`,
  /// OpenClaw as `exec.approval.resolve` — and both needed the client to tell
  /// it apart from a question.
  approval,
}

/// A question or credential the agent is waiting on before it can continue.
///
/// Every agent has this concept: Hermes raises `clarify.request` /
/// `sudo.request` / `secret.request` and takes the answer through the matching
/// `*.respond`; OpenClaw blocks a tool and resolves it through
/// `exec.approval.resolve`. What they share is the shape below, so this is the
/// type the UI is built on and the adapters map onto.
///
/// It is deliberately *not* the union of both wire types. An adapter that
/// cannot fill a field leaves it empty; a field only one backend has belongs
/// in that adapter, keyed off [id].
@immutable
class AgentPrompt {
  const AgentPrompt({
    required this.id,
    required this.kind,
    this.question = '',
    this.choices = const [],
    this.multiSelect = false,
    this.envVar = '',
    this.subject = '',
    this.escalated = false,
  });

  /// What the answer is sent back against. Not the session id.
  final PromptId id;

  final AgentPromptKind kind;

  /// What was asked, as the agent phrased it. May be empty — some servers
  /// raise a credential request with no prose at all, and the UI's own header
  /// carries the meaning in that case.
  final String question;

  /// Offered answers. Empty means free text.
  final List<String> choices;

  /// More than one of [choices] may be picked.
  ///
  /// Servers send this specifically for clients that can render a checklist.
  /// Asking someone to retype the options comma-separated when they are
  /// already on screen is the fallback, not the feature.
  final bool multiSelect;

  /// For a [AgentPromptKind.secret]: the environment variable the server will
  /// store the answer under. Empty otherwise.
  final String envVar;

  /// What the question is *about* — the tool being asked for, on an
  /// [AgentPromptKind.approval]. Empty where the backend does not name one.
  ///
  /// Separate from [question], which is the thing itself (the command), so a
  /// header can say what kind of permission this is while the body shows the
  /// text verbatim in monospace.
  final String subject;

  /// True when this has already been refused once and the user is overriding.
  ///
  /// A boolean rather than a message because the wording is the UI's. Hermes
  /// raises it for an owner override of a Smart-mode denial; any backend with
  /// a policy engine that can be overruled has the same state, and a client
  /// that shows such a re-ask identically to a first ask hides the fact that
  /// something already said no.
  final bool escalated;

  /// True when the answer must never be echoed, stored, or logged.
  ///
  /// The one bit the whole UI branches on: it masks the field, disables
  /// autocorrect and suggestions, and keeps the value out of the transcript.
  ///
  /// An [AgentPromptKind.approval] is *not* secret — "allow once" is not a
  /// credential, and masking it would hide the very thing the user is being
  /// asked to read.
  bool get isSecret =>
      kind == AgentPromptKind.password || kind == AgentPromptKind.secret;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentPrompt && other.id.value == id.value && other.kind == kind;

  @override
  int get hashCode => Object.hash(id.value, kind);

  @override
  String toString() => 'AgentPrompt(${id.value}, ${kind.name})';
}

/// The answer to an [AgentPrompt].
///
/// A type rather than a bare `String` for one reason, and it is the reason
/// [AgentPrompt.isSecret] exists: an answer that must not be logged has to be
/// distinguishable from one that may be, at the point something is about to
/// write it somewhere. A `String` carries no such marking, and every logging
/// call site would have to remember which prompt it came from.
@immutable
class PromptAnswer {
  const PromptAnswer(this.text, {this.secret = false});

  /// The answer as the user gave it. For [AgentPrompt.multiSelect], the picked
  /// choices joined with `', '` — in the order the server offered them, not
  /// the order they were clicked.
  final String text;

  /// Never log, store, or display this.
  final bool secret;

  /// Safe in a log line. A secret renders as its length and nothing else.
  @override
  String toString() =>
      secret ? 'PromptAnswer(<secret, ${text.length} chars>)' : 'PromptAnswer($text)';
}
