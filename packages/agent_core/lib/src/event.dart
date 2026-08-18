/// Everything a backend says about a session, normalised.
library;

import 'package:meta/meta.dart';

import 'message.dart';
import 'prompt.dart';
import 'session.dart';
import 'tool.dart';

/// An opaque marker for "I have seen everything up to here".
///
/// Hermes exposes no ordering at all and puts nothing here. OpenClaw stamps
/// every event with `seq` and `stateVersion`, and a client that reconnects
/// without replaying from its last cursor silently loses the middle of a turn.
///
/// The type is opaque because the two meanings have nothing in common and any
/// attempt to unify them would be a lie: only the adapter that made a cursor
/// may read it. The UI carries one around and hands it back.
@immutable
class ResumeCursor {
  const ResumeCursor(this.value);

  /// Adapter-private. Do not interpret this outside the adapter that set it.
  final Object value;

  @override
  String toString() => 'ResumeCursor($value)';
}

/// Why a turn ended.
enum FinishReason {
  /// The agent finished answering.
  completed,

  /// The user stopped it.
  interrupted,

  /// The backend gave up — an error, a provider failure, a lost connection
  /// mid-turn. [TurnFinished.detail] says what it was.
  failed,
}

/// One thing that happened in a session.
///
/// Delta-shaped rather than snapshot-shaped, which is forced: turning deltas
/// into a snapshot is an append, turning snapshots into deltas is a diff. A
/// backend that sends both (OpenClaw does) emits the deltas and uses the
/// snapshots to *check* itself — see [TextReset].
sealed class AgentEvent {
  const AgentEvent({required this.sessionId, this.cursor});

  /// Which session this belongs to. Always set: a client showing more than one
  /// conversation must route on this rather than assuming one active session.
  final String sessionId;

  /// Where this event sits in the backend's ordering, when it has one.
  final ResumeCursor? cursor;
}

/// The agent has begun working on a turn.
final class TurnStarted extends AgentEvent {
  const TurnStarted({required super.sessionId, super.cursor});
}

/// More of the answer.
final class TextDelta extends AgentEvent {
  const TextDelta({
    required super.sessionId,
    required this.text,
    super.cursor,
  });

  final String text;
}

/// The accumulated answer diverged from the server's, and this is the
/// server's.
///
/// Only a backend that sends both deltas and cumulative snapshots can raise
/// this, and only when the two disagree. The alternative — quietly preferring
/// one — means a transcript that has drifted from what the agent actually said
/// and no way to tell. A visible correction is the lesser evil.
final class TextReset extends AgentEvent {
  const TextReset({
    required super.sessionId,
    required this.text,
    super.cursor,
  });

  /// The full text of the answer so far, replacing everything accumulated.
  final String text;
}

/// More of the model's reasoning. A separate channel from [TextDelta], never
/// concatenated into it.
final class ReasoningDelta extends AgentEvent {
  const ReasoningDelta({
    required super.sessionId,
    required this.text,
    super.cursor,
  });

  final String text;
}

/// A whole reasoning trace delivered at once instead of streamed.
///
/// Some models produce this *instead of* [ReasoningDelta], so a client that
/// handles only the delta channel shows such a model as having done no
/// thinking at all. Separate from the delta because when both arrive the block
/// restates what the deltas already said, and appending would double it.
final class ReasoningBlock extends AgentEvent {
  const ReasoningBlock({
    required super.sessionId,
    required this.text,
    super.cursor,
  });

  final String text;
}

/// The backend's live status line — *not* reasoning.
///
/// Its whole purpose is explaining a long wait: no first byte yet, provider
/// overloaded, a reasoning model thinking for minutes. Folding it into the
/// reasoning channel puts spinner text in the middle of the model's thoughts
/// and wastes the one channel that says why a 57-second wait is taking 57
/// seconds. This client has made that mistake once already.
final class StatusText extends AgentEvent {
  const StatusText({
    required super.sessionId,
    required this.text,
    super.cursor,
  });

  final String text;
}

/// The agent is assembling a call to [toolName] but has not run it yet.
///
/// Distinct from [ToolStarted] because the gap between them is where a slow
/// model spends its time, and a UI with no state for it shows nothing at all
/// during the longest part of some turns.
final class ToolPreparing extends AgentEvent {
  const ToolPreparing({
    required super.sessionId,
    required this.toolName,
    super.cursor,
  });

  final String toolName;
}

/// A tool is running.
final class ToolStarted extends AgentEvent {
  const ToolStarted({
    required super.sessionId,
    required this.toolId,
    required this.call,
    super.cursor,
  });

  /// Correlates with the [ToolFinished] that closes it. Not the tool's name —
  /// the same tool runs many times in one turn.
  final String toolId;

  final AgentToolCall call;
}

/// A tool that is still running has produced output.
final class ToolProgress extends AgentEvent {
  const ToolProgress({
    required super.sessionId,
    required this.toolId,
    required this.text,
    super.cursor,
  });

  final String toolId;
  final String text;
}

/// A tool returned.
final class ToolFinished extends AgentEvent {
  const ToolFinished({
    required super.sessionId,
    required this.toolId,
    required this.call,
    super.cursor,
  });

  final String toolId;

  /// The completed call, with output, exit status and duration filled in.
  final AgentToolCall call;
}

/// The agent is blocked on a question.
final class PromptRaised extends AgentEvent {
  const PromptRaised({
    required super.sessionId,
    required this.prompt,
    super.cursor,
  });

  final AgentPrompt prompt;
}

/// The server gave up waiting on a question.
///
/// The record stays on screen — it is part of what happened — but nothing may
/// still invite an answer, because there is no longer anything listening for
/// one.
final class PromptExpired extends AgentEvent {
  const PromptExpired({
    required super.sessionId,
    required this.id,
    super.cursor,
  });

  final PromptId id;
}

/// The turn is over.
final class TurnFinished extends AgentEvent {
  const TurnFinished({
    required super.sessionId,
    this.reason = FinishReason.completed,
    this.detail = '',
    super.cursor,
  });

  final FinishReason reason;

  /// Why, when [reason] is [FinishReason.failed]. Shown, not parsed.
  final String detail;
}

/// A settled message joined the transcript that this client did not write.
///
/// Not a delta and not a snapshot of the answer in progress: a whole message,
/// already stored, that arrived because somebody else was talking to the same
/// agent — from a phone, a chat channel, another window. A client without this
/// shows half a conversation and no sign that the other half exists.
///
/// Backends that cannot report it simply never raise it, which is not the same
/// as an agent nobody else talks to.
final class MessageAppended extends AgentEvent {
  const MessageAppended({
    required super.sessionId,
    required this.message,
    super.cursor,
  });

  final AgentMessage message;
}

/// The session's own metadata moved — a title arrived, the count changed.
final class SessionChanged extends AgentEvent {
  const SessionChanged({
    required super.sessionId,
    required this.session,
    super.cursor,
  });

  final AgentSession session;
}

/// Something the backend said that the domain has no concept for.
///
/// Deliberate, not a dumping ground. Every backend has events this model does
/// not cover, and the choice is between dropping them silently and showing
/// them as what they are: a note from the server. Hermes' model-switch markers
/// already live in this grey zone. A [BackendNotice] that turns out to matter
/// is evidence for a new event type — not a reason to switch on [kind].
final class BackendNotice extends AgentEvent {
  const BackendNotice({
    required super.sessionId,
    required this.text,
    this.kind = '',
    super.cursor,
  });

  final String text;

  /// The backend's own name for it, for logs and for deciding whether this
  /// deserves promoting to a real event.
  final String kind;
}
