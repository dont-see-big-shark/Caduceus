/// Hermes' wire vocabulary, translated into the domain's.
///
/// The first piece of `HermesBackend` (ARCHITECTURE.md phase 2) to exist. It
/// lives here rather than in `domain/` because it is the half of the seam that
/// knows a protocol: `domain/transcript.dart` must import no wire package, and
/// the way to keep that true is to have somewhere else for the parsing to go
/// the moment a neutral type needs filling from a Hermes payload.
library;

import 'package:agent_core/agent_core.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

/// Structured search hits out of a `tool.complete` result.
///
/// `web_search` answers with `result.data.web[]`, not `result.output`, so a
/// client reading only the latter throws every hit away — it shows that a
/// search happened and nothing about what it found.
List<WebResult> webResultsFromHermes(Object? result) {
  if (result is! Map) return const [];
  final data = result['data'];
  if (data is! Map) return const [];
  final web = data['web'];
  if (web is! List) return const [];
  return web
      .whereType<Map>()
      .map(
        (r) => WebResult(
          title: r['title']?.toString() ?? r['url']?.toString() ?? '',
          url: r['url']?.toString() ?? '',
          snippet: r['description']?.toString() ?? '',
        ),
      )
      .where((r) => r.title.isNotEmpty || r.url.isNotEmpty)
      .toList();
}

/// A tool call as `tool.start` announces it.
AgentToolCall agentToolCallFromHermes(Map<String, dynamic> payload) =>
    AgentToolCall(
      name: payload['name']?.toString() ?? '?',
      context: payload['context']?.toString() ?? '',
    );

/// [base], closed out with what `tool.complete` reported.
///
/// Two shapes of `result` have to be read, and reading only one is a bug this
/// client has shipped: the server does `json.loads` on whatever the tool
/// returned and falls back to the raw string when that fails
/// (`server.py`, `_on_tool_complete`). Handling only the Map showed *no
/// output at all* for every tool that answers in plain text. `summary` is the
/// server's own one-line rendering and is the better thing to show when there
/// is no output field.
AgentToolCall completeToolFromHermes(
  AgentToolCall base,
  Map<String, dynamic> payload, {
  HermesEndpoint? endpoint,
}) {
  final result = payload['result'];
  String? output;
  if (result is Map<String, dynamic>) {
    final image =
        (result['host_image'] ?? result['image'] ?? result['image_url'])
            ?.toString();
    if (image != null && image.isNotEmpty) {
      output = (endpoint != null && !_isNetworkOrDataUri(image))
          ? endpoint.fileDownloadUri(image).toString()
          : image;
    } else {
      output =
          (result['output'] ?? result['stdout'] ?? result['text'])
              ?.toString() ??
          payload['summary']?.toString();
    }
  } else if (result is String) {
    output = result;
  } else if (result == null) {
    output = payload['summary']?.toString();
  } else {
    output = result.toString();
  }

  return base.completed(
    durationSeconds: (payload['duration_s'] as num?)?.toDouble() ?? 0,
    args: payload['args'] as Map<String, dynamic>?,
    output: output,
    webResults: webResultsFromHermes(result),
    exitCode: result is Map ? (result['exit_code'] as num?)?.toInt() : null,
    error: result is Map ? result['error']?.toString() : null,
  );
}

/// A blocking question, from whichever of the three events raised it.
///
/// Hermes splits one concept across `clarify.request`, `sudo.request` and
/// `secret.request`; the domain has one type and a [AgentPromptKind]. The
/// mapping is not quite an alias — Hermes' `sudo` becomes [
/// AgentPromptKind.password], because the concept is "elevate", not "run the
/// `sudo` binary", and the second backend will not have that binary.
AgentPrompt agentPromptFromHermes(String type, Map<String, dynamic> payload) {
  final prompt = BlockingPrompt.fromEvent(type, payload);
  return AgentPrompt(
    id: PromptId(prompt.requestId),
    kind: switch (prompt.kind) {
      BlockingPromptKind.clarify => AgentPromptKind.clarify,
      BlockingPromptKind.sudo => AgentPromptKind.password,
      BlockingPromptKind.secret => AgentPromptKind.secret,
    },
    question: prompt.question,
    choices: prompt.choices,
    multiSelect: prompt.multiSelect,
    envVar: prompt.envVar,
  );
}

/// One row of `session.list`, as a neutral session.
AgentSession agentSessionFromHermes(SessionSummary summary) => AgentSession(
  id: summary.id,
  title: summary.title,
  preview: summary.preview,
  messageCount: summary.messageCount,
  updatedAt: summary.startedAt,
  source: summary.source,
);

