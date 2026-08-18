/// A settled message, as read back from a stored transcript.
library;

import 'package:meta/meta.dart';

import 'tool.dart';

/// Who said it.
enum MessageRole {
  user,
  assistant,

  /// The server talking about the conversation rather than in it — a model
  /// switch, a truncation notice, a compaction marker. Rendered as a note, not
  /// as something the agent said.
  system,

  /// What a tool printed.
  ///
  /// Its own role because it is neither. Folded into [system] — which is where
  /// an unrecognised role lands — a command's raw output renders as an italic
  /// aside from the server, which is a claim about who said it and a wrong
  /// one.
  tool,
}

/// One message in a transcript that has already happened.
///
/// Distinct from the live event stream on purpose. A message is what the
/// server *stored*; the events are what the client *watched*. They carry
/// different information and the difference is visible: a stored message has
/// the reasoning text but not how long it took, which is why a resumed
/// conversation says "Thought" where a watched one says "Thought for 12s".
/// Collapsing the two types would force the restored case to invent a
/// duration nobody measured.
@immutable
class AgentMessage {
  const AgentMessage({
    required this.role,
    required this.text,
    this.reasoning,
    this.at,
    this.kind = '',
    this.toolCallId = '',
    this.toolCall,
  });

  final MessageRole role;
  final String text;

  /// What the model thought before answering, when the server kept it.
  final String? reasoning;

  final DateTime? at;

  /// A backend-specific sub-type, for a [MessageRole.system] note that the
  /// domain has no concept for. Free text; the UI may show it, and must not
  /// switch behaviour on it.
  final String kind;

  /// Correlates a stored tool call with the row that reports its result.
  ///
  /// A transcript records the two apart — the assistant asking for the tool,
  /// then what the tool printed — so reading history back needs the same
  /// correlation the live event stream has.
  final String toolCallId;

  /// The tool this message is about, when it is about one.
  ///
  /// Present on both halves: the call as the agent asked for it, and the same
  /// call completed once the result row arrives. Null for an ordinary message,
  /// and null on every backend that does not put tool calls in its transcript
  /// — which is not the same as a backend whose agent uses no tools.
  final AgentToolCall? toolCall;

  bool get isEmpty =>
      text.trim().isEmpty &&
      (reasoning?.trim().isEmpty ?? true) &&
      toolCall == null;

  @override
  String toString() => 'AgentMessage(${role.name}, ${text.length} chars)';
}
