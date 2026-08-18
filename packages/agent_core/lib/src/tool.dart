/// A tool invocation, and the structured results some tools return.
library;

import 'package:meta/meta.dart';

/// One hit from a web search.
///
/// In the domain rather than in an adapter because it is what a *reader* sees:
/// a search that returned five pages should render as five pages on any
/// backend. Only the parsing is backend-specific, and that stays in the
/// adapter.
@immutable
class WebResult {
  const WebResult({required this.title, required this.url, this.snippet = ''});

  final String title;
  final String url;
  final String snippet;

  @override
  String toString() => 'WebResult($title)';
}

/// One tool invocation, from the moment it starts to the moment it returns.
///
/// Immutable, and advanced by [completed] rather than mutated, because a tool
/// call is referenced by id from the turn timeline: a mutable one edited in
/// place would change history under a widget that had already drawn it.
@immutable
class AgentToolCall {
  const AgentToolCall({
    required this.name,
    this.context = '',
    this.done = false,
    this.durationSeconds = 0,
    this.args,
    this.output,
    this.exitCode,
    this.error,
    this.webResults = const [],
  });

  /// What the agent called — `bash`, `read_file`, `web_search`.
  final String name;

  /// A one-line summary of *this* invocation, when the server offers one.
  /// Usually the command or the path, so a row can say what it did rather
  /// than only that something happened.
  final String context;

  final bool done;
  final double durationSeconds;
  final Map<String, dynamic>? args;
  final String? output;

  /// Process exit status, for tools that run one. Null for tools that do not.
  final int? exitCode;
  final String? error;

  /// Structured search hits, when the tool returned them instead of text.
  ///
  /// Not decoration: a search tool that answers with structured rows and an
  /// empty `output` renders, without this, as "a search happened" and nothing
  /// about what it found.
  final List<WebResult> webResults;

  /// The query, pulled out of [args] so a row can say what was searched for.
  String? get query {
    final q = args?['query'];
    return q is String && q.trim().isNotEmpty ? q.trim() : null;
  }

  /// A non-zero exit is a failure even when the tool reported no error, and an
  /// error is a failure even when the process exited zero. Both, or the row
  /// lies in one direction or the other.
  bool get failed => error != null || (exitCode != null && exitCode != 0);

  /// The same call with more output.
  ///
  /// A tool that prints as it runs — a build, a long grep — otherwise shows an
  /// empty row until it finishes, which for the calls worth watching is the
  /// whole time anybody is watching. Still `done: false`: output arriving is
  /// not the call ending.
  AgentToolCall appending(String more) => AgentToolCall(
    name: name,
    context: context,
    durationSeconds: durationSeconds,
    args: args,
    output: '${output ?? ''}$more',
    webResults: webResults,
  );

  AgentToolCall completed({
    required double durationSeconds,
    Map<String, dynamic>? args,
    String? output,
    int? exitCode,
    String? error,
    List<WebResult> webResults = const [],
  }) => AgentToolCall(
    name: name,
    context: context,
    done: true,
    durationSeconds: durationSeconds,
    args: args,
    output: output,
    exitCode: exitCode,
    error: error,
    webResults: webResults,
  );

  @override
  String toString() => 'AgentToolCall($name${done ? ', done' : ''})';
}
