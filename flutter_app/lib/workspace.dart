import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

import 'package:agent_core/agent_core.dart';

import 'backend_pool.dart';
import 'backends/claw_backend.dart';
import 'backends/hermes_backend.dart';
import 'memory_ledger.dart';
import 'design/tokens.dart';
import 'domain/transcript.dart';
import 'haptics.dart';
import 'transcript_blobs.dart';

// Re-exported so the files that already use Turn, ToolCall and friends
// do not all have to change their imports in the same commit as the
// move. ARCHITECTURE.md phase 1 unwinds this.
export 'domain/transcript.dart';

/// Human-readable cause of a failed control-plane call.
///
/// Not every failure is a [GatewayRpcException]: a call made while the socket
/// is down fails with [GatewayDisconnected], and catching only the former let
/// that escape as an unhandled async error — no banner, and a console left
/// wedged at "streaming" so every later message was steered into a turn that
/// was not running.
String _reason(Object error) => error.userFacingMessage;

/// One entry in a turn's timeline: either a stretch of reasoning or a tool
class SessionConsole extends ChangeNotifier {
  SessionConsole({required this.persistedId, String? liveId, String model = ''})
    : liveId = liveId ?? persistedId,
      _info = AgentSession(id: persistedId, model: model) {
    // The aurora drifts every frame behind the transcript; while the user is
    // scrolling it competes for the same frame budget. Pause it during scroll
    // and let it come back shortly after the finger lifts.
    markdown.scrollController.addListener(_pauseAmbientDuringScroll);
  }

  Timer? _ambientIdle;

  void _pauseAmbientDuringScroll() {
    Materials.ambientPaused.value = true;
    _ambientIdle?.cancel();
    _ambientIdle = Timer(const Duration(milliseconds: 600), () {
      Materials.ambientPaused.value = false;
    });
  }

  /// Durable id from `session.list`. Identifies the row in the sidebar.
  final String persistedId;

  /// Gateway-local handle from `session.resume`. **Every RPC and every inbound
  /// event uses this**, not [persistedId] — see [ResumedSession].
  String liveId;

  /// What the backend has said about this session so far, folded together.
  AgentSession _info;

  String get model => _info.model;
  set model(String value) => _info = _info.copyWith(model: value);

  /// What to call this session in the UI.
  ///
  /// Not the persisted id. That id is a timestamp — `20260802_220058_cc4868` —
  /// and using it as a heading tells the user when they started, which is the
  /// one thing the ordering already tells them. The server sets real titles
  /// and pushes `session.title` when it does.
  String get title => _info.title;
  set title(String value) => _info = _info.copyWith(title: value);

  /// The title if there is one, otherwise the id — which at least identifies
  /// the session, even reading like a serial number.
  String get displayTitle => title.trim().isEmpty ? persistedId : title.trim();

  /// Working directory on the *server*. Shown in the header because every
  /// path in a prompt is resolved there, not here.
  String get cwd => _info.cwd;
  set cwd(String value) => _info = _info.copyWith(cwd: value);

  /// The git branch there, empty when it is not a repository. Settable
  /// because a directory change answers with both at once.
  String get branch => _info.branch;
  set branch(String value) => _info = _info.copyWith(branch: value);

  /// Applies what a backend reported when the session was opened.
  ///
  /// Merged rather than assigned, for the same reason a `SessionChanged` is:
  /// an empty field means "not mentioned", and the console has already been
  /// seeded with the title from the row the user tapped.
  void applyInfo(AgentSession session) {
    _info = _info.mergedWith(session);
    notifyListeners();
  }

  final markdown = StreamingMarkdownController();
  final reasoning = StringBuffer();

  /// When the current turn started thinking, and how long it thought.
  ///
  /// A turn can spend a minute reasoning before it emits a single token of
  /// answer. Without this the console showed a static "Reasoning · N chars"
  /// and nothing else moved, which is indistinguishable from a hung
  /// connection — the complaint that prompted it. Hermes' own client shows a
  /// running "Thinking 57s", and it is right to.
  DateTime? thinkingStartedAt;
  Duration thinkingDuration = Duration.zero;

  /// True while the model is reasoning and has not yet emitted answer text.
  bool get isThinking => thinkingStartedAt != null && !answerStarted;

  /// Live elapsed thinking time, or the final figure once the turn produced
  /// an answer.
  Duration get thinkingElapsed => thinkingStartedAt == null
      ? thinkingDuration
      : DateTime.now().difference(thinkingStartedAt!);

  /// Whether this turn has produced any answer text yet.
  bool answerStarted = false;

  /// Offset into the rendered transcript where this turn's answer starts.
  ///
  /// Only [TextReset] reads it, and only a backend that sends both deltas and
  /// cumulative snapshots can cause one. Null until the turn's first answer
  /// token, and null again for a turn that produced no answer at all.
  int? _answerStartsAt;

  /// Every turn's reasoning and tool calls, oldest first, each turn its own
  /// list. Previously only the current turn was kept, so sending a second
  /// prompt erased the record of how the first one was answered — the tool
  /// that ran, what it printed, how long the model thought about it.
  ///
  /// Capped: a session that runs all day would otherwise hold every reasoning
  /// trace it ever produced. The oldest are dropped, not summarised, and the
  /// UI says how many.
  static const maxRetainedTurns = 20;
  final List<Turn> turns = [];

  /// Turns dropped from [turns] to stay under the cap.
  int forgottenTurns = 0;

  /// Images shown in this session's transcript, held outside the transcript
  /// text and under their own byte budget. See [TranscriptBlobStore].
  final TranscriptBlobStore blobs = TranscriptBlobStore();

  /// The current turn's entries. Empty before the first prompt.
  List<TurnEntry> get timeline => turns.isEmpty ? const [] : turns.last.entries;

  ThinkingSegment? get _openSegment {
    if (turns.isEmpty) return null;
    for (final entry in turns.last.entries.reversed) {
      if (entry is ThinkingSegment && entry.open) return entry;
      if (entry is ToolEntry) return null;
    }
    return null;
  }

  /// The list new entries go into, starting a turn if none is open. A tool
  /// event can be the first thing seen after a reconnect.
  List<TurnEntry> get _currentTurn {
    if (turns.isEmpty) turns.add(Turn(anchorBlock: _anchorNow()));
    return turns.last.entries;
  }

  void _closeSegment() {
    final open = _openSegment;
    if (open != null) open.endedAt = DateTime.now();
  }

  /// The tail of the reasoning, for a one-line preview while it is collapsed.
  /// Seeing the words change is what makes a long think read as progress
  /// rather than as a freeze.
  String get reasoningPreview {
    final text = reasoning.toString().trimRight();
    if (text.isEmpty) return '';
    final lastBreak = text.lastIndexOf('\n');
    final line = lastBreak == -1 ? text : text.substring(lastBreak + 1);
    final trimmed = line.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.length <= 120
        ? trimmed
        : '…${trimmed.substring(trimmed.length - 120)}';
  }

  /// Starts a turn: thinking begins, and last turn's reasoning stops being
  /// this turn's. Kept per turn rather than cumulative because a session-wide
  /// buffer answers a question nobody asks — what matters is what the model is
  /// thinking *now*.
  /// Where the transcript currently ends — the block the next turn's
  /// thinking should render after.
  int _anchorNow() => markdown.settledBlockCount - 1;

  void _beginTurn() {
    if (thinkingStartedAt != null) return;
    reasoning.clear();
    turns.add(Turn(anchorBlock: _anchorNow()));
    while (turns.length > maxRetainedTurns) {
      turns.removeAt(0);
      forgottenTurns++;
    }
    thinkingStartedAt = DateTime.now();
    thinkingDuration = Duration.zero;
    answerStarted = false;
    // Belongs to the turn that has just ended, and pointing a correction at a
    // stale offset would rebuild the transcript from the wrong place.
    _answerStartsAt = null;
  }

  void _endTurn() {
    _closeSegment();
    statusLine = '';
    if (thinkingStartedAt != null && !answerStarted) {
      thinkingDuration = DateTime.now().difference(thinkingStartedAt!);
    }
    thinkingStartedAt = null;
  }

  final Map<String, ToolCall> tools = {};

  /// Permission gates the agent is stopped at. Kept apart from [prompts]
  /// because an approval gates the whole session and renders beside the
  /// composer, while a question renders inside the turn that asked it.
  final List<AgentPrompt> approvals = [];

  /// Questions and credential requests the agent is *blocked* on. Unanswered,
  /// the turn stalls until the server's timeout.
  final List<AgentPrompt> prompts = [];

  String? generatingTool;

  /// The server's live status line, e.g. why a provider call is taking a
  /// minute. Cleared when the turn ends, because a stale explanation of a
  /// finished wait is worse than none.
  String statusLine = '';

  bool streaming = false;
  int deltaCount = 0;
  String? lastError;

  /// When the last inbound frame for this session arrived.
  ///
  /// Which question bubbles have already played their entrance.
  ///
  /// Lives on the console rather than in the widget, for the same reason
  /// [Turn.revealed] does: the transcript is a `ListView.builder`, so a bubble
  /// scrolled off and back is a *new* widget with an old meaning.
  final Set<int> revealedBubbles = {};

  /// A turn can legitimately go quiet for a long time — a slow tool, a large
  /// context. What is not acceptable is the UI looking identical whether the
  /// agent is thinking or the connection has died, which is exactly how "I
  /// sent a message and nothing happened" felt. The header shows this.
  DateTime? lastActivity;

  /// Seconds since the last frame, while a turn is running.
  Duration get sinceActivity => lastActivity == null
      ? Duration.zero
      : DateTime.now().difference(lastActivity!);

  /// 1 Hz, and only while streaming: the quiet case is the one that needs a
  /// moving number, and it produces no other notifications by definition.
  Timer? _idleTick;

