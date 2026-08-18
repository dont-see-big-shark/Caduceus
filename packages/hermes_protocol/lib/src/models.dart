import 'package:meta/meta.dart';

/// One row from `session.list`.
@immutable
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.title,
    required this.preview,
    required this.messageCount,
    required this.startedAt,
    required this.source,
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        preview: json['preview']?.toString() ?? '',
        messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
        // Unix seconds as a float.
        startedAt: json['started_at'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                ((json['started_at'] as num) * 1000).round())
            : null,
        source: json['source']?.toString() ?? '',
      );

  final String id;
  final String title;

  /// First user message, truncated by the server. Usually the only thing worth
  /// showing, since [title] is empty for most sessions.
  final String preview;

  final int messageCount;
  final DateTime? startedAt;

  /// Which client created it — `desktop`, `tui`, a messaging platform…
  final String source;

  /// What to show in a list: a real title if there is one, else the preview.
  String get displayLabel {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final p = preview.trim();
    return p.isEmpty ? '(empty session)' : p;
  }
}

/// One turn in a resumed transcript.
@immutable
class SessionMessage {
  const SessionMessage({
    required this.role,
    required this.text,
    this.reasoning,
    this.displayKind = '',
  });

  factory SessionMessage.fromJson(Map<String, dynamic> json) {
    var text = json['text']?.toString() ?? '';
    final content = json['content'];
    if (text.isEmpty && content is String) {
      text = content;
    } else if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is String && part.isNotEmpty) {
          buffer.write(part);
        } else if (part is Map) {
          final type = part['type'];
          if (type == 'text') {
            buffer.write(part['text'] ?? '');
          } else if (type == 'image' || type == 'image_url') {
            final src = part['source'] ?? part['url'] ?? part['image_url'];
            if (src is Map) {
              final data = src['data'] ?? src['url'];
              final mediaType = src['media_type'] ?? 'image/png';
              if (data != null) {
                if ('$data'.startsWith('http') || '$data'.startsWith('data:')) {
                  buffer.write('\n\n![image]($data)\n\n');
                } else {
                  buffer.write('\n\n![image](data:$mediaType;base64,$data)\n\n');
                }
              }
            } else if (src is String && src.isNotEmpty) {
              if (src.startsWith('http') || src.startsWith('data:')) {
                buffer.write('\n\n![image]($src)\n\n');
              } else {
                buffer.write('\n\n![image](data:image/png;base64,$src)\n\n');
              }
            }
          }
        }
      }
      if (text.isEmpty) text = buffer.toString().trim();
    }

    final attachments =
        (json['images'] as List?) ?? (json['attachments'] as List?);
    if (attachments != null && attachments.isNotEmpty) {
      final buffer = StringBuffer();
      for (final img in attachments) {
        if (img is String && img.isNotEmpty) {
          if (img.startsWith('http') || img.startsWith('data:')) {
            buffer.write('![image]($img)\n\n');
          }
        } else if (img is Map) {
          final url = img['url'] ?? img['content'] ?? img['data'];
          final mime = img['mimeType'] ?? img['mime_type'] ?? 'image/png';
          final name = img['name'] ?? img['fileName'] ?? 'image';
          if (url is String && url.isNotEmpty) {
            if (url.startsWith('http') || url.startsWith('data:')) {
              buffer.write('![$name]($url)\n\n');
            } else {
              buffer.write('![$name](data:$mime;base64,$url)\n\n');
            }
          }
        }
      }
      if (buffer.isNotEmpty) {
        text = text.isEmpty
            ? buffer.toString().trim()
            : '${buffer.toString().trim()}\n\n$text';
      }
    }

    return SessionMessage(
      role: json['role']?.toString() ?? 'assistant',
      text: text,
      // Server sends both `reasoning` and `reasoning_content`; they carry the
      // same text. Kept out of [text] so it can be collapsed in the UI.
      reasoning: (json['reasoning'] ?? json['reasoning_content'])?.toString(),
      displayKind: json['display_kind']?.toString() ?? '',
    );
  }

  final String role;
  final String text;
  final String? reasoning;

  /// How the server means this entry to be shown — `model_switch` is the one
  /// that matters so far.
  ///
  /// The gateway records a model change as a marker *with `role: "user"`*,
  /// deliberately: strict OpenAI-compatible providers reject a system message
  /// that is not first in the list, so it has to be a user turn on the wire.
  /// That is a serialisation constraint, not a claim about who said it, and a
  /// client that reads only `role` renders "[System: The active model for this
  /// chat has changed to …]" as something the user typed.
  final String displayKind;

  bool get isUser => role == 'user' && !isSystemNote;

  /// Written by the server, not by a person. Shown, because it explains why
  /// later answers may differ — but never as a question in the transcript.
  ///
  /// Two tests, because one is not enough:
  ///
  ///  * the declared kind, for rows the server stamped. `model_switch`,
  ///    `auto_continue` (a turn resumed after being killed mid-run) and
  ///    `async_delegation_complete` are the three it emits as user-role rows.
  ///  * the `[System:` prefix, for rows written before it stamped anything.
  ///    The server runs exactly this migration for `auto_continue` and simply
  ///    never added the model marker to it, so on a real transcript the field
  ///    arrives empty and the text is the only evidence there is. Verified on
  ///    a live session: without the prefix test the marker still rendered as a
  ///    question the user had supposedly asked.
  bool get isSystemNote =>
      const {
        'model_switch',
        'auto_continue',
        'async_delegation_complete',
      }.contains(displayKind) ||
      (role == 'user' && text.trimLeft().startsWith('[System:'));
}