/// A stored transcript turn, as a neutral message.
///
final _imageDirectiveLineRegex = RegExp(r'^@image:[^\n]*\n?', multiLine: true);
final _fileDirectiveLineRegex = RegExp(r'^@file:[^\n]*\n?', multiLine: true);
final _screenshotLineRegex = RegExp(r'^\[screenshot\]\n?', multiLine: true);
final _mediaTagLineRegex = RegExp(
  r"""(^|\n)[\t ]*[`"']?MEDIA:\s*(`[^`\n]+`|"[^"\n]+"|'[^'\n]+'|\S+)[`"']?[\t ]*(?:\n|$)""",
  multiLine: true,
);
final _mediaTagInlineRegex = RegExp(
  r"""[`"']?MEDIA:\s*(`[^`\n]+`|"[^"\n]+"|'[^'\n]+'|\S+)[`"']?""",
);
final _markdownImageRegex = RegExp(r'!\[([^\]]*)\]\((.*?)\)');
final _mediaHashLinkRegex = RegExp(r'\[([^\]]*)\]\(\s*#media:([^\)\s]+)\s*\)');

bool _isNetworkOrDataUri(String path) =>
    path.startsWith('http://') ||
    path.startsWith('https://') ||
    path.startsWith('data:') ||
    path.startsWith('blob:');

bool _isImageExtension(String path) {
  final clean = path.split('?').first.split('#').first.toLowerCase();
  return clean.endsWith('.png') ||
      clean.endsWith('.jpg') ||
      clean.endsWith('.jpeg') ||
      clean.endsWith('.gif') ||
      clean.endsWith('.webp') ||
      clean.endsWith('.svg') ||
      clean.endsWith('.bmp');
}

bool _isVideoExtension(String path) {
  final clean = path.split('?').first.split('#').first.toLowerCase();
  return clean.endsWith('.mp4') ||
      clean.endsWith('.mov') ||
      clean.endsWith('.webm') ||
      clean.endsWith('.mkv') ||
      clean.endsWith('.avi');
}

bool _isAudioExtension(String path) {
  final clean = path.split('?').first.split('#').first.toLowerCase();
  return clean.endsWith('.mp3') ||
      clean.endsWith('.wav') ||
      clean.endsWith('.m4a') ||
      clean.endsWith('.ogg') ||
      clean.endsWith('.flac') ||
      clean.endsWith('.opus');
}

String _unquoteMediaPath(String value) {
  var trimmed = value.trim();
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'")) ||
      (trimmed.startsWith('`') && trimmed.endsWith('`'))) {
    trimmed = trimmed.substring(1, trimmed.length - 1).trim();
  }
  return trimmed;
}

String _resolveMediaUrl(String path, HermesEndpoint? endpoint) {
  if (endpoint != null && !_isNetworkOrDataUri(path)) {
    return endpoint.fileDownloadUri(path).toString();
  }
  return path;
}

String _formatMediaMarkdown(String rawPath, HermesEndpoint? endpoint) {
  final path = _unquoteMediaPath(rawPath);
  if (path.isEmpty) return '';
  final name = path.split('/').last.split('\\').last;
  final url = _resolveMediaUrl(path, endpoint);
  if (_isImageExtension(path)) {
    return '![$name]($url)';
  } else if (_isVideoExtension(path)) {
    return '[🎬 $name]($url)';
  } else if (_isAudioExtension(path)) {
    return '[🎵 $name]($url)';
  }
  return '[📄 $name]($url)';
}