  void _startIdleTick() {
    lastActivity = DateTime.now();
    _idleTick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !streaming) return;
      notifyListeners();
    });
  }

  void _stopIdleTick() {
    _idleTick?.cancel();
    _idleTick = null;
  }

  /// Counters and the reasoning buffer change on every token. Notifying per
  /// token would rebuild the console — and the header, and the reasoning pane —
  /// hundreds of times a second, undoing exactly what the incremental renderer
  /// achieves. They are coalesced to ~4 Hz instead, which is well under the
  /// threshold where a counter looks stalled.
  Timer? _statsTick;

  void _notifyStatsSoon() {
    if (_statsTick != null) return;
    _statsTick = Timer(const Duration(milliseconds: 250), () {
      _statsTick = null;
      if (!_disposed) notifyListeners();
    });
  }

  Timer? _liveTick;

  /// Coalescing for text the user is *reading as it arrives*.
  ///
  /// 250 ms was chosen for counters — a delta count and a block total, where
  /// nobody notices four updates a second. Reasoning went through the same
  /// path, and it is the one thing on screen being read word by word. A trace
  /// that the server delivers in a 892 ms burst got three repaints, which
  /// looks exactly like it appeared all at once.
  ///
  /// The answer text never had this problem because it bypasses the console
  /// entirely and drives its own renderer. Reasoning has no such channel, so
  /// it gets a cadence that matches a display instead of a counter. Measured
  /// cost of a repaint here is ~0.5 ms against a 16.67 ms budget, so 20 Hz is
  /// not close to expensive.
  void _notifyLiveSoon() {
    if (_liveTick != null) return;
    _liveTick = Timer(const Duration(milliseconds: 50), () {
      _liveTick = null;
      if (!_disposed) notifyListeners();
    });
  }

  bool _disposed = false;

  /// Populated from `session.resume`, which returns the transcript inline.
  bool historyLoaded = false;

  /// A prompt the server accepted but has not started. Invisible everywhere
  /// else until the current turn drains.
  String? queuedPrompt;

  /// How this session gates tool use, in the backend's own word for it:
  /// `smart`, `manual`, `auto`, and so on. Shown, never switched on.
  String get approvalMode => _info.approvalMode;

  /// The server's own warning about its configuration, if it sent one.
  String? get configWarning => _info.warning.isEmpty ? null : _info.warning;

  /// True when nothing will stop to ask before acting.
  ///
  /// Reported by the backend rather than worked out here: Hermes says it two
  /// ways (`yolo`, or an `auto` approval mode) and the next backend will say
  /// it a third, which is a rule no console should be re-implementing.
  bool get unattended => _info.unattended;

  /// Drops everything rendered so far, so a reload does not append a second
  /// copy of the conversation underneath the first.
  void resetTranscript() {
    markdown.reset();
    reasoning.clear();
    tools.clear();
    turns.clear();
    blobs.clear();
    forgottenTurns = 0;
    generatingTool = null;
    deltaCount = 0;
    historyLoaded = false;
    notifyListeners();
  }

  /// Replays a turn that was already running when this client resumed.
  ///
  /// Without it, resuming mid-turn shows the transcript up to the previous
  /// exchange and then starts appending deltas with no question above them.
  /// Breaks very long lines before they reach the Markdown parser.
  ///
  /// Upstream `markdown` has two spots that spend quadratic time on a long
  /// run without whitespace (the GFM alert block regex `>?\s?(.*)*` and the
  /// inline plain-text syntax `[ \tA-Za-z0-9]*[A-Za-z0-9](?=\s)`, whose
  /// greedy backtrack is O(n^2) when no whitespace ever follows the run), so
  /// a single very long URL or output line can freeze the transcript — which
  /// reads as a crash when opening the session. A zero-width no-break space
  /// (U+FEFF) terminates each bounded run: it satisfies `(?=\s)` so the
  /// inline parser advances linearly, and it is invisible in the rendered
  /// text (unlike a real space, which would show up inside the blob).
  String _guardMarkdown(String text, {int maxLine = 1500}) {
    final lines = text.split('\n');
    if (!lines.any((l) => l.length > maxLine)) return text;
    final out = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.length <= maxLine) {
        out.write(line);
      } else {
        var j = 0;
        while (j < line.length) {
          final end = (j + maxLine).clamp(0, line.length);
          out.write(line.substring(j, end));
          j = end;
          if (j < line.length) out.write('\uFEFF');
        }
      }
      if (i < lines.length - 1) out.write('\n');
    }
    return out.toString();
  }

  void loadInflight(ResumedTurn? inflight, String? queued) {
    if (inflight != null && !inflight.isEmpty) {
      if (inflight.prompt.isNotEmpty) {
        markdown.append(
          '\n\n---\n\n**You:** ${_guardMarkdown(inflight.prompt)}\n\n',
        );
      }
      if (inflight.answerSoFar.isNotEmpty) {
        markdown.append(_guardMarkdown(inflight.answerSoFar));
      }
      if (inflight.streaming) {
        streaming = true;
        // The clock starts now, not at the turn's real start: the server
        // reports started_at but this client cannot trust its own clock
        // against the server's, and a negative or wildly wrong elapsed time
        // is worse than one that undercounts.
        _beginTurn();
        if (inflight.answerSoFar.isNotEmpty) answerStarted = true;
        _startIdleTick();
      }
    }
    // Deliberately *not* in the transcript. A queued prompt has not been
    // answered yet, and writing it after the partial answer means the next
    // delta lands below it, splitting the answer in half. It belongs beside
    // the composer, as a note about what happens next.
    queuedPrompt = (queued == null || queued.isEmpty) ? null : queued;
    notifyListeners();
  }

  /// Rebuilds the transcript from a resumed session, thinking included.
  ///
  /// The server keeps each assistant message's reasoning, and this used to
  /// pour all of it into one session-wide buffer that nothing rendered — so
  /// leaving a conversation and coming back lost every thinking block in it.
  /// Each one is now restored as its own turn, anchored under the question it
  /// answered, exactly where it would have appeared live.
  void loadHistory(List<AgentMessage> messages) {
    // Entries that belong above the next answer — reasoning and tool calls
    // both. Held open rather than flushed per message, because one exchange
    // produces several rows: think, call a tool, read its result, answer.
    Turn? pending;

    Turn openTurn() =>
        pending ??= Turn(anchorBlock: markdown.settledBlockCount - 1);

    for (final m in messages) {
      // A model switch is stored with `role: "user"` for provider-compatibility
      // reasons and is not something the user said; the adapter has already
      // sorted that out. Rendered as an italic aside: it still explains why
      // the answers after it may differ, without claiming to be a question.
      if (m.role == MessageRole.system) {
        if (m.text.trim().isNotEmpty) {
          markdown.append('*${_guardMarkdown(_systemNoteText(m.text))}*\n\n');
        }
        continue;
      }

      // What a tool printed, completing the call the agent asked for.
      if (m.role == MessageRole.tool) {
        final call = m.toolCall;
        if (call == null) continue;
        final existing = tools[m.toolCallId];
        tools[m.toolCallId] = existing == null
            ? call
            : existing.completed(
                durationSeconds: 0,
                args: existing.args,
                output: call.output,
                error: call.error,
              );
        if (existing == null) openTurn().entries.add(ToolEntry(m.toolCallId));
        continue;
      }

      // The agent asking for a tool. No text of its own — the row *is* the
      // call — so it is registered and shown rather than skipped as empty.
      final requested = m.toolCall;
      if (requested != null && m.role == MessageRole.assistant) {
        tools[m.toolCallId] = requested;
        openTurn().entries.add(ToolEntry(m.toolCallId));
        continue;
      }

      final reasoning = m.reasoning?.trim() ?? '';
      if (reasoning.isNotEmpty) {
        openTurn().entries.add(ThinkingSegment.restored(reasoning));
      }

      final text = m.text.trim();
      if (text.isEmpty) continue;

      final isUser = m.role == MessageRole.user;
      markdown.append(
        isUser
            ? '**You:** ${_guardMarkdown(m.text)}\n\n'
            : '${_guardMarkdown(m.text)}\n\n',
      );

      // Closed by the text it belongs above: everything gathered since the
      // last one renders between whatever came before and this answer.
      if (pending != null) {
        turns.add(pending!);
        pending = null;
      }
    }
    if (pending != null) turns.add(pending!);
    historyLoaded = true;
    notifyListeners();
  }

  /// Strips the server's `[System: … ]` wrapper and the instruction addressed
  /// to the model.
  ///
  /// The marker is written for the model to read, so it ends with a sentence
  /// telling it how to behave — of no use to a person, and the longest part of
  /// the line. What is left is the fact: which model is answering from here on.
  static String _systemNoteText(String raw) {
    var s = raw.trim();
    // Tail first: cutting the instruction takes the closing bracket with it,
    // so a bracket test that ran earlier would have to hold for the *whole*
    // marker. On the live server it did not — a row came back without its
    // closing bracket and kept its "[System:" prefix on screen. Each
    // delimiter is now removed on its own evidence.
    const tail = 'From this point forward';
    final cut = s.indexOf(tail);
    if (cut > 0) s = s.substring(0, cut).trim();
    if (s.startsWith('[')) s = s.substring(1);
    if (s.endsWith(']')) s = s.substring(0, s.length - 1);
    if (s.startsWith('System:')) s = s.substring('System:'.length);
    return s.trim();
  }

  void appendLocalPrompt(
    String text, {
    List<Attachment> attachments = const [],
  }) {
    final buffer = StringBuffer();
    buffer.write('\n\n---\n\n**You:** ');
    final cleanText = text.trim().replaceAll(RegExp(r'\n{2,}'), '\n');
    if (cleanText.isNotEmpty) {
      buffer.write('${_guardMarkdown(cleanText)}\n');
    }
    for (final a in attachments) {
      if (a.isImage) {
        // A reference, not the bytes: base64 in the transcript cost 1.37x the
        // file size in a string retained for the life of the session and
        // copied by everything that touched it. See [TranscriptBlobStore].
        final ref = blobs.put(
          TranscriptBlob(name: a.name, bytes: a.bytes, mimeType: a.mimeType),
        );
        buffer.write('![${a.name}]($ref)\n');
      } else {
        buffer.write('📎 `${a.name}`\n');
      }
    }
    buffer.write('\n');
    markdown.append(buffer.toString());
    streaming = true;
    lastError = null;
    _beginTurn();
    _startIdleTick();
    notifyListeners();
  }

  /// Applies one event from the backend. Caller guarantees it belongs here.
  void handle(AgentEvent event) {
    lastActivity = DateTime.now();
    switch (event) {
      case TextDelta(:final text):
        deltaCount++;
        if (!answerStarted) {
          // First answer token ends the thinking phase and freezes its clock.
          answerStarted = true;
          // Where this turn's answer begins, so a correction can replace it
          // without taking the conversation above it as well. Only the offset
          // is needed, and building the transcript to measure it allocated a
          // copy of the whole conversation on the first token of every turn.
          _answerStartsAt = markdown.textLength;
          statusLine = '';
          _closeSegment();
          if (thinkingStartedAt != null) {
            thinkingDuration = DateTime.now().difference(thinkingStartedAt!);
            thinkingStartedAt = null;
          }
          notifyListeners();
        }
        // The markdown controller drives its own view directly; this only
        // paces the surrounding chrome (counters, reasoning size).
        markdown.append(_guardMarkdown(text));
        _notifyStatsSoon();

      // The accumulated answer disagreed with the server's, so the server's
      // wins — but only for this turn.
      //
      // The renderer can be appended to or emptied and nothing else, so a
      // naive correction empties it and takes the whole conversation above
      // with it: an hour of exchange lost to one divergent snapshot, which is
      // a far worse outcome than the drift it was fixing. Rebuilding from the
      // text up to where this turn's answer began keeps everything the server
      // is not disputing. Only a backend that sends deltas and cumulative
      // snapshots both can raise this at all — Hermes never does.
      case TextReset(:final text):
        final before = _answerStartsAt;
        // Read once: each access rebuilds the transcript from its blocks.
        final current = markdown.text;
        final kept = before == null || before > current.length
            ? current
            : current.substring(0, before);
        markdown
          ..reset()
          ..append(kept + text);
        notifyListeners();

      // The server's status line, which exists precisely to explain a long
      // wait. Shown as chrome; never written into the reasoning trace.
      case StatusText(:final text):
        statusLine = text.trim();
        _notifyLiveSoon();

      case ReasoningDelta(:final text):
        // Reasoning can arrive before the turn starts, so this is where a turn
        // that begins with a long think actually starts as far as the UI is
        // concerned.
        if (thinkingStartedAt == null && !answerStarted) _beginTurn();
        reasoning.write(text);
        _reasoningSegment().text.write(text);
        _notifyLiveSoon();

      // Only when the turn produced no streamed reasoning: on models that emit
      // both, this block restates the deltas and appending it would double the
      // trace. On models that emit only this, it is the entire trace.
      case ReasoningBlock(:final text):
        if (text.isEmpty || reasoning.isNotEmpty) return;
        if (thinkingStartedAt == null && !answerStarted) _beginTurn();
        reasoning.write(text);
        _reasoningSegment().text.write(text);
        notifyListeners();

      case PromptExpired(:final id):
        // The server stopped waiting. Leaving the banner up would offer an
        // answer that can no longer land.
        prompts.removeWhere((p) => p.id.value == id.value);
        notifyListeners();

      // An approval gates the whole session and renders beside the composer;
      // the other kinds render inside the turn that asked them, so they are
      // kept apart rather than filtered at every read.
      case PromptRaised(:final prompt)
          when prompt.kind == AgentPromptKind.approval:
        approvals.add(prompt);
        notifyListeners();

      case PromptRaised(:final prompt):
        prompts.add(prompt);
        // Also in the turn, in the order it was asked. A question closes the
        // open thinking segment for the same reason a tool call does: the model
        // stopped reasoning to ask something.
        _closeSegment();
        _currentTurn.add(PromptEntry(prompt));
        notifyListeners();

      case ToolPreparing(:final toolName):
        generatingTool = toolName;
        notifyListeners();

      case ToolStarted(:final toolId, :final call):
        generatingTool = null;
        _closeSegment();
        _currentTurn.add(ToolEntry(toolId));
        tools[toolId] = call;
        notifyListeners();

      case ToolFinished(:final toolId, :final call):
        // A completion whose start we never saw — a reconnect landing
        // mid-tool, or a turn resumed after the fact — still has to appear.
        // Keying the timeline off the start alone would silently drop it.
        if (!timeline.any((e) => e is ToolEntry && e.toolId == toolId)) {
          _closeSegment();
          _currentTurn.add(ToolEntry(toolId));
        }
        tools[toolId] = call;
        notifyListeners();

      // A tool printing as it runs. Kept, because for the calls worth
      // watching — a build, a long grep — the wait *is* when somebody is
      // watching, and an empty row until it finishes shows nothing for
      // exactly as long as it matters. Hermes never raises this.
      case ToolProgress(:final toolId, :final text):
        final running = tools[toolId];
        if (running != null && !running.done) {
          tools[toolId] = running.appending(text);
          _notifyLiveSoon();
        }

      case TurnStarted():
        streaming = true;
        _beginTurn();
        _startIdleTick();
        notifyListeners();

      case TurnFinished():
        streaming = false;
        generatingTool = null;
        _endTurn();
        _stopIdleTick();
        notifyListeners();

      case SessionChanged(:final session):
        // Merged, not replaced: an empty field in an update means "not
        // mentioned", not "cleared", so a title arriving on its own must not
        // blank the model. The two flags are the exception — a bool cannot
        // say "not mentioned" — so only an update that names the posture may
        // move them, or a bare title would report a session that never asks
        // as one that does.
        final posture = session.approvalMode.isEmpty && !session.unattended
            ? _info
            : session;
        _info = _info
            .mergedWith(session)
            .copyWith(unattended: posture.unattended, warning: posture.warning);
        notifyListeners();

      // Someone else, talking to the same agent. Written into the transcript
      // as it arrives rather than waiting for a reload, because a
      // conversation that shows only this client's half of itself is a
      // conversation with holes in it.
      case MessageAppended(:final message):
        if (message.text.trim().isNotEmpty) {
          markdown.append(
            message.role == MessageRole.user
                ? '\n\n---\n\n**You:** ${_guardMarkdown(message.text)}\n\n'
                : '${_guardMarkdown(message.text)}\n\n',
          );
          notifyListeners();
        }

      // A note from the backend that the domain has no concept for. Nothing
      // to show yet, and deliberately not switched on by kind.
      case BackendNotice():
        break;
    }
  }

  /// The open thinking segment, or a new one.
  ///
  /// A new segment whenever the previous one was closed by a tool call:
  /// "thought, ran something, thought again" is three entries, not one.
  ThinkingSegment _reasoningSegment() {
    final open = _openSegment;
    if (open != null) return open;
    final segment = ThinkingSegment(DateTime.now());
    _currentTurn.add(segment);
    return segment;
  }

  void removePrompt(AgentPrompt prompt) {
    prompts.remove(prompt);
    notifyListeners();
  }

  void removeApproval(AgentPrompt prompt) {
    approvals.remove(prompt);
    notifyListeners();
  }

  void setError(String message) {
    lastError = message;
    streaming = false;
    _endTurn();
    _stopIdleTick();
    notifyListeners();
  }

  /// Lets [Workspace] publish a change it made to this console's fields.
  void notify() => notifyListeners();

  /// A control-plane call can outlive the console that started it — a slow or
  /// hung method still completes eventually, and its handler then notifies.
  /// After dispose that throws, taking the app down for what is really just a
  /// late reply nobody is waiting for.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  void clearError() {
    if (lastError == null) return;
    lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _statsTick?.cancel();
    _liveTick?.cancel();
    _stopIdleTick();
    _ambientIdle?.cancel();
    blobs.clear();
    Materials.ambientPaused.value = false;
    markdown.scrollController.removeListener(_pauseAmbientDuringScroll);
    markdown.dispose();
    super.dispose();
  }
}