/// Result of `session.resume`.
///
/// Resume is the load-a-session call: it returns the full transcript inline.
///
/// ## Two different ids
///
/// `session.resume` mints a **new gateway-local handle** —
/// `sid = uuid.uuid4().hex[:8]` in `methods_session.py` — and registers the
/// session in the live `_sessions` map under *that*, not under the persisted
/// id you asked for. The response carries both:
///
///  * `session_id` → [liveId], the handle every later RPC must use
///  * `resumed`    → [persistedId], the durable id `session.list` returns
///
/// `_sess_nowait` looks up `_sessions[session_id]`, so calling
/// `session.title` / `interrupt` / `steer` / `compress` / `approval.respond`
/// with the persisted id fails `session not found` (4001) — verified live.
/// Events are emitted against the gateway handle too, so **event routing must
/// key on [liveId]** or a resumed session receives nothing.
@immutable
/// A turn that was already running when the client resumed.
///
/// `session.resume` carries the accepted prompt and whatever answer text has
/// arrived so far (`server.py`, `_start_inflight_turn` /
/// `_append_inflight_delta`). A client that ignores it shows the transcript
/// without the question currently being answered, and then appends new deltas
/// under nothing — the server source says as much about the queued case:
/// "otherwise the accepted prompt disappears until it finally drains".
@immutable
class InflightTurn {
  const InflightTurn({
    required this.user,
    required this.assistant,
    required this.streaming,
  });

  factory InflightTurn.fromJson(Map<String, dynamic> json) => InflightTurn(
        user: json['user']?.toString() ?? '',
        assistant: json['assistant']?.toString() ?? '',
        streaming: json['streaming'] == true,
      );

  /// The prompt being answered.
  final String user;

  /// Answer text so far. Empty while the model is still thinking.
  final String assistant;

  final bool streaming;

  bool get isEmpty => user.isEmpty && assistant.isEmpty;
}

class ResumedSession {
  const ResumedSession({
    required this.liveId,
    required this.persistedId,
    required this.messages,
    required this.running,
    required this.status,
    required this.model,
    this.inflight,
    this.queuedPrompt,
    this.cwd = '',
    this.branch = '',
  });