/// Resolves Hermes message text by converting `MEDIA:...` tags, `@image:...`
/// directives, image `@file:...` references, and Markdown image paths into
/// valid Markdown image/media tags, optionally resolved through [endpoint]'s
/// authenticated download URL.
String resolveHermesMessageText(String text, {HermesEndpoint? endpoint}) {
  if (text.isEmpty) return text;
  if (!text.contains('@image:') &&
      !text.contains('@file:') &&
      !text.contains('MEDIA:') &&
      !text.contains('[screenshot]') &&
      !text.contains('![') &&
      !text.contains('#media:')) {
    return text;
  }

  var result = text.replaceAllMapped(_mediaTagLineRegex, (match) {
    final lead = match.group(1) ?? '';
    final val = match.group(2) ?? '';
    final formatted = _formatMediaMarkdown(val, endpoint);
    return '$lead$formatted\n';
  });

  result = result.replaceAllMapped(_mediaTagInlineRegex, (match) {
    final val = match.group(1) ?? '';
    return _formatMediaMarkdown(val, endpoint);
  });

  result = result.replaceAllMapped(_mediaHashLinkRegex, (match) {
    final label = match.group(1) ?? '';
    final encoded = match.group(2) ?? '';
    final path = Uri.decodeComponent(encoded);
    final url = _resolveMediaUrl(path, endpoint);
    if (_isImageExtension(path)) {
      return '![$label]($url)';
    }
    return '[$label]($url)';
  });

  result = result.replaceAllMapped(_markdownImageRegex, (match) {
    final alt = match.group(1) ?? '';
    final src = match.group(2) ?? '';
    if (!_isNetworkOrDataUri(src) && endpoint != null) {
      final url = endpoint.fileDownloadUri(src).toString();
      return '![$alt]($url)';
    }
    return match.group(0)!;
  });

  final imageRefs = <String>[];

  var cleaned = result.replaceAllMapped(_imageDirectiveLineRegex, (match) {
    final line = match.group(0)!.trim();
    if (line.startsWith('@image:')) {
      final path = line.substring('@image:'.length).trim();
      if (path.isNotEmpty) imageRefs.add(path);
    }
    return '';
  });

  cleaned = cleaned.replaceAllMapped(_fileDirectiveLineRegex, (match) {
    final line = match.group(0)!.trim();
    if (line.startsWith('@file:')) {
      final path = line.substring('@file:'.length).trim();
      if (_isImageExtension(path)) {
        if (path.isNotEmpty) imageRefs.add(path);
        return '';
      }
    }
    return match.group(0)!;
  });

  if (imageRefs.isNotEmpty) {
    cleaned = cleaned.replaceAll(_screenshotLineRegex, '');
  }

  cleaned = cleaned.trim();

  if (imageRefs.isEmpty) {
    return cleaned;
  }

  final imageMarkdown = StringBuffer();
  for (final ref in imageRefs) {
    if (ref.isEmpty) continue;
    final name = ref.split('/').last.split('\\').last;
    final url = _resolveMediaUrl(ref, endpoint);
    imageMarkdown.writeln('![$name]($url)');
  }

  final imagesStr = imageMarkdown.toString().trim();
  final singleCleaned = cleaned.replaceAll(RegExp(r'\n{2,}'), '\n');
  if (singleCleaned.isEmpty) {
    return imagesStr;
  }
  if (imagesStr.isEmpty) {
    return singleCleaned;
  }
  return '$singleCleaned\n$imagesStr';
}

/// A stored transcript turn, as a neutral message.
///
/// [SessionMessage.isSystemNote] decides the role *before* `role` does, and it
/// has to. The gateway records a model switch as a marker with `role: "user"`,
/// because strict OpenAI-compatible providers reject a system message that is
/// not first in the list — so reading `role` alone renders "[System: The
/// active model for this chat has changed to …]" as something the user typed.
AgentMessage agentMessageFromHermes(
  SessionMessage message, {
  HermesEndpoint? endpoint,
}) => AgentMessage(
  role: message.isSystemNote
      ? MessageRole.system
      : switch (message.role) {
          'user' => MessageRole.user,
          'assistant' => MessageRole.assistant,
          _ => MessageRole.system,
        },
  text: resolveHermesMessageText(message.text, endpoint: endpoint),
  reasoning: message.reasoning,
  kind: message.displayKind,
);

/// The prompt id an approval is raised under.
///
/// Approvals are keyed by session on the wire — `resolve_gateway_approval`
/// looks the pending gate up by session id and there is no request id to use —
/// so the domain id is derived rather than reported. Derived in one place so
/// the raise and the answer cannot disagree about it.
PromptId approvalPromptId(String sessionId) => PromptId('approval:$sessionId');