/// Owns the connection and every open session.
class Workspace extends ChangeNotifier {
  /// The Hermes workspace: a gateway, wrapped in the adapter for it.
  ///
  /// Kept as the unnamed constructor because it is what the whole test suite
  /// builds, and because Hermes is the backend with the extra twenty methods
  /// that still need the raw client.
  Workspace(HermesGateway gateway, {AgentBackend? backend})
    : this.forBackend(backend ?? HermesBackend(gateway), gateway: gateway);

  /// A workspace over any backend.
  ///
  /// [gateway] is Hermes' and only Hermes'. It is here because the seven
  /// feature panels talk to the raw client directly and always did — they are
  /// gated on a [Capability] rather than squeezed through the core interface,
  /// which is the whole point of a narrow core. A backend that is not Hermes
  /// passes nothing and those surfaces are not built.
  Workspace.forBackend(this.backend, {HermesGateway? gateway})
    : _gateway = gateway {
    // Hermes-only, and the one frame still read off the raw stream: see
    // [_dispatch].
    _events = gateway?.events.listen(_dispatch);
    // Sessions changing anywhere, not only the ones open here. A session
    // started on a phone or finished by a scheduled job reaches the sidebar
    // through this and nothing else.
    _index = backend.sessionUpdates.listen(_onSessionUpdate);
    _connection = backend.connection.listen((s) {
      final wasConnected = connection.isConnected;
      connection = s;
      notifyListeners();
      // A reconnect usually means the server process restarted, and a backend
      // only tracks sessions live in *its* process. Every console we hold was
      // opened against the old one, so without this the UI reads "connected"
      // while every prompt fails with `session not found`.
      if (!wasConnected && s.isConnected) unawaited(_reactivateOpenSessions());
    });
  }

  final HermesGateway? _gateway;

  /// The Hermes client, for the surfaces only Hermes has.
  ///
  /// Every caller is behind a [Capability] this backend does not declare
  /// unless there is one, so reaching this on another backend means a gate is
  /// missing — which is worth saying out loud rather than failing as a null.
  HermesGateway get gateway =>
      _gateway ??
      (throw StateError(
        'This backend has no Hermes gateway. A surface that needs one must be '
        'gated on a Capability that ${backend.id} does not declare.',
      ));

  /// The Hermes control-plane address, or null on a backend that has no
  /// Hermes gateway (OpenClaw). Surfaces that merely *show* where the server
  /// is — the sidebar profile row — read this instead of [gateway], so a
  /// non-Hermes tab renders instead of throwing.
  String? get gatewayAddress => _gateway?.endpoint.toString();

  /// Where every conversation goes.
  ///
  /// Not disposed here: the backend and its socket are owned by whoever built
  /// them, and disposing would close a connection the connect screen still
  /// holds.
  final AgentBackend backend;

  /// Whether a surface should be built at all. See [Capability].
  bool supports(Capability capability) => backend.supports(capability);

  /// The models this backend can answer with.
  ///
  /// Empty on a backend without [Capability.modelSwitching] rather than an
  /// error, because a caller that ignored the capability would have to handle
  /// an empty list anyway.
  Future<List<AgentModel>> models(String sessionId) async {
    if (!supports(Capability.modelSwitching)) return const [];
    final handle = _handles[sessionId];
    if (handle == null) return const [];
    try {
      return await backend.models(handle);
    } on AgentException catch (e) {
      _consoles[sessionId]?.setError('Models unavailable: ${e.detail}');
      return const [];
    }
  }

  StreamSubscription<GatewayEvent>? _events;
  late final StreamSubscription<AgentSession> _index;
  late final StreamSubscription<AgentConnection> _connection;

  AgentConnection connection = const AgentConnection(AgentStatus.connected);

  bool _disposed = false;

  /// Same reason as [SessionConsole.notifyListeners]: an in-flight call
  /// outliving this workspace must not crash the app when it lands. Reproduced
  /// against a server whose `session.list` hung for 30 s while the user closed
  /// the window.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  List<AgentSession> sessions = const [];
  bool loadingSessions = false;
  String? sessionsError;

  /// Maximum number of inactive consoles kept resident in memory.
  static const _maxCachedConsoles = 8;
  final List<String> _consoleAccessOrder = [];

  void _touchConsole(String id) {
    _consoleAccessOrder.remove(id);
    _consoleAccessOrder.add(id);
    _evictExcessConsoles();
  }

