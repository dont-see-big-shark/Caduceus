/// What a backend already knew about a session the moment it was opened.
library;

import 'package:meta/meta.dart';

import 'session.dart';

/// A turn that was already running when the client arrived.
///
/// Joining a conversation mid-turn is not an edge case — it is what happens
/// every time the app is reopened while the agent is still working, and every
/// time a reconnect lands in the middle of an answer. A client that ignores it
/// shows the transcript without the question currently being answered, and
/// then appends new deltas under nothing.
@immutable
class ResumedTurn {
  const ResumedTurn({
    this.prompt = '',
    this.answerSoFar = '',
    this.streaming = false,
  });

  /// The question being answered.
  final String prompt;

  /// Answer text so far. Empty while the model is still thinking.
  final String answerSoFar;

  /// True when more is still coming. False for a turn that ended between the
  /// server assembling this reply and the client reading it.
  final bool streaming;

  bool get isEmpty => prompt.isEmpty && answerSoFar.isEmpty;

  @override
  String toString() =>
      'ResumedTurn(${prompt.length} + ${answerSoFar.length} chars'
      '${streaming ? ', streaming' : ''})';
}

/// The live state of a session at the moment [AgentBackend.open] returned.
///
/// Separate from `history()` on purpose, and the split is the same one
/// `AgentMessage` documents: history is what the server *stored*, this is what
/// is *happening*. They carry different information and merging them would
/// force the stored case to invent a running turn it has no idea about.
///
/// It is an accessor rather than part of `open()`'s return value so that the
/// handle stays the handle. Backends that know none of this return a bare
/// [AgentSession] and nothing else, which is honest — an empty [inflight] says
/// "no turn is running", and a backend that cannot tell should say so by
/// declaring the capability rather than by inventing one.
@immutable
class OpenedSession {
  const OpenedSession({
    required this.session,
    this.inflight,
    this.queuedPrompt = '',
  });

  /// Everything the list row would have shown, plus the model, working
  /// directory, branch and approval posture the backend reported on opening.
  final AgentSession session;

  /// The turn in progress, if there is one.
  final ResumedTurn? inflight;

  /// A prompt the server accepted but has not started answering.
  ///
  /// Deliberately not part of the transcript: it has no answer yet, and
  /// writing it after a partial answer means the next delta lands below it and
  /// splits the answer in half. It belongs beside the composer, as a note
  /// about what happens next.
  final String queuedPrompt;

  @override
  String toString() =>
      'OpenedSession(${session.id}${inflight == null ? '' : ', mid-turn'})';
}
