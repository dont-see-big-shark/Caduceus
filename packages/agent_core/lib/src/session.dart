/// A conversation, and the handle a backend hands back when one is opened.
library;

import 'package:meta/meta.dart';

/// One conversation as it appears in a list.
///
/// The fields are the intersection that every backend can fill: an id, a label,
/// how much has been said, when it last moved, and whether it is running. What
/// a specific backend knows on top of that (Hermes' `source`, OpenClaw's
/// `stateVersion`) does not belong here — it belongs in the adapter, keyed off
/// [id].
@immutable
class AgentSession {
  const AgentSession({
    required this.id,
    this.title = '',
    this.preview = '',
    this.messageCount = 0,
    this.updatedAt,
    this.running = false,
    this.model = '',
    this.cwd = '',
    this.branch = '',
    this.source = '',
    this.approvalMode = '',
    this.unattended = false,
    this.warning = '',
  });

  /// The durable id — what the sidebar shows and what survives a reconnect.
  /// Distinct from the live handle a backend uses on the wire; see
  /// [SessionHandle].
  final String id;

  /// A server-set title, when there is one.
  final String title;

  /// First user message, for when there is no title. Most sessions have no
  /// title, so this is usually what a row shows.
  final String preview;

  final int messageCount;

  /// When the session last had activity. Backends order their lists by this;
  /// the field is here so the UI can show it, not so it can re-sort.
  final DateTime? updatedAt;

  /// A turn is running in this session right now.
  final bool running;

  /// Where the conversation came from — which client or channel started it.
  ///
  /// Hermes calls it `source` (`desktop`, `tui`, a messaging platform);
  /// OpenClaw spells the same idea in its session keys (`dashboard`, `ios`,
  /// `telegram`, `cron`). Universal enough to be worth searching on, which is
  /// what the sidebar does with it, and free text because the vocabulary is
  /// each backend's own.
  final String source;

  /// Which model is answering. Empty where the backend does not say.
  final String model;

  /// The working directory **on the server**.
  ///
  /// In the domain rather than an adapter because it is not a Hermes detail:
  /// every path in a prompt resolves against it, on any backend, and a client
  /// that never shows it leaves the user guessing which machine and which
  /// directory their words apply to.
  final String cwd;

  /// The git branch at [cwd]. Empty when it is not a repository — which is a
  /// perfectly ordinary state and not an error.
  final String branch;

  /// How this session gates tool use, in the backend's own word for it —
  /// `smart`, `manual`, `auto` on Hermes. Shown to the user, never switched
  /// on: the vocabulary is the backend's and the next one will differ.
  final String approvalMode;

  /// True when nothing will stop and ask before acting.
  ///
  /// The single most important thing a user can know about a session, and the
  /// reason it is in the domain rather than in an adapter. Each backend
  /// *derives* it from its own settings — Hermes from `yolo` or an `auto`
  /// approval mode — so the UI gets one honest boolean instead of a rule it
  /// would have to re-implement per backend.
  final bool unattended;

  /// The server's own warning about its configuration, if it sent one.
  /// Displayed verbatim; empty when there is nothing wrong.
  final String warning;

  /// This session, updated with whatever [next] actually reports.
  ///
  /// Backends send partial updates: `session.info` names only the fields that
  /// moved, and an empty string there means "not mentioned", not "cleared".
  /// Taking the whole object would blank the model every time a cwd change
  /// arrived on its own.
  AgentSession mergedWith(AgentSession next) => AgentSession(
    id: id,
    title: next.title.isEmpty ? title : next.title,
    preview: next.preview.isEmpty ? preview : next.preview,
    messageCount: next.messageCount == 0 ? messageCount : next.messageCount,
    updatedAt: next.updatedAt ?? updatedAt,
    running: next.running,
    source: next.source.isEmpty ? source : next.source,
    model: next.model.isEmpty ? model : next.model,
    cwd: next.cwd.isEmpty ? cwd : next.cwd,
    branch: next.branch.isEmpty ? branch : next.branch,
    approvalMode: next.approvalMode.isEmpty ? approvalMode : next.approvalMode,
    // A bool cannot say "not mentioned", so this one is always taken. A
    // backend that reports the posture at all reports it on every update.
    unattended: next.unattended,
    warning: next.warning,
  );

  /// What a row shows: a real title, else the preview, else the id.
  String get label {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final p = preview.trim();
    return p.isNotEmpty ? p : id;
  }

  AgentSession copyWith({
    String? title,
    String? preview,
    int? messageCount,
    DateTime? updatedAt,
    bool? running,
    String? source,
    String? model,
    String? cwd,
    String? branch,
    String? approvalMode,
    bool? unattended,
    String? warning,
  }) => AgentSession(
    id: id,
    title: title ?? this.title,
    preview: preview ?? this.preview,
    messageCount: messageCount ?? this.messageCount,
    updatedAt: updatedAt ?? this.updatedAt,
    running: running ?? this.running,
    source: source ?? this.source,
    model: model ?? this.model,
    cwd: cwd ?? this.cwd,
    branch: branch ?? this.branch,
    approvalMode: approvalMode ?? this.approvalMode,
    unattended: unattended ?? this.unattended,
    warning: warning ?? this.warning,
  );

  @override
  String toString() => 'AgentSession($id, "$label", $messageCount msgs)';
}

/// An opaque reference to an opened session.
///
/// It exists because the durable id and the thing a backend actually talks to
/// are not the same, on either backend: Hermes returns a gateway handle plus a
/// stored id; OpenClaw carries a per-session subscription and a `seq`/
/// `stateVersion` cursor. The UI holds a handle and passes it back; it never
/// constructs one and never reads inside it. Only the adapter that made it
/// knows what its [wireId] and [cursor] mean.
@immutable
class SessionHandle {
  const SessionHandle({
    required this.sessionId,
    required this.wireId,
    this.cursor,
  });

  /// The durable id this handle opens — the one in [AgentSession.id].
  final String sessionId;

  /// The id the backend uses on the wire for this open session. May equal
  /// [sessionId]; often does not.
  final String wireId;

  /// A backend-private resume marker (OpenClaw's `seq`/`stateVersion`), opaque
  /// to everything but the adapter. Null where the backend has no such notion.
  final Object? cursor;

  SessionHandle withCursor(Object? cursor) =>
      SessionHandle(sessionId: sessionId, wireId: wireId, cursor: cursor);

  @override
  String toString() => 'SessionHandle($sessionId via $wireId)';
}