  void _evictExcessConsoles() {
    while (_consoles.length > _maxCachedConsoles) {
      String? evictId;
      for (final id in _consoleAccessOrder) {
        if (id == activeId) continue;
        final console = _consoles[id];
        if (console == null) continue;
        if (console.streaming) continue;
        if (unread.contains(id)) continue;
        if (console.prompts.isNotEmpty) continue;
        evictId = id;
        break;
      }
      if (evictId == null) break;
      _consoleAccessOrder.remove(evictId);
      final console = _consoles.remove(evictId);
      final handle = _handles.remove(evictId);
      if (handle != null) {
        _liveToPersisted.remove(handle.wireId);
      }
      unawaited(
        _sessionEvents.remove(evictId)?.cancel() ?? Future<void>.value(),
      );
      console?.dispose();
    }
  }

  /// Keyed by persisted id — that is what the sidebar and the caller hold.
  final Map<String, SessionConsole> _consoles = {};

  /// Live handle → persisted id, for routing inbound events.
  final Map<String, String> _liveToPersisted = {};

  /// The open handle for each session, keyed by durable id.
  ///
  /// The handle is what every backend call takes, and it is opaque — the
  /// workspace never reads inside one. Held here rather than on the console
  /// because a console is state the UI listens to, and a handle is a
  /// reference the backend owns.
  final Map<String, SessionHandle> _handles = {};

  /// One event subscription per open session, cancelled when it is released.
  final Map<String, StreamSubscription<AgentEvent>> _sessionEvents = {};

  String? activeId;

  /// Whether the shell yet knows what to show.
  ///
  /// `session.list` and then `session.resume` are two round trips, and for
  /// their duration there is no console. Treating that as "no session open"
  /// put the new-session screen in front of the user on every single connect,
  /// for as long as the server took to answer — an invitation to start over,
  /// shown to someone whose conversation was already on its way in. Nothing
  /// offers a new session until this is true.
  bool arrived = false;

  SessionConsole? get active => activeId == null ? null : _consoles[activeId];
  SessionConsole? consoleFor(String id) => _consoles[id];

  /// Sessions with output the user has not looked at yet.
  final Set<String> unread = {};

  /// Slash commands, fetched once — the catalog is ~30 KB.
  List<SlashCommand> commands = const [];

  Future<void> loadCommands() async {
    if (commands.isNotEmpty) return;
    // Hermes-only, and quietly so: a backend without a catalog simply has no
    // completions to offer, which is the same outcome as a catalog that fails
    // to load.
    if (_gateway == null) return;
    try {
      commands = await gateway.slashCommands();
      notifyListeners();
    } catch (_) {
      // A missing catalog is not worth surfacing; the composer just won't
      // offer completions.
    }
  }

  /// Re-opens already-open sessions after a reconnect.
  ///
  /// For the side effect only — the transcript the backend hands back is
  /// discarded, because the console already holds it and loading it again
  /// would duplicate the whole conversation. What is needed is the fresh
  /// handle and, on a backend that subscribes per session, the subscription:
  /// a restarted gateway remembers neither.
  Future<void> _reactivateOpenSessions() async {
    for (final id in _consoles.keys.toList()) {
      final console = _consoles[id];
      if (console == null || !console.historyLoaded) continue;
      try {
        final handle = await backend.open(id);
        // The restarted backend mints a fresh handle; the old one is dead.
        _liveToPersisted.remove(console.liveId);
        _handles[id] = handle;
        console.liveId = handle.wireId;
        _liveToPersisted[handle.wireId] = id;
        // Not awaited — see [_adopt]. Awaiting a broadcast subscription's
        // cancel here is what deadlocked the reopen path once already.
        unawaited(_sessionEvents.remove(id)?.cancel() ?? Future<void>.value());
        _sessionEvents[id] = backend
            .events(handle)
            .listen((e) => _onAgentEvent(id, e));
        console.streaming = (await backend.opened(handle)).session.running;
        console.clearError();
      } catch (e) {
        console.setError('Session unavailable after reconnect: ${_reason(e)}');
      }
    }
    unawaited(refreshSessions());
  }

  /// The one thing still read off the raw Hermes stream.
  ///
  /// `terminal.read.request` asks for *this client's* terminal buffer. It is
  /// not session-scoped, it has no domain shape, and it is Hermes-only — so
  /// it stays here rather than being forced through the seam. Everything else
  /// arrives through [_onAgentEvent].
  void _dispatch(GatewayEvent event) {
    if (event.isTerminalReadRequest) unawaited(_answerTerminalRead(event));
  }

  /// One session's events, already normalised by its backend.
  ///
  /// Subscribed per open session rather than fanned out from one firehose,
  /// because that is the shape the interface has and the shape OpenClaw
  /// requires — it streams only what was subscribed to. The adapter is also
  /// where a raised question is *remembered*, so routing events around it
  /// left [respondToPrompt] with nothing to answer against and every answer
  /// failing as `notFound`.
  void _onAgentEvent(String persistedId, AgentEvent event) {
    final console = _consoles[persistedId];
    if (console == null) return;
    console.handle(event);
    // The sidebar shows the same session the header does. A title derived
    // while the conversation is happening reached one and not the other, so a
    // new session kept reading "(untitled)" in the list it was selected from.
    if (event is SessionChanged) _mergeIntoList(persistedId, event.session);
    final isActive = persistedId == activeId;
    _feedback(event, isActive: isActive);
    if (isActive) return;
    // Worth a badge: the agent said something, or it is waiting on an answer.
    final notable = event is TextDelta || event is PromptRaised;
    if (notable && unread.add(persistedId)) notifyListeners();
  }

  /// A session changed somewhere. Fold it in, or add it.
  ///
  /// A row this client has never seen is inserted rather than ignored: that
  /// is the case the index subscription exists for, and refusing it would
  /// leave a conversation started elsewhere invisible until the next refresh.
  void _onSessionUpdate(AgentSession update) {
    if (_disposed) return;
    if (sessions.any((s) => s.id == update.id)) {
      _mergeIntoList(update.id, update);
      return;
    }
    // Only once it has something to show for itself. The first frame for a
    // brand-new session names neither a title nor a preview, and a row that
    // reads as nothing at all is worse than one that arrives a moment later.
    if (update.label.trim().isEmpty || update.label == update.id) return;
    sessions = [update, ...sessions];
    notifyListeners();
  }

  /// Folds a live update into the row the sidebar draws.
  ///
  /// Merged, not replaced: an event names the fields that moved, and taking
  /// the whole object would blank the preview every time a model resolved.
  void _mergeIntoList(String id, AgentSession update) {
    final index = sessions.indexWhere((s) => s.id == id);
    if (index == -1) return;
    final before = sessions[index];
    final merged = before.mergedWith(update);
    // Everything a row draws, not just the title. A preview that changed
    // while the label did not is the ordinary case — it is what happens every
    // time the conversation moves — and comparing only the title left the
    // sidebar showing the message before last.
    if (merged.label == before.label &&
        merged.preview == before.preview &&
        merged.running == before.running &&
        merged.model == before.model &&
        merged.updatedAt == before.updatedAt) {
      return;
    }
    sessions = [...sessions]..[index] = merged;
    notifyListeners();
  }

  /// Touch feedback for something the *server* did.
  ///
  /// Here rather than in [SessionConsole] for two reasons. A console is state:
  /// it has no business reaching for a platform channel, and doing so made
  /// every plain `test()` that feeds it events fail on a missing binding.
  /// More importantly, a console does not know whether anyone is looking at
  /// it — so a tool finishing in a session left running in the background
  /// buzzed the phone about work the user had walked away from.
  void _feedback(AgentEvent event, {required bool isActive}) {
    // A blocked agent is worth a pulse whichever session it came from.
    if (event is PromptRaised) {
      Haptics.needsAttention();
      return;
    }
    if (!isActive) return;
    if (event is ToolFinished) {
      event.call.failed ? Haptics.warn() : unawaited(Haptics.toolDone());
    }
  }

  /// Answers the agent's request for an in-app terminal buffer.
  ///
  /// Caduceus has no in-app terminal, and one would be the wrong thing anyway:
  /// it would run on *this* Mac while the agent works on the server. Not
  /// answering is worse than answering — the server parks the tool for 30 s
  /// and then returns empty regardless, so the agent waits half a minute to
  /// learn nothing. This says so immediately, in the JSON string the tool
  /// hands the agent verbatim.
  Future<void> _answerTerminalRead(GatewayEvent event) async {
    final id = event.requestId;
    if (id == null) return;
    try {
      await gateway.terminalReadRespond(
        requestId: id,
        text: jsonEncode({
          'lines': <String>[],
          'note':
              'This client (Caduceus) has no in-app terminal. Background '
              'processes started by tools are still visible through the '
              'process tools.',
        }),
      );
    } catch (_) {
      // The tool falls back to empty on its own; a failed courtesy answer is
      // not worth a banner.
    }
  }

  /// Persisted id → the gateway handle to address it with.
  String _live(String persistedId) =>
      _consoles[persistedId]?.liveId ?? persistedId;

  Future<void> refreshSessions() async {
    loadingSessions = true;
    sessionsError = null;
    notifyListeners();
    try {
      sessions = await backend.sessions();
    } catch (e) {
      sessionsError = _reason(e);
    } finally {
      loadingSessions = false;
      notifyListeners();
    }
  }

  /// Re-establishes a dead connection and refreshes the session list — the
  /// gentle ⌘R, not a force-reload that tears the transcript down.
  ///
  /// When the socket is already healthy this only refreshes the list; when it
  /// has dropped (disconnected, fatal) the backend reconnects, and the
  /// connection listener reactivates whatever sessions were open.
  Future<void> reconnect() async {
    if (_disposed) return;
    if (!connection.isConnected) {
      try {
        await backend.connect();
      } catch (_) {
        // Leave the existing error state visible; the refresh below is what
        // exposes whether the server came back.
      }
    }
    await refreshSessions();
  }

  /// Proves a socket is usable after the app returns from the background.
  ///
  /// A quiet socket can look connected while the operating system has already
  /// invalidated it. A protocol-level check distinguishes that half-open state
  /// from a healthy connection without tearing down a live turn unnecessarily.
  Future<void> resumeFromBackground() async {
    if (_disposed) return;
    final alive = await backend.verifyConnection();
    if (_disposed) return;
    if (!alive) {
      try {
        await backend.connect();
      } catch (_) {
        // The refresh below reports the failure; reconnect state is owned by
        // the backend and remains visible to the workspace listener.
      }
    }
    await refreshSessions();
  }