/// One control-plane event, as a domain event.
///
/// A free function rather than a method because two callers need it and
/// neither should own it: [HermesBackend] maps for the seam, and the workspace
/// maps for the console it already holds. Pure — the prompt bookkeeping that
/// [HermesBackend.respond] depends on stays with the adapter, because it is
/// state and this is a translation.
///
/// Returns null for a frame that carries nothing worth showing; a tool event
/// with no `tool_id` is the only such case, and it cannot be correlated with
/// anything, so it has nowhere to go.
AgentEvent? agentEventFromHermes(
  String sessionId,
  GatewayEvent event, {
  HermesEndpoint? endpoint,
}) {
  final answer = event.answerText;
  if (answer != null) return TextDelta(sessionId: sessionId, text: answer);

  final reasoning = event.reasoningText;
  if (reasoning != null) {
    return ReasoningDelta(sessionId: sessionId, text: reasoning);
  }

  final block = event.reasoningBlockText;
  if (block != null) return ReasoningBlock(sessionId: sessionId, text: block);

  // The server's spinner text. Its whole purpose is explaining a long wait,
  // and it is emphatically not reasoning — this client folded the two
  // together for months and put `cogitating...` in the middle of the
  // model's thoughts.
  final status = event.statusText;
  if (status != null) return StatusText(sessionId: sessionId, text: status);

  if (event.isPromptExpiry) {
    return PromptExpired(
      sessionId: sessionId,
      id: PromptId(event.requestId ?? ''),
    );
  }

  if (event.isBlockingPrompt) {
    return PromptRaised(
      sessionId: sessionId,
      prompt: agentPromptFromHermes(event.type, event.payload),
    );
  }

  if (event.isApprovalRequest) {
    // An approval *is* a blocking question, so it is one in the domain — with
    // its own kind, because the answer is a decision about the agent rather
    // than information for it. The choices come from the server and vary with
    // context; render them, never hardcode them.
    final request = ApprovalRequest.fromEvent(sessionId, event.payload);
    return PromptRaised(
      sessionId: sessionId,
      prompt: AgentPrompt(
        id: approvalPromptId(sessionId),
        kind: AgentPromptKind.approval,
        question: request.command,
        choices: request.choices,
        subject: request.tool,
        escalated: request.smartDenied,
      ),
    );
  }

  return switch (event.type) {
    HermesEventTypes.messageStart => TurnStarted(sessionId: sessionId),
    HermesEventTypes.messageComplete => TurnFinished(sessionId: sessionId),
    HermesEventTypes.toolGenerating => ToolPreparing(
      sessionId: sessionId,
      toolName: event.payload['name']?.toString() ?? '?',
    ),
    HermesEventTypes.toolStart => switch (event.payload['tool_id']) {
      final Object toolId => ToolStarted(
        sessionId: sessionId,
        toolId: toolId.toString(),
        call: agentToolCallFromHermes(event.payload),
      ),
      null => null,
    },
    HermesEventTypes.toolComplete => switch (event.payload['tool_id']) {
      final Object toolId => ToolFinished(
        sessionId: sessionId,
        toolId: toolId.toString(),
        call: completeToolFromHermes(
          agentToolCallFromHermes(event.payload),
          event.payload,
          endpoint: endpoint,
        ),
      ),
      null => null,
    },
    HermesEventTypes.sessionTitle => SessionChanged(
      sessionId: sessionId,
      session: AgentSession(
        id: sessionId,
        title: event.payload['title']?.toString().trim() ?? '',
      ),
    ),
    // `session.info` carries far more than the model. Two of its fields decide
    // whether this session will stop and ask before doing something
    // destructive, which is not a detail to leave off screen.
    HermesEventTypes.sessionInfo => SessionChanged(
      sessionId: sessionId,
      session: AgentSession(
        id: sessionId,
        title: event.payload['title']?.toString().trim() ?? '',
        model: event.payload['model']?.toString() ?? '',
        cwd: event.payload['cwd']?.toString() ?? '',
        branch: event.payload['branch']?.toString() ?? '',
        approvalMode: event.payload['approval_mode']?.toString() ?? '',
        // Hermes says "nothing will ask" two ways, and reading only one of
        // them showed an unattended session as a supervised one. Derived here
        // rather than in the UI because the rule is this backend's, and the
        // next backend will spell its own posture differently.
        unattended:
            event.payload['yolo'] == true ||
            event.payload['approval_mode'] == 'auto',
        // The server's own verdict on its configuration. Dropping it meant
        // the user found out from behaviour instead.
        warning: event.payload['config_warning']?.toString() ?? '',
      ),
    ),
    // Everything else the server says. Shown as a note from the backend
    // rather than dropped: a notice that turns out to matter is the
    // evidence for promoting it to a real event.
    _ => BackendNotice(
      sessionId: sessionId,
      kind: event.type,
      text: event.payload['text']?.toString() ?? '',
    ),
  };
}

/// The live state a `session.resume` reply reported.
///
/// Hermes tells a client what is happening in a session exactly once, in the
/// reply that opens it — the model it is on, the directory it works in, and
/// any turn already running. There is no method to ask again, which is why the
/// adapter caches this rather than fetching it.
OpenedSession openedSessionFromHermes(
  String durableId,
  ResumedSession resumed,
) => OpenedSession(
  session: AgentSession(
    id: resumed.persistedId.isEmpty ? durableId : resumed.persistedId,
    model: resumed.model,
    cwd: resumed.cwd,
    branch: resumed.branch,
    running: resumed.running,
  ),
  inflight: switch (resumed.inflight) {
    final turn? when !turn.isEmpty => ResumedTurn(
      prompt: turn.user,
      answerSoFar: turn.assistant,
      streaming: turn.streaming,
    ),
    _ => null,
  },
  queuedPrompt: resumed.queuedPrompt ?? '',
);