  factory ResumedSession.fromJson(Map<String, dynamic> json) => ResumedSession(
        liveId: json['session_id']?.toString() ?? '',
        persistedId:
            (json['resumed'] ?? json['session_id'])?.toString() ?? '',
        messages: ((json['messages'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SessionMessage.fromJson)
            .toList(),
        running: json['running'] == true,
        inflight: switch (json['inflight']) {
          final Map<String, dynamic> m => InflightTurn.fromJson(m),
          _ => null,
        },
        // A prompt accepted while the previous turn was still winding down.
        // It has no answer yet and is invisible everywhere else.
        queuedPrompt: switch (json['queued']) {
          final Map<String, dynamic> m => m['user']?.toString(),
          _ => null,
        },
        status: json['status']?.toString() ?? '',
        model: (json['info'] as Map?)?['model']?.toString() ?? '',
        // The agent's working directory lives on the server, and everything
        // path-shaped — @-completion, attachments, checkpoints — resolves
        // against it. A client that never shows it leaves the user guessing
        // which machine and which directory their words apply to.
        cwd: (json['info'] as Map?)?['cwd']?.toString() ?? '',
        branch: (json['info'] as Map?)?['branch']?.toString() ?? '',
      );

  /// Gateway-local handle. Use for every subsequent RPC and for event routing.
  final String liveId;

  /// Durable id, as listed by `session.list`. Use for display and re-opening.
  final String persistedId;

  final List<SessionMessage> messages;

  /// True when a turn is already in flight — the client should expect deltas
  /// without having submitted anything.
  final bool running;

  /// The turn in progress, if any, with its partial answer.
  final InflightTurn? inflight;

  /// A prompt the server accepted but has not started yet.
  final String? queuedPrompt;

  final String status;
  final String model;

  /// Server-side working directory for this session.
  final String cwd;

  /// Git branch at [cwd], empty when it is not a repository.
  final String branch;
}

/// A pending approval gate, parsed from an `approval.request` event.
///
/// Shapes taken from `_emit_approval_request` in `tui_gateway/server.py`.
/// The valid responses are **not** a boolean and **not** "allow" — the server
/// sends the exact set in [choices], which varies with context:
///
///  * normal            → `once`, `session`, `always`, `deny`
///  * `allow_permanent: false` → `once`, `session`, `deny`
///  * `smart_denied`    → `once`, `deny` (owner override of a Smart DENY)
///
/// `resolve_gateway_approval` stores the choice string verbatim without
/// validating it, so an invented value like "allow" is silently not an
/// approval. Always send one of [choices].
@immutable
class ApprovalRequest {
  const ApprovalRequest({
    required this.sessionId,
    required this.command,
    required this.choices,
    required this.smartDenied,
    required this.raw,
  });

  factory ApprovalRequest.fromEvent(
    String? sessionId,
    Map<String, dynamic> payload,
  ) {
    final choices = ((payload['choices'] as List?) ?? const [])
        .map((c) => c.toString())
        .toList();
    return ApprovalRequest(
      sessionId: sessionId ?? '',
      // Already redacted server-side: credential-shaped values are stripped
      // before the event is emitted, so this is safe to display.
      command: payload['command']?.toString() ?? '',
      choices: choices.isEmpty ? const ['once', 'deny'] : choices,
      smartDenied: payload['smart_denied'] == true,
      raw: payload,
    );
  }

  final String sessionId;

  /// The command awaiting approval, redacted by the server.
  final String command;

  /// Exactly the responses this gate accepts. Render these, do not hardcode.
  final List<String> choices;

  /// True when Smart mode already denied this and the user is overriding.
  final bool smartDenied;

  final Map<String, dynamic> raw;

  String get tool => raw['tool']?.toString() ?? raw['name']?.toString() ?? '';

  /// Human label for a choice value.
  static String labelFor(String choice) => switch (choice) {
        'once' => 'Allow once',
        'session' => 'Allow this session',
        'always' => 'Always allow',
        'deny' => 'Deny',
        _ => choice,
      };

  static bool isDeny(String choice) => choice == 'deny';
}

/// One entry from `commands.catalog`.
@immutable
class SlashCommand {
  const SlashCommand({required this.name, required this.description});
  final String name;
  final String description;

  /// The catalog ships names with the leading slash.
  String get bare => name.startsWith('/') ? name.substring(1) : name;

  bool matches(String query) {
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q);
  }
}

/// A provider row from `model.options`.
@immutable
class ModelProvider {
  const ModelProvider({
    required this.slug,
    required this.name,
    required this.models,
    required this.isCurrent,
    required this.authenticated,
    this.warning = '',
  });

  factory ModelProvider.fromJson(Map<String, dynamic> json) => ModelProvider(
        slug: json['slug']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        models: ((json['models'] as List?) ?? const [])
            .map((m) => m.toString())
            .toList(),
        isCurrent: json['is_current'] == true,
        // An unauthenticated provider is listed but cannot actually be used;
        // showing it as selectable would produce a confusing failure later.
        authenticated: json['authenticated'] == true,
        warning: json['warning']?.toString() ?? '',
      );

  final String slug;
  final String name;
  final List<String> models;
  final bool isCurrent;
  final bool authenticated;
  final String warning;
}

/// Parsed `model.options` response.
@immutable
class ModelInventory {
  const ModelInventory({
    required this.providers,
    required this.currentModel,
    required this.currentProvider,
  });