  /// Lands on the conversation the user was last in, rather than nothing.
  ///
  /// Connecting used to arrive at an empty screen offering a new session,
  /// which is the wrong default: almost nobody connects to start over, and the
  /// work in progress was one drawer tap away with no indication of which row
  /// held it.
  ///
  /// The first row is the right one to open, not the newest `started_at`:
  /// `session.list` is ordered by *last activity* server-side, so an old
  /// session used ten minutes ago sorts above one started yesterday and
  /// abandoned. The server also has `session.most_recent`, which applies the
  /// same ordering and deny-list — but it costs another round trip to learn
  /// what the list we just fetched already says.
  ///
  /// Does nothing if a session is already open, so a reconnect or a rebuild
  /// cannot yank the user out of what they are reading.
  Future<void> openMostRecent() async {
    await refreshSessions();
    if (activeId == null && sessions.isNotEmpty) {
      // Not simply `sessions.first`. Connecting to the gateway *creates a
      // session on the server* — verified by pointing a bare client with no
      // session calls at it and watching a new row appear, title-less and one
      // message long, timestamped to the second the socket opened. Ordered by
      // last activity, that shell is always first, so "open the most recent"
      // reliably opened a blank session the user had never seen: the same
      // empty screen this feature exists to avoid, wearing a session id.
      final resumable = sessions.where(_worthResuming);
      await open((resumable.isEmpty ? sessions : resumable).first.id);
    }
    arrived = true;
    notifyListeners();
  }

  /// Whether a session is a conversation rather than an empty shell.
  ///
  /// A title *or* more than one message. The server names a session once there
  /// is something to name, so a title alone is enough; and a session someone
  /// actually spoke in has a prompt and a reply. Both signals are needed —
  /// with only the title test, a real exchange the server has not titled yet
  /// would be skipped.
  ///
  /// If every session looks like a shell, [openMostRecent] opens one anyway.
  /// There is nothing better to offer, and refusing would leave a blank screen
  /// beside a list that plainly has rows in it.
  static bool _worthResuming(AgentSession s) =>
      s.title.trim().isNotEmpty || s.messageCount > 1;

  /// Opens a session, reusing the cached console when there is one.
  /// Re-resuming an already-open session would replay its transcript into a
  /// controller that already holds it, duplicating everything.
  Future<SessionConsole> open(String sessionId) async {
    unread.remove(sessionId);
    // There is a console from here on, whichever path got us here — including
    // the `--session` preset, which never goes through [openMostRecent].
    arrived = true;
    final cached = _consoles[sessionId];
    if (cached != null) {
      activeId = sessionId;
      _touchConsole(sessionId);
      notifyListeners();
      return cached;
    }

    final console = SessionConsole(persistedId: sessionId);
    // Seed from the list entry the user just tapped, so the heading says the
    // same thing the row did instead of falling back to the id.
    final listed = sessions.where((s) => s.id == sessionId);
    if (listed.isNotEmpty) console.title = listed.first.label;
    _consoles[sessionId] = console;
    _touchConsole(sessionId);
    activeId = sessionId;
    notifyListeners();

    try {
      await _adopt(console, await backend.open(sessionId));
    } on AgentException catch (e) {
      console.setError('Could not open session: ${e.detail}');
    } catch (e) {
      console.setError('Could not open session: ${_reason(e)}');
    }
    notifyListeners();
    return console;
  }

  /// Points a console at a freshly opened handle and fills it from the
  /// backend.
  ///
  /// Three calls rather than one, because the backend keeps them apart on
  /// purpose: the handle is the reference, `opened()` is what is *happening*
  /// (the model, the directory, a turn already running), and `history()` is
  /// what was *stored*. Merging them would force a backend that knows only
  /// one to invent the other.
  Future<void> _adopt(SessionConsole console, SessionHandle handle) async {
    final id = console.persistedId;
    _liveToPersisted.remove(console.liveId);
    _handles[id] = handle;
    console.liveId = handle.wireId;
    _liveToPersisted[handle.wireId] = id;

    // Not awaited. Cancelling a subscription is cleanup, and awaiting it here
    // deadlocks: the backend's per-session stream is a broadcast controller,
    // and the future `cancel()` hands back does not complete while the
    // controller is still live — so the reopen that follows never runs, and
    // `undo` hangs in a way indistinguishable from a dead connection.
    unawaited(_sessionEvents.remove(id)?.cancel() ?? Future<void>.value());

    final opened = await backend.opened(handle);
    console.applyInfo(opened.session);
    console.streaming = opened.session.running;
    if (backend.supports(Capability.history)) {
      console.loadHistory(await backend.history(handle));
    } else {
      // Said plainly rather than left looking like a conversation that lost
      // its history, which is what an empty transcript reads as.
      console.historyLoaded = true;
    }
    console.loadInflight(opened.inflight, opened.queuedPrompt);

    // Subscribed last, once the console holds what the server already had.
    // An event delivered while the transcript is still being rebuilt lands in
    // a console that is half a conversation behind, and the backend has been
    // buffering nothing in the meantime — Hermes pushes everything regardless
    // and OpenClaw's subscription is already open by this point.
    _sessionEvents[id] = backend
        .events(handle)
        .listen((e) => _onAgentEvent(id, e));
  }

  /// Rebuilds a console's transcript from the server.
  ///
  /// Needed after anything that rewrites history behind the client's back:
  /// `session.undo` drops the last exchange, `session.compress` replaces older
  /// messages with a summary. Neither emits events for what it removed, so the
  /// console keeps showing text the server no longer has — the user reads a
  /// conversation the agent cannot see.
  Future<void> reloadConsole(String sessionId) async {
    final console = _consoles[sessionId];
    if (console == null) return;
    try {
      console.resetTranscript();
      await _adopt(console, await backend.open(sessionId));
      console.clearError();
    } on AgentException catch (e) {
      console.setError('Could not reload the session: ${e.detail}');
    } catch (e) {
      console.setError('Could not reload the session: ${_reason(e)}');
    }
    notifyListeners();
  }

  Future<SessionConsole?> createSession() async {
    arrived = true;
    try {
      // Two ids again, and they are *not* the same — the handle carries both,
      // which is what it is for. The new session is born on the current one's
      // model when there is one: OpenClaw accepts it at create time with no
      // operator.admin (only switching a running session is admin-gated), and
      // Hermes has always accepted a starting model.
      final handle = await backend.create(model: _consoles[activeId]?.model);
      final console = SessionConsole(
        persistedId: handle.sessionId,
        liveId: handle.wireId,
      );
      console.historyLoaded = true;
      _consoles[handle.sessionId] = console;
      _touchConsole(handle.sessionId);
      await _adopt(console, handle);
      activeId = handle.sessionId;
      notifyListeners();
      unawaited(refreshSessions());
      return console;
    } on AgentException catch (e) {
      sessionsError = e.detail;
      notifyListeners();
      return null;
    } catch (e) {
      sessionsError = _reason(e);
      notifyListeners();
      return null;
    }
  }

  /// Submits a prompt.
  ///
  /// [queued] parks it behind a turn that is already running instead of
  /// failing. The alternative — quietly turning it into a steer — is how a
  /// message could disappear with no reply and no error: `session.steer`
  /// succeeds against an idle session and simply does nothing.
  Future<void> send(
    String sessionId,
    String text, {
    bool queued = false,
    List<Attachment> attachments = const [],
  }) async {
    final console = _consoles[sessionId];
    console?.appendLocalPrompt(text, attachments: attachments);
    final handle = _handles[sessionId];
    if (handle == null) {
      console?.setError('That session is not open.');
      return;
    }
    try {
      await backend.send(
        handle,
        text,
        // Minted here, by the caller, which is the whole point of the
        // parameter: a key generated inside the backend would be new on the
        // retry it exists to make safe.
        clientId: _idempotencyKey(sessionId),
        queued: queued,
        attachments: attachments,
      );
    } on AgentException catch (e) {
      console?.setError(e.detail.isEmpty ? '$e' : e.detail);
    } catch (e) {
      console?.setError(_reason(e));
    }
  }

  var _sendSeq = 0;

  /// An idempotency key for one user-initiated send.
  ///
  /// Stable for the message, not for the attempt: that is the distinction the
  /// key exists for, and it is why it is minted here rather than inside a
  /// backend that would regenerate it on every retry.
  String _idempotencyKey(String sessionId) => '$sessionId:${++_sendSeq}';

  /// Sends `/name arg` as a slash command rather than a prompt.
  Future<void> dispatchCommand(String sessionId, String raw) async {
    final trimmed = raw.trim();
    final space = trimmed.indexOf(' ');
    final name = space == -1 ? trimmed : trimmed.substring(0, space);
    final arg = space == -1 ? '' : trimmed.substring(space + 1).trim();
    final console = _consoles[sessionId];
    console?.appendLocalPrompt(trimmed);
    try {
      await gateway.commandDispatch(
        sessionId: console?.liveId ?? sessionId,
        name: name,
        arg: arg,
      );
    } catch (e) {
      console?.setError('${trimmed.split(' ').first} failed: ${_reason(e)}');
    }
  }

  Future<bool> deleteSession(String sessionId) async {
    try {
      await gateway.sessionDelete(sessionId);
      await _releaseSession(sessionId);
      _consoleAccessOrder.remove(sessionId);
      final removed = _consoles.remove(sessionId);
      if (removed != null) _liveToPersisted.remove(removed.liveId);
      removed?.dispose();
      unread.remove(sessionId);
      if (activeId == sessionId) activeId = null;
      await refreshSessions();
      return true;
    } catch (e) {
      sessionsError = 'Delete failed: ${_reason(e)}';
      notifyListeners();
      return false;
    }
  }

  Future<bool> renameSession(String sessionId, String title) async {
    try {
      await gateway.sessionTitle(_live(sessionId), title);
      _consoles[sessionId]?.title = title;
      _consoles[sessionId]?.notifyListeners();
      await refreshSessions();
      return true;
    } catch (e) {
      sessionsError = 'Rename failed: ${_reason(e)}';
      notifyListeners();
      return false;
    }
  }

  /// Token usage and context breakdown for a session.
  ///
  /// Both go through `_sess`, so they need the gateway handle — with the
  /// persisted id they fail 4001 and look broken.
  Future<AgentUsage?> sessionStats(String sessionId) async {
    final handle = _handles[sessionId];
    if (handle == null) return null;
    try {
      return await backend.usage(handle);
    } catch (e) {
      _consoles[sessionId]?.setError('Stats unavailable: ${_reason(e)}');
      return null;
    }
  }

  /// Model inventory for the picker, cached per session.
  ///
  /// `model.options` measured 3–7 seconds against the reference server and
  /// does not get faster on repeat, so every reopen paid the full cost while
  /// the user waited on a dialog that had not appeared yet. Cached here
  /// because the set of providers changes only when someone connects or
  /// disconnects one, both of which go through this class.
  final Map<String, ModelInventory> _modelCache = {};

  Future<ModelInventory?> modelInventory(
    String sessionId, {
    bool refresh = false,
  }) async {
    if (!refresh) {
      final cached = _modelCache[sessionId];
      if (cached != null) return cached;
    }
    try {
      final inventory = ModelInventory.fromJson(
        await gateway.modelOptionsFor(_live(sessionId), refresh: refresh),
      );
      _modelCache[sessionId] = inventory;
      return inventory;
    } catch (e) {
      _consoles[sessionId]?.setError('Model list failed: ${_reason(e)}');
      return null;
    }
  }

