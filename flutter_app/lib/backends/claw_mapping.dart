/// OpenClaw's stored shapes, translated into the domain's.
///
/// Beside `hermes_mapping.dart` and for the same reason: this is the half of
/// the seam that knows a protocol, and keeping it out of the adapter means the
/// parsing can be tested against a real payload without a socket.
library;

import 'package:agent_core/agent_core.dart';

/// A `chat.history` reply, as domain messages.
///
/// A stored transcript records a tool call in two rows — the assistant asking
/// for it, then a `toolResult` carrying what it printed — and neither is an
/// ordinary message. Read as one, the result row lands on the unrecognised-role
/// path and a command's raw output renders as an italic aside from the server.
List<AgentMessage> clawMessagesFromHistory(List<Map<String, dynamic>> rows) => [
  for (final row in rows) clawMessageFromRow(row),
];

/// One stored row, as a domain message.
AgentMessage clawMessageFromRow(Map<String, dynamic> row) {
  final role = row['role']?.toString();

  if (role == 'toolResult') {
    final output = _parts(row, 'text').join();
    final failed = row['isError'] == true;
    return AgentMessage(
      role: MessageRole.tool,
      text: '',
      toolCallId: '${row['toolCallId'] ?? ''}',
      toolCall: AgentToolCall(
        name: '${row['toolName'] ?? '?'}',
        done: true,
        output: output.isEmpty ? null : output,
        // The row states failure; there is no exit code here to infer it
        // from, and a tool that is not a process would not have one.
        error: failed ? (output.isEmpty ? 'failed' : output) : null,
      ),
    );
  }

  final call = _toolCallPart(row);
  if (call != null) {
    return AgentMessage(
      role: MessageRole.assistant,
      text: '',
      toolCallId: '${call['id'] ?? ''}',
      toolCall: AgentToolCall(
        name: '${call['name'] ?? '?'}',
        context: _callSummary(call),
        args: (call['arguments'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }

  return AgentMessage(
    role: switch (role) {
      'user' => MessageRole.user,
      'assistant' => MessageRole.assistant,
      _ => MessageRole.system,
    },
    text: _visibleText(row),
    reasoning: _reasoningText(row),
  );
}

/// The idempotency key a row was written with, when it has one.
///
/// A client's own sends come back through the event stream like anybody
/// else's. This is what tells them apart from a message typed on a phone —
/// without it, every message this client sends appears twice.
String clawRowClientId(Map<String, dynamic> row) {
  final key =
      row['idempotencyKey'] ?? (row['__openclaw'] as Map?)?['idempotencyKey'];
  final text = key?.toString() ?? '';
  // Written as `<clientId>:user`; the suffix is the gateway's, not ours.
  final colon = text.lastIndexOf(':');
  return colon == -1 ? text : text.substring(0, colon);
}

/// The `toolCall` part of an assistant row, if it has one.
Map<String, dynamic>? _toolCallPart(Map<String, dynamic> row) {
  final content = row['content'];
  if (content is! List) return null;
  for (final part in content.whereType<Map>()) {
    if (part['type'] == 'toolCall') return part.cast<String, dynamic>();
  }
  return null;
}

/// A one-line summary of what a call is about.
///
/// The live event stream gets this from the gateway as `meta`; a stored row
/// carries only the arguments, so it is built from the one that reads like a
/// subject — the command, the path, the query. Better than nothing beside the
/// tool's name, which on its own says a tool ran and not what it did.
String _callSummary(Map<String, dynamic> call) {
  final args = call['arguments'];
  if (args is! Map) return '';
  for (final key in const ['command', 'path', 'file_path', 'query', 'url']) {
    final value = args[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

/// What a stored message actually says.
///
/// A message's `content` is an array of typed parts, not a string — the
/// answer, what the model thought, images, and a signature blob travel side
/// by side. Reading it extracts visible text and image elements as Markdown
/// images, while filtering out metadata signatures.
String _visibleText(Map<String, dynamic> row) {
  final buffer = StringBuffer();

  // Attachments in row
  final attachments =
      (row['attachments'] as List?) ??
      (row['files'] as List?) ??
      (row['images'] as List?);
  if (attachments != null) {
    for (final a in attachments) {
      if (a is Map) {
        final content = a['content'] ?? a['data'] ?? a['url'];
        final mime = a['mimeType'] ?? a['mime_type'] ?? 'image/png';
        final name = a['fileName'] ?? a['name'] ?? 'image';
        if (content is String && content.isNotEmpty) {
          if (content.startsWith('http') || content.startsWith('data:')) {
            buffer.write('![$name]($content)\n\n');
          } else {
            buffer.write('![$name](data:$mime;base64,$content)\n\n');
          }
        }
      } else if (a is String && a.isNotEmpty) {
        if (a.startsWith('http') || a.startsWith('data:')) {
          buffer.write('![image]($a)\n\n');
        }
      }
    }
  }

  // Content array or text
  final content = row['content'];
  if (content is String) {
    buffer.write(content);
  } else if (content is List) {
    for (final part in content.whereType<Map>()) {
      final type = part['type'];
      if (type == 'text') {
        final val = part['text'];
        if (val is String && val.isNotEmpty) buffer.write(val);
      } else if (type == 'image' ||
          type == 'image_url' ||
          type == 'input_image') {
        final src =
            part['source'] ??
            part['image_url'] ??
            part['url'] ??
            part['data'] ??
            part['image'];
        final mime = part['mimeType'] ?? part['mime_type'] ?? 'image/png';
        if (src is Map) {
          final data = src['data'] ?? src['url'];
          final mediaType = src['media_type'] ?? mime;
          if (data is String && data.isNotEmpty) {
            if (data.startsWith('http') || data.startsWith('data:')) {
              buffer.write('\n\n![image]($data)\n\n');
            } else {
              buffer.write('\n\n![image](data:$mediaType;base64,$data)\n\n');
            }
          }
        } else if (src is String && src.isNotEmpty) {
          if (src.startsWith('http') || src.startsWith('data:')) {
            buffer.write('\n\n![image]($src)\n\n');
          } else {
            buffer.write('\n\n![image](data:$mime;base64,$src)\n\n');
          }
        }
      }
    }
  }

  if (buffer.isNotEmpty) return buffer.toString().trim();

  // A row that carries a plain `text` instead — the display-normalised
  // placeholder the gateway substitutes for an oversized message is one.
  final plain = row['text'];
  return plain is String ? plain : '';
}

/// The thinking parts, kept out of the answer and in their own channel —
/// the same separation every other backend gets.
String? _reasoningText(Map<String, dynamic> row) {
  final thinking = _parts(row, 'thinking').join().trim();
  return thinking.isEmpty ? null : thinking;
}

/// Every `content` part of [kind], in order.
Iterable<String> _parts(Map<String, dynamic> row, String kind) sync* {
  final content = row['content'];
  if (content is String) {
    if (kind == 'text') yield content;
    return;
  }
  if (content is! List) return;
  for (final part in content.whereType<Map>()) {
    if (part['type'] != kind) continue;
    final value = part[kind];
    if (value is String && value.isNotEmpty) yield value;
  }
}

/// Attachments are refused rather than guessed at.
///
/// `sessions.send` does accept an `attachments` array, but the schema types
/// its entries as unknown, so the shape of one is the single thing about
/// this method the gateway's contract does not pin down. Sending a guess at
/// it is how the rest of this adapter's first draft went wrong.

/// One `session.tool` frame, as a domain event — or null when it is not one
/// this client shows.
///
/// The gateway sends each phase three times: once as the tool lifecycle
/// itself, and twice more as rows for its own activity list, tagged
/// `itemId: tool:…` and `itemId: command:…`. Only the first is the tool. A
/// client that takes all three renders every call three times over.
///
/// The phases are `start`, `update`, `delta` and `result`. `update` carries a
/// partial result that `delta` then sends as plain output, so only `delta` is
/// forwarded — taking both would print the same bytes twice.
AgentEvent? clawToolEvent(
  String sessionId,
  Map<String, dynamic> data, {
  ResumeCursor? cursor,
}) {
  if (data.containsKey('itemId')) return null;
  final toolId = data['toolCallId']?.toString();
  if (toolId == null || toolId.isEmpty) return null;

  switch (data['phase']?.toString()) {
    case 'start':
      return ToolStarted(
        sessionId: sessionId,
        toolId: toolId,
        call: AgentToolCall(
          name: data['name']?.toString() ?? '?',
          // `meta` is the gateway's own one-line summary of *this* call — the
          // command for an exec, the path for a read. It is what lets a row
          // say what it did rather than only that something did.
          context: data['meta']?.toString() ?? '',
          args: (data['args'] as Map?)?.cast<String, dynamic>(),
        ),
      );

    case 'delta':
      final output = data['output']?.toString() ?? '';
      return output.isEmpty
          ? null
          : ToolProgress(
              sessionId: sessionId,
              toolId: toolId,
              text: output,
              cursor: cursor,
            );

    case 'result':
      final result = (data['result'] as Map?)?.cast<String, dynamic>();
      final details = (result?['details'] as Map?)?.cast<String, dynamic>();
      return ToolFinished(
        sessionId: sessionId,
        toolId: toolId,
        cursor: cursor,
        call: AgentToolCall(
          name: data['name']?.toString() ?? '?',
          context: data['meta']?.toString() ?? '',
          done: true,
          durationSeconds:
              ((details?['durationMs'] as num?)?.toDouble() ?? 0) / 1000,
          args: (data['args'] as Map?)?.cast<String, dynamic>(),
          output: _toolOutput(result, details),
          exitCode: (details?['exitCode'] as num?)?.toInt(),
          // The gateway states failure rather than leaving it to be inferred
          // from an exit code, which a tool that is not a process does not
          // have. `exitReason` is its word for what went wrong.
          error: data['isError'] == true
              ? (details?['exitReason']?.toString() ?? 'failed')
              : null,
        ),
      );

    default:
      return null;
  }
}

/// What a finished tool printed.
///
/// `result.content` is the same typed-part array a message uses; `aggregated`
/// is the gateway's own flattening of it and is the better fallback than
/// stringifying the array, which is how a signature blob ends up on screen.
String? _toolOutput(
  Map<String, dynamic>? result,
  Map<String, dynamic>? details,
) {
  final parts = _parts({'content': result?['content']}, 'text').join();
  if (parts.isNotEmpty) return parts;
  final aggregated = details?['aggregated'];
  return aggregated is String && aggregated.isNotEmpty ? aggregated : null;
}
