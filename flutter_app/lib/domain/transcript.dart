/// What a turn is made of, independent of any agent that produced one.
///
/// These are the classes that describe a *conversation* rather than a
/// protocol. The value types among them now live in `agent_core`; what stays
/// here is the part that is about *rendering* a transcript — the ordering, the
/// open/closed segments, the reveal bookkeeping — which is the app's problem
/// and not a backend's. See ARCHITECTURE.md §8.
///
/// The library imports no wire package, which is the whole point and was not
/// true a phase ago: [PromptEntry] held a `hermes_protocol` `BlockingPrompt`,
/// so the otherwise-neutral transcript dragged the Hermes client in behind it.
/// A blocking question is a concept every agent has — OpenClaw resolves them
/// through `exec.approval.resolve` — so it became [AgentPrompt], and this line
/// is what proves the leak is closed.
library;

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';

export 'package:agent_core/agent_core.dart'
    show AgentPrompt, AgentPromptKind, AgentToolCall, PromptId, WebResult;

/// The app's long-standing name for [AgentToolCall].
///
/// A typedef rather than a rename across ~20 files: the type moved packages,
/// the concept did not, and a mechanical rename would have buried the one
/// change that mattered under a hundred that did not.
typedef ToolCall = AgentToolCall;

/// call, in the order they happened.
///
/// The two used to live in separate panes, which lost the ordering entirely —
/// a turn that thought, ran a command, then thought again about its output
/// rendered as one reasoning blob beside one tool list. That ordering is most
/// of what makes a long turn legible.
sealed class TurnEntry {
  const TurnEntry();
}

/// A stretch of reasoning, closed when a tool starts or the answer begins.
class ThinkingSegment extends TurnEntry {
  ThinkingSegment(this.startedAt, {this.durationKnown = true});

  /// Restored from a transcript rather than watched as it happened.
  ///
  /// The server stores what the model thought, not how long it took. Showing
  /// "Thought for 0s" on a resumed conversation would state a duration nobody
  /// measured, so those segments say "Thought" and nothing more.
  factory ThinkingSegment.restored(String text) {
    final segment = ThinkingSegment(DateTime.now(), durationKnown: false)
      ..endedAt = DateTime.now();
    segment.text.write(text);
    return segment;
  }

  final DateTime startedAt;
  final StringBuffer text = StringBuffer();
  DateTime? endedAt;

  /// False for segments read back from history, where no clock ever ran.
  final bool durationKnown;

  bool get open => endedAt == null;
  Duration get elapsed => (endedAt ?? DateTime.now()).difference(startedAt);

  /// One line of the trace, for a preview while collapsed.
  ///
  /// Which line, and which end of it, depends on whether a clock is running.
  /// A trace still being written shows its *newest* line, tail-first — that is
  /// where the movement is, and watching it is how a long think stays legible
  /// as something happening rather than something stuck.
  ///
  /// A restored one shows its *first* line, head-first. Nothing is moving, the
  /// reader is skimming rather than watching, and a trace that opens mid-word
  /// with an ellipsis ("…s missing according to the project context") reads as
  /// damage. Seen on a real resumed transcript, which is the only place a
  /// restored segment exists.
  String get preview {
    final body = text.toString().trim();
    if (body.isEmpty) return '';
    if (!durationKnown) {
      final br = body.indexOf('\n');
      final line = (br == -1 ? body : body.substring(0, br)).trim();
      return line.length <= 120 ? line : '${line.substring(0, 120)}…';
    }
    final br = body.lastIndexOf('\n');
    final line = (br == -1 ? body : body.substring(br + 1)).trim();
    return line.length <= 120 ? line : '…${line.substring(line.length - 120)}';
  }
}

/// A tool call, referenced by id so it stays in step with [SessionConsole.tools]
/// as `tool.complete` fills in the result.
class ToolEntry extends TurnEntry {
  const ToolEntry(this.toolId);
  final String toolId;
}

/// A question the agent is blocked on, in the turn where it was asked.
///
/// These used to render as a banner pinned above the transcript. With more
/// than one turn on screen that banner said nothing about *which* question it
/// belonged to, and it sat above the conversation rather than in it — so the
/// answer arrived detached from the exchange that prompted it. In the
/// timeline it reads in sequence: thought, asked, waited.
class PromptEntry extends TurnEntry {
  const PromptEntry(this.prompt);
  final AgentPrompt prompt;
}

/// One exchange: the entries it produced, and where it sits in the transcript.
///
/// The anchor is what lets a turn's thinking render under *its own* question
/// rather than all of them piling up under the newest one. Without it the
/// previous turn's reasoning appeared inside the current turn's block, and
/// scrolling back through history showed no thinking at all.
class Turn {
  Turn({required this.anchorBlock});

  final List<TurnEntry> entries = [];

  /// Which entries have already been shown arriving.
  ///
  /// Kept on the turn rather than in the widget that draws it, because that
  /// widget lives inside the transcript's `ListView` and is destroyed and
  /// rebuilt every time it scrolls out of view and back. Any "have I animated
  /// this yet" flag held in the widget tree is reset by that, and every
  /// thought and tool call in a finished turn plays its entrance again under
  /// the reader's thumb.
  final Set<int> revealed = {};

  /// Index of the settled transcript block this turn's prompt occupies.
  final int anchorBlock;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;
}

/// Live state for one session.
///
/// Kept alive by [Workspace] after the user navigates away, for two reasons:
/// switching back is instant instead of re-resuming, and a turn running in a
/// background session keeps accumulating instead of silently dropping output.

/// One installed skill, as `plugins.list` reports it.
@immutable
class Skill {
  const Skill({required this.name, required this.enabled, this.version = ''});

  final String name;
  final bool enabled;
  final String version;
}