  Future<bool> setModel(
    String sessionId,
    String model, {
    String? provider,
  }) async {
    final handle = _handles[sessionId];
    if (handle == null) return false;
    try {
      await backend.selectModel(handle, model);
      _consoles[sessionId]?.model = model;
      // The cached inventory still names the old model as current, so
      // reopening the picker showed the tick beside the model you had just
      // switched away from — which reads as the switch not having worked.
      // Updated in place rather than dropped, because re-querying costs the
      // 3-7 seconds the cache exists to avoid.
      final cached = _modelCache[sessionId];
      if (cached != null) {
        _modelCache[sessionId] = cached.withCurrentModel(model);
      }
      notifyListeners();
      return true;
    } on AgentException catch (e) {
      _consoles[sessionId]?.setError('Model switch failed: ${e.detail}');
      return false;
    } catch (e) {
      _consoles[sessionId]?.setError('Model switch failed: ${_reason(e)}');
      return false;
    }
  }

  /// Stores a provider API key on the server and returns whether it worked.
  ///
  /// The key is the user's own, typed by them. It is passed through and never
  /// written to this client's storage or its transcript.
  Future<bool> connectProvider(
    String sessionId,
    String slug,
    String key,
  ) async {
    try {
      await gateway.modelSaveKey(slug: slug, apiKey: key);
      _modelCache.clear();
      return true;
    } catch (e) {
      // The message must not contain the key.
      _consoles[sessionId]?.setError('Could not save the key: ${_reason(e)}');
      return false;
    }
  }

  Future<bool> disconnectProvider(String sessionId, String slug) async {
    try {
      await gateway.modelDisconnect(slug);
      _modelCache.clear();
      return true;
    } catch (e) {
      _consoles[sessionId]?.setError('Disconnect failed: ${_reason(e)}');
      return false;
    }
  }

  /// Replaces the objective of a running turn, keeping the work so far.
  /// [steer] adds guidance instead; the two are not the same call.
  Future<void> redirect(String sessionId, String text) async {
    final console = _consoles[sessionId];
    try {
      await gateway.sessionRedirect(sessionId: _live(sessionId), text: text);
      console?.markdown.append('\n\n> **redirected:** $text\n\n');
    } catch (e) {
      console?.setError('Redirect failed: ${_reason(e)}');
    }
  }

  Future<void> compress(String sessionId, {String? focusTopic}) async {
    try {
      await gateway.sessionCompress(_live(sessionId), focusTopic: focusTopic);
      // The summary replaces older messages server-side and no event says so.
      await reloadConsole(sessionId);
    } catch (e) {
      _consoles[sessionId]?.setError('Compress failed: ${_reason(e)}');
    }
  }

  /// Redirects a turn that is already running, without discarding it.
  /// Distinct from interrupt, which stops it.
  Future<void> steer(String sessionId, String text) async {
    final console = _consoles[sessionId];
    try {
      await gateway.sessionSteer(_live(sessionId), text);
      console?.markdown.append('\n\n> **steering:** $text\n\n');
    } catch (e) {
      console?.setError('Steer failed: ${_reason(e)}');
    }
  }

  /// Forks a conversation. [count] is how many messages carry over.
  /// Forks a session, transcript and all, and returns the new one's id.
  Future<String?> branch(String sessionId) async {
    final handle = _handles[sessionId];
    if (handle == null) return null;
    try {
      final branched = await backend.branch(handle);
      // The backend opened it; adopt the console so the caller can switch
      // straight into it rather than reopening what was just created.
      final console = SessionConsole(
        persistedId: branched.sessionId,
        liveId: branched.wireId,
      );
      console.historyLoaded = true;
      _consoles[branched.sessionId] = console;
      _touchConsole(branched.sessionId);
      await _adopt(console, branched);
      unawaited(refreshSessions());
      return branched.sessionId;
    } on AgentException catch (e) {
      _consoles[sessionId]?.setError('Branch failed: ${e.detail}');
      return null;
    } catch (e) {
      _consoles[sessionId]?.setError('Branch failed: ${_reason(e)}');
      return null;
    }
  }

  Future<void> interrupt(String sessionId) async {
    try {
      final handle = _handles[sessionId];
      if (handle != null) await backend.interrupt(handle);
    } on AgentException catch (e) {
      _consoles[sessionId]?.setError('Interrupt failed: ${e.detail}');
    } catch (e) {
      _consoles[sessionId]?.setError('Interrupt failed: ${_reason(e)}');
    }
  }

  /// Removes the last exchange. Refused (4009) while a turn is running, which
  /// is deliberate on the server — interrupt first.
  Future<int?> undo(String sessionId) async {
    try {
      final r = await gateway.sessionUndo(_live(sessionId));
      final removed = (r['removed'] as num?)?.toInt() ?? 0;
      if (removed > 0) await reloadConsole(sessionId);
      return removed;
    } catch (e) {
      _consoles[sessionId]?.setError('Undo failed: ${_reason(e)}');
      return null;
    }
  }

  /// The server's own rendering of its configuration.
  ///
  /// Neither backend answers with a schema — Hermes prints what its CLI
  /// prints, OpenClaw hands back a redacted snapshot — so this is presented
  /// as facts rather than as something to build editors from. Behind
  /// [Capability.serverConfig].
  Future<List<ServerConfigSection>> serverConfig() => backend.serverConfig();

  /// What the server will reload, behind [Capability.serverMaintenance].
  Future<List<String>> reloadTargets(String sessionId) async {
    final handle = _handles[sessionId];
    return handle == null ? const [] : backend.reloadTargets(handle);
  }

  /// Reloads [target] on the server. Throws, rather than swallowing: the
  /// caller put a confirmation in front of this and has somewhere to say so.
  Future<void> reloadServer(String sessionId, String target) async {
    final handle = _handles[sessionId];
    if (handle == null) {
      throw AgentException(
        AgentFailure.notFound,
        detail: 'That session is not open.',
      );
    }
    await backend.reloadServer(handle, target);
  }

  /// What the agent has left running in this session.
  Future<List<AgentTask>> tasks(String sessionId) async {
    final handle = _handles[sessionId];
    return handle == null ? const [] : backend.tasks(handle);
  }

  /// Stops one. Throws rather than swallowing: the caller confirmed first and
  /// has somewhere to say what went wrong.
  Future<void> stopTask(String sessionId, String id) async {
    final handle = _handles[sessionId];
    if (handle == null) {
      throw AgentException(
        AgentFailure.notFound,
        detail: 'That session is not open.',
      );
    }
    await backend.stopTask(handle, id);
  }

  /// Stops everything on the server. Behind [Capability.serverMaintenance],
  /// because it reaches sessions this client has never opened.
  Future<void> stopAllTasks() => backend.stopAllTasks();

  /// What the connected agent remembers. Behind [Capability.memoryRead].
  ///
  /// One backend's worth. The bridge's unified view asks each connected
  /// backend in turn and groups by [MemoryEntry.origin] — this deliberately
  /// does not merge, because merging is phase 2 and doing it here would make
  /// the read path own a decision the person is supposed to make.
  /// The ledger's own copy of everything every agent remembers.
  ///
  /// Held here rather than made per-panel because recording is a side effect
  /// of *reading*: the app connects to one backend at a time, so the only
  /// chance to learn what a server remembers is while it is the connected one.
  final ledger = MemoryLedger();

  /// What the connected agent remembers, recorded on the way past.
  ///
  /// Behind [Capability.memoryRead]. The recording is what lets a later view
  /// show this backend while a *different* one is connected — see
  /// [MemoryLedger] for why that is the mechanism and not an optimisation.
  Future<List<MemoryEntry>> memory() async {
    final entries = await backend.memory();
    // Best effort. A ledger that cannot write is a stale cache, which is a
    // far better outcome than a memory panel that will not open.
    try {
      await ledger.record(backend.id, entries);
    } on Object {
      // Deliberately swallowed.
    }
    return entries;
  }

  /// What the connected agent can do — the skill library, for the bridge.
  ///
  /// Behind [Capability.skills]. See [AgentBackend.skillLibrary].
  Future<List<SkillEntry>> skillLibrary() => backend.skillLibrary();

  /// Everything both agents can do, side by side.
  ///
  /// [reachOut] opens the *other* saved servers so their skill libraries are
  /// read now rather than never (there is no skill ledger — a library is
  /// live inventory, re-fetched per open). The same [MemoryPeers] rules
  /// apply as for [memoryView]: already-open tabs are asked first, and the
  /// pool is told not to reopen the saved servers behind them.
  Future<SkillLibraryView> skillView({
    bool reachOut = false,
    MemoryPeers peers = MemoryPeers.none,
  }) async {
    final live = <String, List<SkillEntry>>{};
    final unreachable = <String, String>{};

    if (supports(Capability.skills)) {
      try {
        live[backend.id] = await backend.skillLibrary();
      } on Object catch (e) {
        unreachable[backend.id] = _peerFailure(e);
      }
    }

    if (reachOut) {
      for (final other in peers.backends.values) {
        if (other.id == backend.id) continue;
        if (live.containsKey(other.id)) continue;
        if (!other.supports(Capability.skills)) continue;
        try {
          live[other.id] = await other.skillLibrary();
        } on Object catch (e) {
          unreachable[other.id] = _peerFailure(e);
        }
      }

      final pool = BackendPool();
      try {
        pool.adopt(connectionId ?? backend.id, backend);
        await pool.connectAll(
          except: {?connectionId, ...peers.openConnectionIds},
        );
        for (final pooled in pool.usable) {
          final other = pooled.backend!;
          if (other.id == backend.id) continue;
          if (live.containsKey(other.id)) continue;
          if (!other.supports(Capability.skills)) continue;
          try {
            live[other.id] = await other.skillLibrary();
          } on Object catch (e) {
            unreachable[other.id] = _peerFailure(e);
          }
        }
        unreachable.addAll(pool.failures);
      } finally {
        await pool.dispose();
      }
    }

    return SkillLibraryView(
      clusters: clusterSkills([for (final list in live.values) ...list]),
      liveBackendIds: live.keys.toSet(),
      unreachable: unreachable,
    );
  }

  /// What a workspace document held before this app overwrote it.
  ///
  /// The undo for phase 5's one destructive operation.
  Future<String?> previousPersona(String name) =>
      ledger.overwriteFor(backend.id, name);