  factory ModelInventory.fromJson(Map<String, dynamic> json) => ModelInventory(
        providers: ((json['providers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ModelProvider.fromJson)
            .toList(),
        currentModel: json['model']?.toString() ?? '',
        currentProvider: json['provider']?.toString() ?? '',
      );

  final List<ModelProvider> providers;
  final String currentModel;
  final String currentProvider;

  ModelInventory withCurrentModel(String model) => ModelInventory(
        providers: providers,
        currentModel: model,
        currentProvider: currentProvider,
      );
}

/// A scheduled agent run, from `cron.manage {action: list}`.
@immutable
class CronJob {
  const CronJob({
    required this.name,
    required this.schedule,
    required this.prompt,
    required this.enabled,
  });

  factory CronJob.fromJson(Map<String, dynamic> json) => CronJob(
        name: json['name']?.toString() ?? '',
        schedule: json['schedule']?.toString() ?? '',
        prompt: json['prompt']?.toString() ?? '',
        // Absent means enabled; only an explicit false disables.
        enabled: json['enabled'] != false && json['paused'] != true,
      );

  final String name;
  final String schedule;
  final String prompt;
  final bool enabled;
}

/// A file staged into the session workspace by `file.attach`.
@immutable
class FileAttachment {
  const FileAttachment({
    required this.name,
    required this.path,
    required this.refText,
    required this.uploaded,
  });

  factory FileAttachment.fromJson(Map<String, dynamic> json) => FileAttachment(
        name: json['name']?.toString() ?? '',
        path: json['path']?.toString() ?? '',
        // What the user actually pastes into the prompt.
        refText: json['ref_text']?.toString() ?? '',
        // False when the gateway could open the path itself — i.e. the client
        // and the agent share a filesystem.
        uploaded: json['uploaded'] == true,
      );

  final String name;
  final String path;
  final String refText;
  final bool uploaded;
}

/// A filesystem checkpoint the agent took before editing.
@immutable
class Checkpoint {
  const Checkpoint({
    required this.hash,
    required this.timestamp,
    required this.message,
  });

  factory Checkpoint.fromJson(Map<String, dynamic> json) => Checkpoint(
        hash: json['hash']?.toString() ?? '',
        timestamp: json['timestamp']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
      );

  final String hash;
  final String timestamp;
  final String message;

  String get shortHash => hash.length > 8 ? hash.substring(0, 8) : hash;
}

/// A background process owned by a session.
@immutable
class RunningProcess {
  const RunningProcess({
    required this.id,
    required this.command,
    required this.cwd,
    required this.pid,
    required this.status,
    required this.uptimeSeconds,
    required this.outputTail,
    this.exitCode,
  });

  factory RunningProcess.fromJson(Map<String, dynamic> json) => RunningProcess(
        // The registry calls its own id `session_id`, which is not the
        // conversation's session id — do not route events on it.
        id: json['session_id']?.toString() ?? '',
        command: json['command']?.toString() ?? '',
        cwd: json['cwd']?.toString() ?? '',
        pid: (json['pid'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ?? '',
        uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
        // `output_tail` is the 4 KB tail the gateway adds for desktop clients;
        // `output_preview` is the 200-char one from the registry itself.
        outputTail: (json['output_tail'] ?? json['output_preview'])?.toString() ??
            '',
        exitCode: (json['exit_code'] as num?)?.toInt(),
      );

  final String id;
  final String command;
  final String cwd;
  final int pid;
  final String status;
  final int uptimeSeconds;
  final String outputTail;
  final int? exitCode;

  bool get running => status == 'running';
}

/// One `complete.path` suggestion.
@immutable
class PathCompletion {
  const PathCompletion({
    required this.text,
    required this.display,
    required this.meta,
  });

  factory PathCompletion.fromJson(Map<String, dynamic> json) => PathCompletion(
        text: json['text']?.toString() ?? '',
        display: json['display']?.toString() ?? '',
        meta: json['meta']?.toString() ?? '',
      );

  /// What to insert.
  final String text;

  /// What to show — may be shortened or decorated relative to [text].
  final String display;

  /// A short hint: "git diff", "attach file", a file size.
  final String meta;
}

/// One learned skill or memory on the journey timeline.
@immutable
class LearningNode {
  const LearningNode({
    required this.id,
    required this.label,
    required this.body,
    required this.meta,
    required this.style,
  });

  factory LearningNode.fromJson(Map<String, dynamic> json) => LearningNode(
        id: json['id']?.toString() ?? '',
        // `label` is pre-truncated for a terminal column; `fullLabel` is the
        // longer of the two but is still truncated for memory nodes — the
        // complete text travels as `body` when the server includes it.
        label: (json['fullLabel'] ?? json['label'])?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        meta: json['meta']?.toString() ?? '',
        style: json['style']?.toString() ?? '',
      );

  final String id;
  final String label;

  /// The full text when the server sends it in the frames payload.
  ///
  /// Memory nodes carry their complete text here; skill nodes send an empty
  /// body and require `learning.detail` for the file's content.
  final String body;
  final String meta;

  /// `skill` or `memory`. Skills are archived on delete; memories are removed.
  final String style;

  bool get isSkill => style == 'skill';
}

/// One day on the journey timeline.
@immutable
class LearningBucket {
  const LearningBucket({
    required this.label,
    required this.date,
    required this.skills,
    required this.memories,
    required this.color,
    required this.nodes,
  });

  factory LearningBucket.fromJson(Map<String, dynamic> json) => LearningBucket(
        label: json['label']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        skills: (json['skills'] as num?)?.toInt() ?? 0,
        memories: (json['memories'] as num?)?.toInt() ?? 0,
        color: json['color']?.toString() ?? '',
        nodes: ((json['nodes'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LearningNode.fromJson)
            .toList(),
      );

  final String label;
  final String date;
  final int skills;
  final int memories;

  /// `#RRGGBB` from the server's category palette, or empty.
  final String color;
  final List<LearningNode> nodes;

  int get total => skills + memories;
}

/// What the agent has learned, over time.
///
/// `learning.frames` exists to drive a terminal animation and most of its
/// payload is a pre-rendered character grid. That part is ignored here: the
/// same response also carries the structured buckets, categories and summary
/// the grid was rendered *from*, which is what a native view needs.
@immutable
class LearningJourney {
  const LearningJourney({
    required this.buckets,
    required this.categories,
    required this.summary,
    required this.count,
    required this.start,
    required this.end,
  });

  factory LearningJourney.fromJson(Map<String, dynamic> json) {
    final axis = (json['axis'] as Map?) ?? const {};
    return LearningJourney(
      buckets: ((json['buckets'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LearningBucket.fromJson)
          .toList(),
      categories: ((json['categories'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((c) => LearningCategory(
                label: c['label']?.toString() ?? '',
                color: c['color']?.toString() ?? '',
              ))
          .toList(),
      summary: ((json['summary'] as List?) ?? const [])
          .map((s) => s.toString())
          .toList(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      start: axis['start']?.toString() ?? '',
      end: axis['end']?.toString() ?? '',
    );
  }

  final List<LearningBucket> buckets;
  final List<LearningCategory> categories;

  /// Pre-composed lines such as "49 learned skills · 12 memories".
  final List<String> summary;
  final int count;
  final String start;
  final String end;
}

@immutable
class LearningCategory {
  const LearningCategory({required this.label, required this.color});
  final String label;

  /// `#RRGGBB`, or empty for the "+5 more" row.
  final String color;
}

/// A question or credential the agent is blocked waiting on.
///
/// Three server events share one shape. They differ in what the answer *is*,
/// which decides whether the field is masked and which `*.respond` method
/// carries it back.
@immutable
class BlockingPrompt {
  const BlockingPrompt({
    required this.requestId,
    required this.kind,
    required this.question,
    required this.choices,
    required this.multiSelect,
    required this.envVar,
  });

  factory BlockingPrompt.fromEvent(String type, Map<String, dynamic> payload) =>
      BlockingPrompt(
        requestId: payload['request_id']?.toString() ?? '',
        kind: switch (type) {
          'sudo.request' => BlockingPromptKind.sudo,
          'secret.request' => BlockingPromptKind.secret,
          _ => BlockingPromptKind.clarify,
        },
        question:
            (payload['question'] ?? payload['prompt'] ?? '').toString(),
        choices: ((payload['choices'] as List?) ?? const [])
            .map((c) => c.toString())
            .toList(),
        multiSelect: payload['multi_select'] == true,
        envVar: payload['env_var']?.toString() ?? '',
      );

  final String requestId;
  final BlockingPromptKind kind;
  final String question;

  /// Offered answers for a clarify. Empty means free text.
  final List<String> choices;
  final bool multiSelect;

  /// For a secret: the environment variable the server will store it under.
  final String envVar;

  /// True when the answer must never be echoed or logged.
  bool get isSecret => kind != BlockingPromptKind.clarify;
}

enum BlockingPromptKind { clarify, sudo, secret }