  /// Puts back what was there before the last push of [name].
  ///
  /// Goes through [applyMemory] rather than writing directly, so the restore
  /// is guarded by the same staleness check as the push that caused it — if
  /// the agent has rewritten its own persona since, putting the old one back
  /// is as destructive as the push was.
  Future<MemoryWriteResult> undoPersona(String name) async {
    final previous = await previousPersona(name);
    if (previous == null) {
      throw AgentException(
        AgentFailure.notFound,
        detail: 'There is no earlier version of $name to put back.',
      );
    }
    final result = await applyMemory([
      MemoryChange(
        MemoryOp.update,
        MemoryEntry(
          id: '${backend.id}:$name',
          kind: MemoryKind.persona,
          title: name,
          text: previous,
          origin: MemoryOrigin(backendId: backend.id, nativeId: name),
        ),
      ),
    ]);
    if (result.applied.isNotEmpty) {
      await ledger.clearOverwrite(backend.id, name);
    }
    return result;
  }

  /// Which memory operations the connected agent can perform.
  Set<MemoryOp> get memoryOps => backend.supportedMemoryOps;

  /// Pushes [changes] to the connected agent.
  ///
  /// Behind [Capability.memoryWrite]. Re-reads afterwards so the ledger holds
  /// what the server now has rather than what the app hoped it would: a push
  /// that was partly refused leaves the two disagreeing, and the disagreement
  /// is exactly what the next diff should show.
  Future<MemoryWriteResult> applyMemory(List<MemoryChange> changes) async {
    // Persona documents are whole-file writes, so what they replace is kept.
    // Wired here rather than inside the adapter, which depends on nothing
    // above the seam and should keep it that way.
    if (backend case final ClawBackend claw) {
      claw.onOverwrite = ledger.recordOverwrite;
    }
    final result = await backend.applyMemory(changes);
    if (result.applied.isNotEmpty) {
      try {
        await ledger.record(backend.id, await backend.memory());
      } on Object {
        // A re-read that fails leaves a stale snapshot, which the source chip
        // already labels with its age.
      }
    }
    return result;
  }

  // -- shared knowledge base ------------------------------------------------

  /// Everything shared and every agent's state against it.
  ///
  /// `SHARED_MEMORY.md`. The facts come from the physical store on this
  /// device; the states come from [detectFactStates] over the same view the
  /// memory panel shows — so the detector never knows more or less than the
  /// bridge does, and a server the bridge could not ask is `unverifiable`
  /// here, never `missing`.
  Future<SharedMemoryView> sharedMemoryView({
    bool reachOut = false,
    MemoryPeers peers = MemoryPeers.none,
  }) async {
    final view = await memoryView(reachOut: reachOut, peers: peers);
    final facts = await ledger.sharedFacts();
    final statesByFact = <String, FactStates>{};
    for (final fact in facts) {
      statesByFact[fact.id] = detectFactStates(
        fact: fact,
        clusters: view.clusters,
        knownBackends: view.backends,
        unreachable: view.unreachable,
        anchors: await ledger.anchorsFor(fact.id),
      );
    }
    return SharedMemoryView(
      facts: facts,
      statesByFact: statesByFact,
      sources: view.sources,
      liveBackendIds: view.liveBackendIds,
      unreachable: view.unreachable,
    );
  }

  /// Syncs [fact] to [target], then anchors whatever actually landed.
  ///
  /// OpenClaw takes the memory through `applyMemory` (block splice, R3);
  /// Hermes has no create RPC, so it is asked through its agent and the
  /// landing node is read back. Either way the anchor records reality —
  /// [SharedSyncResult.nativeId] and the landed fingerprint — not the text
  /// this client wished for.
  Future<SharedSyncResult> syncSharedFact(
    SharedFact fact,
    AgentBackend target,
  ) async {
    if (target is ClawBackend) {
      final result = await target.applyMemory([
        MemoryChange(
          MemoryOp.add,
          MemoryEntry(
            id: 'shared:${fact.id}',
            kind: fact.kind,
            title: fact.title,
            text: fact.text,
            origin: MemoryOrigin(backendId: target.id, nativeId: ''),
          ),
        ),
      ]);
      if (result.refused.isNotEmpty) {
        return SharedSyncResult.refused(target.id, result.refused.first.detail);
      }
    } else if (target is HermesBackend) {
      final landed = await target.syncMemoryViaAgent(fact.text);
      if (landed.nativeId == null) {
        return SharedSyncResult.refused(target.id, landed.detail);
      }
      await ledger.recordAnchor(
        SyncAnchor(
          factId: fact.id,
          backendId: target.id,
          nativeId: landed.nativeId!,
          fingerprint: MemoryFingerprint.of(
            landed.landedText ?? fact.text,
          ).value,
          syncedAt: DateTime.now(),
        ),
      );
      return SharedSyncResult(
        backendId: target.id,
        ok: true,
        nativeId: landed.nativeId,
        detail: '',
      );
    } else {
      return SharedSyncResult.refused(target.id, 'Unsupported backend.');
    }

    // OpenClaw: read back to find the entry the block actually created, so
    // the anchor points at reality and later drift is measured against it.
    try {
      final entries = await target.memory();
      final wanted = MemoryFingerprint.of(fact.text);
      for (final entry in entries) {
        if (entry.origin.backendId != target.id) continue;
        if (wanted.matches(MemoryFingerprint.of(entry.text))) {
          await ledger.recordAnchor(
            SyncAnchor(
              factId: fact.id,
              backendId: target.id,
              nativeId: entry.origin.nativeId,
              fingerprint: wanted.value,
              syncedAt: DateTime.now(),
            ),
          );
          return SharedSyncResult(
            backendId: target.id,
            ok: true,
            nativeId: entry.origin.nativeId,
            detail: '',
          );
        }
      }
      return SharedSyncResult(
        backendId: target.id,
        ok: false,
        detail:
            'OpenClaw accepted the write but the entry was not found '
            'on read-back.',
      );
    } on Object catch (e) {
      return SharedSyncResult(
        backendId: target.id,
        ok: false,
        detail: describeFailure(e),
      );
    }
  }

  /// Rewrites [target]'s drifted copy of [fact] back to the shared wording.
  ///
  /// The anchored entry is what gets overwritten — never a guessed one.
  Future<SharedSyncResult> restoreSharedFact(
    SharedFact fact,
    AgentBackend target,
    SyncAnchor anchor,
  ) async {
    final String? refusal;
    if (target is ClawBackend) {
      final result = await target.applyMemory([
        MemoryChange(
          MemoryOp.update,
          MemoryEntry(
            id: 'shared:${fact.id}',
            kind: fact.kind,
            title: fact.title,
            text: fact.text,
            origin: MemoryOrigin(
              backendId: target.id,
              nativeId: anchor.nativeId,
            ),
          ),
        ),
      ]);
      refusal = result.refused.isEmpty ? null : result.refused.first.detail;
    } else if (target is HermesBackend) {
      refusal = await target.restoreMemoryNode(anchor.nativeId, fact.text);
    } else {
      return SharedSyncResult.refused(target.id, 'Unsupported backend.');
    }
    if (refusal != null) {
      return SharedSyncResult.refused(target.id, refusal);
    }
    await ledger.recordAnchor(
      SyncAnchor(
        factId: fact.id,
        backendId: target.id,
        nativeId: anchor.nativeId,
        fingerprint: MemoryFingerprint.of(fact.text).value,
        syncedAt: DateTime.now(),
      ),
    );
    return SharedSyncResult(backendId: target.id, ok: true, detail: '');
  }

  /// Drops [factId] from the base; when [removeCopies] is true, also removes
  /// the app-owned copies on [targets] (R2-guarded on OpenClaw, node-delete
  /// on Hermes). A copy the app does not own is left alone and reported.
  Future<String> dropSharedFact(
    String factId, {
    required bool removeCopies,
    required List<AgentBackend> targets,
  }) async {
    final anchors = await ledger.sharedAnchors();
    final notes = <String>[];
    if (removeCopies) {
      for (final target in targets) {
        final key = '$factId\u0000${target.id}';
        final anchor = anchors[key];
        if (anchor == null) continue;
        final String? refusal;
        if (target is ClawBackend) {
          final result = await target.applyMemory([
            MemoryChange(
              MemoryOp.remove,
              MemoryEntry(
                id: 'shared:$factId',
                kind: MemoryKind.fact,
                text: anchor.fingerprint,
                origin: MemoryOrigin(
                  backendId: target.id,
                  nativeId: anchor.nativeId,
                ),
              ),
            ),
          ]);
          refusal = result.refused.isEmpty ? null : result.refused.first.detail;
        } else if (target is HermesBackend) {
          refusal = await target.removeMemoryNode(anchor.nativeId);
        } else {
          refusal = 'Unsupported backend.';
        }
        if (refusal != null) notes.add('${target.displayName}: $refusal');
      }
    }
    await ledger.removeSharedFact(factId);
    return notes.isEmpty ? '' : notes.join('\n');
  }

  /// Everything known, live where possible and cached where not.
  ///
  /// [reachOut] opens the *other* saved servers so their memory is read now
  /// rather than recalled from a snapshot. Off by default because it pays a
  /// full handshake — and on OpenClaw a pairing check — per server, which is
  /// not something a panel should do every time it opens.
  ///
  /// The ledger still covers what the pool cannot reach. A server that is
  /// switched off, unreachable, or waiting for its device to be approved has
  /// no live answer, and its last snapshot is strictly better than omitting
  /// it — a bridge that quietly drops a server lies about what it compared.
  Future<MemoryView> memoryView({
    bool reachOut = false,
    MemoryPeers peers = MemoryPeers.none,
  }) async {
    final live = <String, List<MemoryEntry>>{};
    final unreachable = <String, String>{};

    if (supports(Capability.memoryRead)) {
      try {
        live[backend.id] = await memory();
      } on Object catch (e) {
        // The connected server failing must not hide the others — and it must
        // not masquerade as a stale snapshot. It goes in the unreachable
        // banner with the rest, and its cache is still shown (labelled with
        // its age) rather than dropped.
        unreachable[backend.id] = _peerFailure(e);
      }
    }

    if (reachOut) {
      // Already-open tabs first: no handshake, no pairing check — the user
      // opened them. This is what `AgentTabs.connectedBackends` buys the
      // bridge.
      for (final other in peers.backends.values) {
        if (other.id == backend.id) continue;
        if (live.containsKey(other.id)) continue;
        if (!other.supports(Capability.memoryRead)) continue;
        try {
          final entries = await other.memory();
          live[other.id] = entries;
          await ledger.record(other.id, entries);
        } on Object catch (e) {
          unreachable[other.id] = _peerFailure(e);
        }
      }

      final pool = BackendPool();
      try {
        // The workspace's own connection is adopted rather than reopened:
        // a second socket to a server already connected is a second device
        // pairing on OpenClaw, and a wasted handshake on both. The saved
        // servers already open as tabs are excluded the same way.
        pool.adopt(connectionId ?? backend.id, backend);
        await pool.connectAll(
          except: {?connectionId, ...peers.openConnectionIds},
        );
        for (final pooled in pool.usable) {
          final other = pooled.backend!;
          if (other.id == backend.id) continue;
          if (live.containsKey(other.id)) continue;
          if (!other.supports(Capability.memoryRead)) continue;
          try {
            final entries = await other.memory();
            live[other.id] = entries;
            await ledger.record(other.id, entries);
          } on Object catch (e) {
            unreachable[other.id] = _peerFailure(e);
          }
        }
        unreachable.addAll(pool.failures);
      } finally {
        await pool.dispose();
      }
    }

    return ledger.view(liveEntries: live, unreachable: unreachable);
  }

  String _peerFailure(Object e) {
    final reason = describeFailure(e);
    return reason.trim().isEmpty ? 'read failed' : reason;
  }

  /// Records a person's ruling that two entries are, or are not, one fact.
  ///
  /// The bridge's whole premise is that the person is the merge resolver;
  /// this is how a ruling is made and it outlives the next read. A `same`
  /// verdict joins entries the fingerprint could not see were one; a
  /// `different` verdict keeps apart two it did.
  Future<void> ruleMemory(
    MemoryOrigin a,
    MemoryOrigin b, {
    required bool same,
  }) => ledger.rule(MemoryVerdict(a: a, b: b, same: same));

  /// Which saved connection this workspace was opened from.
  ///
  /// Null for a workspace built straight from a gateway — the bench, and the
  /// tests. Without it the pool cannot tell which saved server is already
  /// connected and would open a second socket to it.
  String? connectionId;

  /// The bridge's reach-out set: backends already open as tabs, and the saved
  /// connection ids they came from. Filled by the shell; empty for a bench
  /// or test workspace.
  MemoryPeers peers = MemoryPeers.none;

  /// Runs the server has scheduled for itself. Behind [Capability.cron].
  Future<List<AgentJob>> jobs() => backend.jobs();

  /// Schedules one. Behind [Capability.cronEditing], which is a different
  /// permission from reading the schedule — and on OpenClaw a different
  /// scope. Throws rather than swallowing: the caller has a dialog open and
  /// somewhere to say what went wrong.
  Future<void> createJob({
    required String name,
    required String schedule,
    required String prompt,
  }) => backend.createJob(name: name, schedule: schedule, prompt: prompt);

  /// One line a panel can show for any failure a backend threw.
  ///
  /// Here rather than in each panel because the mapping is the same
  /// everywhere and getting it wrong shows a stack trace to a user.
  String describeFailure(Object error) => switch (error) {
    AgentException(:final detail) when detail.isNotEmpty => detail,
    _ => _reason(error),
  };

  /// The gateway's approval policy, as the server currently reports it.
  Future<String> approvalMode() async {
    final raw = await gateway.configGet('approval_mode');
    return '${raw['value'] ?? ''}';
  }

  /// Changes the approval policy **for one session**.
  ///
  /// [HermesConsole.configSet] defaults to `scope: 'session'` and this relies
  /// on that: `approvals.mode` is global config, and writing it globally would
  /// change how every session on the server behaves — including ones this
  /// client has never opened. A phone settings screen is not where that
  /// decision belongs.
  Future<bool> setApprovalMode(String sessionId, String mode) async {
    try {
      await gateway.configSet(
        sessionId: _live(sessionId),
        key: 'approval_mode',
        value: mode,
      );
      return true;
    } catch (e) {
      _consoles[sessionId]?.setError('Could not set approvals: ${_reason(e)}');
      return false;
    }
  }

  /// What the agent can reach for, in this session.
  ///
  /// Behind [Capability.skills]. Takes a session because the tool half of the
  /// answer is per session on both backends. An unopened session has no
  /// handle and so has no answer — an empty list rather than a throw, since a
  /// caller that ignored the capability would have to handle one anyway.
  Future<List<AgentSkill>> skills(String sessionId) async {
    final handle = _handles[sessionId];
    if (handle == null) return const [];
    return backend.skills(handle);
  }

  /// `@`-reference completion. Resolved against the session's cwd, which lives
  /// on the server — a local file picker cannot answer this.
  Future<List<PathCompletion>> completePath(
    String sessionId,
    String word,
  ) async {
    // Hermes-only. Answering nothing is the same outcome the catch below
    // already produces, and reaching for a client that is not there to get
    // there would be a slower way to say it.
    if (_gateway == null) return const [];
    try {
      return await gateway.completePath(
        word: word,
        sessionId: _live(sessionId),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<bool> setCwd(String sessionId, String cwd) async {
    try {
      final r = await gateway.sessionCwdSet(
        sessionId: _live(sessionId),
        cwd: cwd,
      );
      final console = _consoles[sessionId];
      if (console != null) {
        // Trust the server's answer, not the input: it resolves `~`, relative
        // paths and symlinks, and the resolved form is what @-completion and
        // attachments will use.
        console.cwd = r['cwd']?.toString() ?? cwd;
        console.branch = r['branch']?.toString() ?? '';
        console.notify();
      }
      return true;
    } catch (e) {
      _consoles[sessionId]?.setError('Working directory: ${_reason(e)}');
      return false;
    }
  }

  /// Answers a blocking prompt.
  ///
  /// The value is whatever the user typed — for sudo and secret prompts it is
  /// a credential, so it is passed straight through and never stored, logged
  /// or echoed into the transcript.
  Future<bool> respondToPrompt(
    String sessionId,
    AgentPrompt prompt,
    String value,
  ) async {
    try {
      // One call. Which of Hermes' four answer paths this is — and that an
      // approval is keyed on the session rather than the request — is the
      // adapter's to remember, because the adapter is what raised it.
      await backend.respond(
        prompt.id,
        PromptAnswer(value, secret: prompt.isSecret),
      );
      _consoles[sessionId]?.removePrompt(prompt);
      return true;
    } catch (e) {
      // Deliberately does not include the value in the message.
      _consoles[sessionId]?.setError('Could not answer: ${_reason(e)}');
      return false;
    }
  }

  Future<void> respondToApproval(
    String sessionId,
    AgentPrompt prompt,
    String choice,
  ) async {
    try {
      await backend.respond(prompt.id, PromptAnswer(choice));
      _consoles[sessionId]?.removeApproval(prompt);
    } on AgentException catch (e) {
      _consoles[sessionId]?.setError('Approval failed: ${e.detail}');
    } catch (e) {
      _consoles[sessionId]?.setError('Approval failed: ${_reason(e)}');
    }
  }

  /// Stops listening to a session and tells the backend to stop sending.
  ///
  /// The second half is a no-op on Hermes, which pushes everything down one
  /// socket regardless, and a real unsubscribe on OpenClaw — which otherwise
  /// keeps streaming a conversation nobody is reading.
  Future<void> _releaseSession(String sessionId) async {
    // Not awaited: the future a broadcast subscription's cancel returns does
    // not complete while its controller is live, and awaiting one in a path
    // that then does more work deadlocks. Learned the hard way in [_adopt].
    unawaited(
      _sessionEvents.remove(sessionId)?.cancel() ?? Future<void>.value(),
    );
    final handle = _handles.remove(sessionId);
    if (handle != null) await backend.release(handle);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events?.cancel() ?? Future<void>.value());
    unawaited(_index.cancel());
    unawaited(_connection.cancel());
    for (final sub in _sessionEvents.values) {
      unawaited(sub.cancel());
    }
    _sessionEvents.clear();
    for (final c in _consoles.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// The bridge's reach-out set, handed from the shell to the memory panel.
///
/// [backends] are the tabs already open — asking them costs no handshake and,
/// on OpenClaw, no second device pairing. [openConnectionIds] are the saved
/// servers those tabs came from, so the pool does not open a second socket to
/// a server that is already on screen.
class MemoryPeers {
  const MemoryPeers({
    this.backends = const {},
    this.openConnectionIds = const {},
  });

  /// No peers: the panel pays a pool for every reach-out.
  static const none = MemoryPeers();

  final Map<String, AgentBackend> backends;

  /// Saved-connection ids already open as tabs.
  final Set<String> openConnectionIds;
}

/// What the skills screen shows, and which agents it came from.
///
/// Unlike [MemoryView] there is no ledger half: a skill library is live
/// inventory, so every entry is from a backend read just now, and a backend
/// that could not answer is in [unreachable] rather than silently absent.
class SkillLibraryView {
  const SkillLibraryView({
    required this.clusters,
    this.liveBackendIds = const {},
    this.unreachable = const {},
  });

  final List<SkillCluster> clusters;

  /// The backends whose libraries are in this view, read live.
  final Set<String> liveBackendIds;

  /// Servers that were asked and could not answer, and why.
  final Map<String, String> unreachable;

  Set<String> get backends => liveBackendIds;

  bool get isEmpty => clusters.isEmpty;

  /// Clusters missing from at least one backend in the view.
  ///
  /// The answer to "what does one agent have that the other does not", which
  /// is the question the bridge exists to make askable.
  List<SkillCluster> get divergent => [
    for (final cluster in clusters)
      if (cluster.missingFrom(backends).isNotEmpty) cluster,
  ];
}

/// The shared knowledge base, and every agent's state against it.
///
/// `SHARED_MEMORY.md`. [facts] is the physical store on this device (the
/// future cloud-sync source); [statesByFact] maps each fact to the per-agent
/// verdicts the detector produced from the same view the memory panel shows.
class SharedMemoryView {
  const SharedMemoryView({
    required this.facts,
    required this.statesByFact,
    this.sources = const {},
    this.liveBackendIds = const {},
    this.unreachable = const {},
  });

  final List<SharedFact> facts;

  /// Fact id → per-agent states.
  final Map<String, FactStates> statesByFact;

  /// Every backend the memory bridge knows about, and when it was read.
  final Map<String, DateTime?> sources;

  final Set<String> liveBackendIds;

  /// Servers that were asked and could not answer, in the bridge's words.
  final Map<String, String> unreachable;

  Set<String> get backends => sources.keys.toSet();

  bool get isEmpty => facts.isEmpty;

  /// Facts with at least one drifted or missing agent — the panel's
  /// "needs attention" edge.
  List<SharedFact> get needsAttention => [
    for (final fact in facts)
      if (statesByFact[fact.id]?.anyNeedsAttention ?? false) fact,
  ];

  FactStates? statesFor(String factId) => statesByFact[factId];
}

/// What became of one shared-fact write to one agent.
class SharedSyncResult {
  const SharedSyncResult({
    required this.backendId,
    required this.ok,
    required this.detail,
    this.nativeId,
  });

  const SharedSyncResult.refused(String backendId, String detail)
    : this(backendId: backendId, ok: false, detail: detail);

  final String backendId;
  final bool ok;

  /// Why it failed, in the backend's own words. Empty on success.
  final String detail;

  /// Where the copy landed (a Hermes node id or an OpenClaw `MEMORY.md#`).
  final String? nativeId;

  @override
  String toString() =>
      'SharedSyncResult($backendId, ${ok ? "ok" : "refused: $detail"})';
}
