/// [AgentBackend] over an OpenClaw gateway.
library;

import 'dart:async';
import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';

import 'claw_mapping.dart';
import 'claw_memory.dart';

/// OpenClaw, behind the neutral interface.
///
/// Thicker than [HermesBackend] in exactly the places ARCHITECTURE.md §3 said
/// it would be, and nowhere else:
///
///  * **Subscription is real.** Hermes pushes every session down one socket;
///    OpenClaw streams only what was subscribed to, so [open] subscribes and
///    [release] genuinely unsubscribes rather than being a no-op. A client that
///    forgets keeps a conversation nobody is reading streaming forever.
///  * **Events are ordered.** Every event carries `seq` and `stateVersion`,
///    which ride along as an opaque [ResumeCursor].
///  * **Text arrives twice.** `deltaText` and a cumulative snapshot both. The
///    deltas drive the model and the snapshot checks it — see [_reconcile].
///  * **Connecting is two steps.** Handshake, then device pairing. The second
///    is a human gate, and it gets its own status rather than being reported
///    as a failure.
///
/// What it does *not* do is stub the features OpenClaw has no answer for.
/// [supports] declares a much smaller set than Hermes, and the surfaces built
/// on the rest are simply not built.
class ClawBackend implements AgentBackend {
  ClawBackend(this.gateway);

  final ClawGateway gateway;

  @override
  String get id => 'openclaw';

  @override
  String get displayName => 'OpenClaw';

  final _connection = StreamController<AgentConnection>.broadcast();
  final Map<String, StreamController<AgentEvent>> _sessionEvents = {};

  /// What we have accumulated from deltas, per session, so a cumulative
  /// snapshot can be checked against it.
  final Map<String, StringBuffer> _accumulated = {};

  /// Which approval each outstanding question belongs to.
  ///
  /// Same shape as the Hermes adapter's, for the same reason: [respond] is
  /// given an id and an answer, and the backend needs the idempotency key and
  /// the session that raised it. The adapter raised the prompt, so the adapter
  /// remembers.
  final Map<String, String> _promptSessions = {};

  StreamSubscription<ClawEvent>? _eventSub;
  AgentConnection _state = AgentConnection.disconnected;

  @override
  AgentConnection get connectionState => _state;

  @override
  Stream<AgentConnection> get connection async* {
    yield _state;
    yield* _connection.stream;
  }

  void _setState(AgentConnection next) {
    _state = next;
    if (!_connection.isClosed) _connection.add(next);
  }

  /// Connects, and reports the pairing gate as a state rather than an error.
  ///
  /// This is the method the whole [AgentStatus.awaitingApproval] state exists
  /// for. A fresh device gets `NOT_PAIRED` from a *correct* handshake with a
  /// *correct* token — nothing is wrong, nothing about retrying will help, and
  /// the only thing that moves it forward is an operator approving the device
  /// somewhere else. Throwing here would send the user hunting for a bad
  /// credential that is not bad.
  @override
  Future<void> connect() async {
    _setState(const AgentConnection(AgentStatus.connecting));
    _eventSub ??= gateway.events.listen(_route);
    try {
      final hello = await gateway.connect();
      _setState(
        AgentConnection(
          AgentStatus.connected,
          detail: 'protocol ${hello.protocol}, ${hello.serverVersion}',
        ),
      );
    } on ClawRpcException catch (e) {
      if (e.needsPairing) {
        _setState(
          AgentConnection(
            AgentStatus.awaitingApproval,
            detail: e.message.isEmpty
                ? 'Waiting for this device to be approved.'
                : e.message,
          ),
        );
        return;
      }
      _setState(
        AgentConnection(AgentStatus.fatal, error: e, detail: e.message),
      );
      throw _translate(e);
    }
  }

  @override
  Future<bool> verifyConnection() async {
    try {
      await gateway.sessions(limit: 1);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    await _eventSub?.cancel();
    for (final c in _sessionEvents.values) {
      await c.close();
    }
    _sessionEvents.clear();
    await _index.close();
    await _connection.close();
    await gateway.dispose();
  }

  @override
  Future<List<AgentSession>> sessions({int limit = 100}) async {
    final rows = await _guard(() => gateway.sessions(limit: limit));
    return [
      for (final row in rows)
        AgentSession(
          id: row.key,
          title: row.title,
          preview: row.preview,
          source: row.source,
          model: row.model,
          running: row.running,
          updatedAt: row.updatedAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(row.updatedAt!),
        ),
    ];
  }

  /// Subscribes — twice, and that is the point.
  ///
  /// `sessions.subscribe` carries the session *index*: rows appearing, titles
  /// changing. The transcript travels on `sessions.messages.subscribe`, and a
  /// client that calls only the first one connects, lists, sends, and then
  /// waits forever for a reply on a channel it never opened.
  ///
  /// The key is the same on the wire and in the sidebar — OpenClaw has no
  /// second handle — so the two-id machinery collapses to an identity here,
  /// which is exactly what an opaque [SessionHandle] is for.
  @override
  Future<SessionHandle> open(String sessionId) async {
    await _guard(() => gateway.subscribeSessions());
    await _guard(() => gateway.subscribeMessages(sessionId));
    _channel(sessionId);
    _accumulated[sessionId] = StringBuffer();
    // Best effort. A session that cannot describe itself still opens; it just
    // opens without a heading, which beats failing the open over one.
    try {
      final row = await gateway.describeSession(sessionId);
      if (row != null) {
        _described[sessionId] = OpenedSession(
          session: AgentSession(
            id: sessionId,
            title: row.title,
            preview: row.preview,
            source: row.source,
            model: row.model,
            running: row.running,
          ),
        );
      }
    } on ClawRpcException {
      // Undescribed rather than unopened.
    }
    return SessionHandle(sessionId: sessionId, wireId: sessionId);
  }

  @override
  /// [cwd] is ignored, and cannot be otherwise: an OpenClaw session's
  /// workspace comes from its agent, and `sessions.create` has no such
  /// parameter. Nor does it take an idempotency key — the schema forbids
  /// additional properties, so sending one fails the whole request.
  @override
  Future<SessionHandle> create({
    String? title,
    String? cwd,
    String? model,
  }) async {
    // [model] rides `sessions.create`, which needs no operator.admin — only
    // *switching* a running session (`sessions.patch {model}`) is admin-gated
    // on this gateway. So a new OpenClaw session can be born on the chosen
    // model without any elevated scope.
    final key = await _guard(
      () => gateway.createSession(label: title, model: model),
    );
    return open(key);
  }

  /// A real unsubscribe. Skipping it leaves the gateway streaming a
  /// conversation nobody is looking at, which is not free on either end.
  @override
  Future<void> release(SessionHandle handle) async {
    _accumulated.remove(handle.wireId);
    _described.remove(handle.wireId);
    await _sessionEvents.remove(handle.wireId)?.close();
    try {
      await gateway.unsubscribeMessages(handle.wireId);
    } on ClawRpcException {
      // Releasing is cleanup. A gateway that has already forgotten the
      // subscription — after a reconnect, say — is the outcome we wanted.
    }
  }

  /// What the session's own row says about it.
  ///
  /// Read at open time and kept, because `sessions.subscribe` answers with an
  /// acknowledgement rather than a state snapshot. Without it a session opened
  /// directly — from a preset, or before the sidebar has listed anything —
  /// knows nothing about itself and shows its routing address as a heading.
  ///
  /// [OpenedSession.inflight] stays null. Nothing here reports a turn already
  /// running, and null is the absence of a claim rather than a claim that none
  /// is.
  @override
  Future<OpenedSession> opened(SessionHandle handle) async =>
      _described[handle.wireId] ??
      OpenedSession(session: AgentSession(id: handle.sessionId));

  /// What `sessions.describe` said, keyed by session.
  final Map<String, OpenedSession> _described = {};

  /// Idempotency keys this client sent with, most recent last.
  ///
  /// The gateway echoes every stored message to every subscriber, our own
  /// included. Without a way to recognise them, each message a user types
  /// appears twice — once as they typed it and once as the server's copy.
  ///
  /// Bounded, because the echo arrives within a turn and a set that only ever
  /// grows is a slow leak in a client meant to stay open for days. The cap is
  /// far above any plausible echo delay; a key evicted before its copy comes
  /// back would show one message twice, which is why it is not tight.
  final _ownSends = <String>[];
  static const _rememberedSends = 200;

  bool _isOwnSend(String clientId) => _ownSends.contains(clientId);

  void _rememberSend(String clientId) {
    _ownSends.add(clientId);
    if (_ownSends.length > _rememberedSends) {
      _ownSends.removeRange(0, _ownSends.length - _rememberedSends);
    }
  }

  /// `chat.history`, which the gateway display-normalises for UI clients: it
  /// strips inline directive tags and leaked tool-call XML, drops silent-token
  /// rows, and may replace an oversized message with a placeholder. So this is
  /// already the *readable* transcript rather than the raw one, which is what
  /// a transcript view wants.
  @override
  Future<List<AgentMessage>> history(SessionHandle handle) async {
    final rows = await _guard(() => gateway.history(handle.wireId));
    return clawMessagesFromHistory(rows);
  }

  @override
  Future<void> send(
    SessionHandle handle,
    String text, {
    required String clientId,
    List<Attachment> attachments = const [],
    // Accepted and ignored: OpenClaw queues a send behind a running turn on
    // its own, so there is nothing to ask for.
    bool queued = false,
  }) async {
    _accumulated[handle.wireId] = StringBuffer();
    // Remembered so the stored copy of this message, which comes back through
    // the event stream like anybody else's, is not shown a second time.
    _rememberSend(clientId);
    await _guard(
      () => gateway.call('sessions.send', {
        'key': handle.wireId,
        'message': text,
        if (attachments.isNotEmpty)
          'attachments': [
            for (final a in attachments)
              ClawConversation.attachment(
                fileName: a.name,
                mimeType: a.mimeType,
                contentBase64: base64Encode(a.bytes),
              ),
          ],
      }, clientId),
    );
  }

  @override
  Future<void> interrupt(SessionHandle handle) =>
      _guard(() => gateway.abort(handle.wireId));

  @override
  Future<void> respond(PromptId id, PromptAnswer answer) async {
    if (!_promptSessions.containsKey(id.value)) {
      throw AgentException(
        AgentFailure.notFound,
        detail: 'That question is no longer open.',
      );
    }
    await _guard(
      () => gateway.resolveApproval(
        id: id.value,
        // The server's own choice string, verbatim. Inventing a value here
        // would be stored without validation and silently not be an approval.
        decision: answer.text,
      ),
    );
    _promptSessions.remove(id.value);
  }

  /// One catalog for the whole gateway, so the session is not consulted.
  @override
  Future<List<AgentModel>> models(SessionHandle handle) async {
    final rows = await _guard(() => gateway.models());
    return [
      for (final row in rows)
        AgentModel(
          id: '${row['id'] ?? ''}',
          name: '${row['name'] ?? row['alias'] ?? ''}',
          provider: '${row['provider'] ?? ''}',
          // Absent means available; the gateway only says so when it is not.
          available: row['available'] != false,
          contextTokens: (row['contextWindow'] as num?)?.toInt() ?? 0,
          reasoning: row['reasoning'] == true,
        ),
    ];
  }

  @override
  Future<void> selectModel(SessionHandle handle, String modelId) async {
    await _guard(() => gateway.patchSession(handle.wireId, model: modelId));
  }

  /// Forks the transcript into a new session, and opens it.
  ///
  /// The label is left unset: the gateway derives one from the first message,
  /// and labels are unique per gateway — inventing "X (copy)" would collide
  /// the second time anyone branched the same conversation.
  @override
  Future<SessionHandle> branch(SessionHandle handle) async {
    final key = await _guard(
      () => gateway.createSession(parentSessionKey: handle.wireId, fork: true),
    );
    return open(key);
  }

  /// Skills, effective tools and user commands, folded into one list.
  ///
  /// Concurrent, each catching for itself, for the reason
  /// [AgentBackend.skills] describes — and here there is a second: the three
  /// methods carry
  /// *different scopes* in the gateway's own descriptor table. All three are
  /// `operator.read` today, but the surrounding `skills.install` /
  /// `skills.curator.*` family is `operator.admin` — a scope this client
  /// deliberately never asks for — so a build that tightens one of these
  /// should cost that group, not the panel.
  @override
  Future<List<AgentSkill>> skills(SessionHandle handle) async {
    Future<List<AgentSkill>> collect(
      Future<List<AgentSkill>> Function() read,
    ) async {
      try {
        return await read();
      } on Object {
        // Deliberately swallowed. See the doc comment.
        return const [];
      }
    }

    final groups = await Future.wait([
      collect(() async {
        final raw = await gateway.call('skills.status', const {});
        return [
          for (final row in (raw['skills'] as List?) ?? const [])
            if (row is Map && '${row['name'] ?? ''}'.trim().isNotEmpty)
              AgentSkill(
                name: '${row['name']}'.trim(),
                group: SkillGroup.skill,
                description: row['description']?.toString() ?? '',
                // `eligible` already folds in every reason it might not run —
                // disabled in config, blocked by the bundled allowlist, a
                // missing binary, the wrong platform. Reading `disabled` alone
                // called a skill available that the server would refuse to
                // load.
                enabled: row['eligible'] == true,
                detail: _whySkillIsOff(row),
              ),
        ];
      }),
      collect(() async {
        final raw = await gateway.call('tools.effective', {
          'sessionKey': handle.wireId,
        });
        return [
          for (final group in (raw['groups'] as List?) ?? const [])
            if (group is Map)
              for (final tool in (group['tools'] as List?) ?? const [])
                if (tool is Map && _toolName(tool).isNotEmpty)
                  AgentSkill(
                    name: _toolName(tool),
                    // A plugin's tools are the only way this backend reports a
                    // plugin at all, so they are filed as one.
                    group: group['source'] == 'plugin'
                        ? SkillGroup.plugin
                        : SkillGroup.tool,
                    description: tool['description']?.toString() ?? '',
                    detail: [
                      '${group['label'] ?? ''}',
                      if (tool['risk'] != null) '${tool['risk']} risk',
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
        ];
      }),
      collect(() async {
        final raw = await gateway.call('commands.list', const {});
        return [
          for (final row in (raw['commands'] as List?) ?? const [])
            if (row is Map && '${row['name'] ?? ''}'.trim().isNotEmpty)
              AgentSkill(
                name: '/${'${row['name']}'.trim()}',
                group: SkillGroup.command,
                description: row['description']?.toString() ?? '',
                detail: [
                  '${row['source'] ?? ''}',
                  if (row['acceptsArgs'] == true) 'takes arguments',
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
        ];
      }),
    ]);
    return [for (final group in groups) ...group];
  }

  /// The skill library: `skills.status` plus best-effort content.
  ///
  /// `skills.status` (an `operator.read` call) is the whole read side — name,
  /// description, the `eligible` verdict and the evidence for it, the file
  /// path. Content is a separate, per-skill `skills.detail {slug}` call, and
  /// it reads the *ClawHub registry copy*, not the installed file: registry-
  /// published skills answer, and local workspace skills (`trim-cli`, `fnos`)
  /// 404 — which is the honest "no content from here", not a failure of the
  /// library. All writes are `operator.admin` and deliberately absent.
  @override
  Future<List<SkillEntry>> skillLibrary() async {
    // Bounded, like the registry reads below: a status call the gateway never
    // answers must fail the library (and let the view call this backend
    // unreachable) rather than leave the panel spinning forever.
    final raw = await gateway
        .call('skills.status', const {})
        .timeout(_skillLibraryTimeout);
    final rows = (raw['skills'] as List?) ?? const [];
    final entries = <SkillEntry>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final name = '${row['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final skillKey = '${row['skillKey'] ?? ''}'.trim();
      final key = skillKey.isEmpty ? name : skillKey;
      entries.add(
        SkillEntry(
          key: key,
          title: name,
          backendId: id,
          nativeId: key,
          description: row['description']?.toString() ?? '',
          eligible: row['eligible'] == true,
          detail: _whySkillIsOff(row),
          filePath: row['filePath']?.toString(),
        ),
      );
    }
    final contents = await Future.wait([
      for (final entry in entries) _skillContent(entry.nativeId),
    ]);
    return [
      for (var i = 0; i < entries.length; i++)
        entries[i].copyWith(content: contents[i]),
    ];
  }

  /// The registry SKILL.md for a skill, or null when it cannot be read.
  ///
  /// `skills.detail` queries ClawHub by slug, so a local-only skill answers
  /// `404 Skill not found` and an ambiguous slug answers `409` — both are
  /// "no registry copy", swallowed here. Timeout-guarded for the same reason
  /// as the Hermes side: one unanswered call must cost content, not the
  /// library.
  Future<String?> _skillContent(String slug) async {
    try {
      final raw = await gateway
          .call('skills.detail', {'slug': slug})
          .timeout(_skillReadTimeout);
      final skill = raw['skill'];
      if (skill is Map) {
        final content = skill['description'];
        if (content is String && content.trim().isNotEmpty) return content;
      }
      return null;
    } on Object {
      // Deliberately swallowed. See [skillLibrary].
      return null;
    }
  }

  /// How long one registry read may take before its content is given up on.
  static const _skillReadTimeout = Duration(seconds: 20);

  /// How long the whole library read may take before it counts as a failure.
  static const _skillLibraryTimeout = Duration(seconds: 45);

  /// A tool's label, falling back to its id — `label` is what a person reads
  /// and `id` is what the schema guarantees.
  static String _toolName(Map<Object?, Object?> tool) {
    final label = '${tool['label'] ?? ''}'.trim();
    return label.isNotEmpty ? label : '${tool['id'] ?? ''}'.trim();
  }

  /// Why a skill will not run, in the server's own terms.
  ///
  /// `skills.status` reports the verdict *and* the evidence for it. Showing
  /// only the verdict makes a greyed row a mystery — "installed but off" is
  /// not an answer, "needs the `gh` binary" is.
  static String _whySkillIsOff(Map<Object?, Object?> row) {
    if (row['eligible'] == true) {
      return row['bundled'] == true ? 'bundled' : '${row['source'] ?? ''}';
    }
    if (row['disabled'] == true) return 'disabled in config';
    if (row['blockedByAllowlist'] == true) return 'not in the allowlist';
    if (row['platformIncompatible'] == true) return 'not for this platform';
    final missing = row['missing'];
    if (missing is Map) {
      for (final entry in missing.entries) {
        final values = entry.value;
        if (values is List && values.isNotEmpty) {
          return 'missing ${entry.key}: ${values.join(', ')}';
        }
      }
    }
    return 'unavailable';
  }

  /// Tokens and money for this session. No context figure, and none faked.
  ///
  /// `sessions.usage` totals what a session has *spent*; there is no live
  /// context-occupancy number anywhere in this gateway's contract, so
  /// [AgentUsage.contextMax] stays zero and the meter is simply not drawn.
  /// Inventing one from a model's advertised window would be a number that
  /// looks measured and is not.
  ///
  /// `key` is the session key — the same identity every other method here
  /// takes, and not the `sessionId` in the same row.
  @override
  Future<AgentUsage> usage(SessionHandle handle) async {
    final raw = await _guard(
      () => gateway.call('sessions.usage', {'key': handle.wireId}),
    );
    final totals = raw['totals'] is Map
        ? (raw['totals'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    int count(String key) => (totals[key] as num?)?.toInt() ?? 0;

    return AgentUsage(
      inputTokens: count('input'),
      outputTokens: count('output'),
      totalTokens: count('totalTokens'),
      costUsd: (totals['totalCost'] as num?)?.toDouble() ?? 0,
      details: [
        if (raw['startDate'] != null) ('range starts', '${raw['startDate']}'),
        if (raw['endDate'] != null) ('range ends', '${raw['endDate']}'),
        // Cache traffic is most of the token count on a long session and is
        // the reason input + output does not equal the total.
        if (count('cacheRead') > 0) ('cache read', '${count('cacheRead')}'),
        if (count('cacheWrite') > 0) ('cache write', '${count('cacheWrite')}'),
        // The server's own admission that it could not price some of this.
        if (count('missingCostEntries') > 0)
          ('unpriced entries', '${count('missingCostEntries')}'),
      ],
    );
  }

  /// The task ledger, scoped to this session.
  ///
  /// Wider than Hermes' notion: this includes sub-agent runs and flows, not
  /// only spawned OS processes. That is the right answer to the question the
  /// panel asks — "what did this session start that is still going?" — and
  /// narrowing it to something process-shaped would hide the delegated runs
  /// that are the more common cause of a session that will not settle.
  @override
  Future<List<AgentTask>> tasks(SessionHandle handle) async {
    final raw = await _guard(
      () => gateway.call('tasks.list', {'sessionKey': handle.wireId}),
    );
    return [
      for (final row in (raw['tasks'] as List?) ?? const [])
        if (row is Map && '${row['id'] ?? ''}'.isNotEmpty)
          AgentTask(
            id: '${row['id']}',
            title: '${row['title'] ?? ''}'.trim().isNotEmpty
                ? '${row['title']}'.trim()
                : '${row['kind'] ?? row['id']}',
            status: '${row['status'] ?? ''}',
            detail: [
              '${row['runtime'] ?? ''}',
              '${row['progressSummary'] ?? row['terminalSummary'] ?? ''}',
              if (row['error'] != null) 'error: ${row['error']}',
            ].where((s) => s.isNotEmpty).join(' · '),
            startedAt: _timestamp(row['startedAt'] ?? row['createdAt']),
            // `tasks.cancel` is `operator.write`, which this client has — but
            // only a task that has not ended can be cancelled, and the ledger
            // says which. A terminal status with a stop button would report
            // success having done nothing.
            canStop: _liveStatuses.contains('${row['status'] ?? ''}'),
          ),
    ];
  }

  /// The statuses a task can still be cancelled from.
  ///
  /// An allowlist rather than a denylist of terminal ones: a status this
  /// client has never seen should read as *not stoppable*, because the cost
  /// of guessing wrong that way is a missing button rather than a button that
  /// lies.
  static const _liveStatuses = {'pending', 'queued', 'running', 'active'};

  @override
  Future<void> stopTask(SessionHandle handle, String id) =>
      _guard(() => gateway.call('tasks.cancel', {'taskId': id}));

  /// Absent, like every other server-wide power here. There is no
  /// cancel-everything method, and building one out of `tasks.list` +
  /// `tasks.cancel` would be this client inventing a destructive operation
  /// the server never offered.
  @override
  Future<void> stopAllTasks() async => throw AgentException(
    AgentFailure.notFound,
    detail: 'This gateway has no stop-everything.',
  );

  /// A gateway timestamp, which may be epoch millis or an ISO string.
  static DateTime? _timestamp(Object? value) => switch (value) {
    final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
    final String text => DateTime.tryParse(text),
    _ => null,
  };

  /// What the agent remembers: `MEMORY.md`, plus the persona documents.
  ///
  /// Read live, and the wire settled two things a schema could not. `list`
  /// does **not** carry content — every file needs its own `get` — and a file
  /// that has never been written answers `missing: true` with an empty string
  /// rather than an error, which is a state to show rather than a failure to
  /// report. `updatedAtMs` is the change marker; `size` is bytes while the
  /// content is UTF-16, so the two disagree by design and only one of them is
  /// safe to compare.
  ///
  /// Reads are concurrent and each catches for itself, for the reason
  /// [skills] does: a workspace missing one document should cost that
  /// document, not the panel.
  @override
  Future<List<MemoryEntry>> memory() async {
    final agentId = await _defaultAgentId();
    final stamps = await _fileTimestamps(agentId);
    // Remembered for R3: a later write compares against what this read saw.
    _lastSeenStamps = stamps;

    Future<List<MemoryEntry>> read(
      String name,
      List<MemoryEntry> Function(String content, DateTime? at) parse,
    ) async {
      try {
        final raw = await gateway.call('agents.files.get', {
          'agentId': agentId,
          'name': name,
        });
        final file = (raw['file'] as Map?) ?? const {};
        if (file['missing'] == true) return const [];
        return parse('${file['content'] ?? ''}', stamps[name]);
      } on Object {
        return const [];
      }
    }

    final groups = await Future.wait([
      read(clawMemoryFile, clawMemoriesFromMarkdown_),
      for (final name in clawPersonaFiles)
        read(name, (content, at) {
          final entry = clawPersonaEntry(name, content, updatedAt: at);
          return entry == null ? const [] : [entry];
        }),
    ]);
    return [for (final group in groups) ...group];
  }

  static List<MemoryEntry> clawMemoriesFromMarkdown_(
    String content,
    DateTime? at,
  ) => clawMemoriesFromMarkdown(content, updatedAt: at);

  /// `updatedAtMs` per file, from the one call that reports it.
  ///
  /// Best effort: a workspace that will not list still reads, it just reads
  /// without timestamps. Phase 3 needs these for optimistic concurrency; phase
  /// 1 shows them as "last changed".
  Future<Map<String, DateTime>> _fileTimestamps(String agentId) async {
    try {
      final raw = await gateway.call('agents.files.list', {'agentId': agentId});
      return {
        for (final f in (raw['files'] as List?) ?? const [])
          if (f is Map && f['updatedAtMs'] is num)
            '${f['name']}': DateTime.fromMillisecondsSinceEpoch(
              (f['updatedAtMs'] as num).toInt(),
            ),
      };
    } on Object {
      return const {};
    }
  }

  /// Which agent's workspace to read.
  ///
  /// Every `agents.files.*` call requires an explicit `agentId` and the
  /// gateway will not infer one. Cached because it does not change while the
  /// connection lives, and asking again on every panel open is a round trip
  /// for an answer we already have.
  String? _agentId;

  Future<String> _defaultAgentId() async {
    final known = _agentId;
    if (known != null) return known;
    try {
      final raw = await gateway.call('agents.list', const {});
      final rows = (raw['agents'] as List?) ?? const [];
      for (final row in rows) {
        if (row is Map && '${row['id'] ?? ''}'.isNotEmpty) {
          return _agentId = '${row['id']}';
        }
      }
    } on Object {
      // Fall through to the conventional default.
    }
    return _agentId = 'main';
  }

  /// Everything, because the block is ours to rewrite wholesale.
  ///
  /// Unlike Hermes, which has no way to create a memory, this backend owns a
  /// delimited region of `MEMORY.md` and can put anything in it.
  @override
  Set<MemoryOp> get supportedMemoryOps =>
      supports(Capability.memoryWrite) ? MemoryOp.values.toSet() : const {};

  /// The `updatedAtMs` of each file as of the last [memory] read.
  ///
  /// The basis of `MEMORY_BRIDGE.md` R3. The agent writes its own memory, so
  /// the file can move between the read a person is looking at and the write
  /// they press — and a whole-file `set` from a stale read destroys whatever
  /// arrived in between.
  Map<String, DateTime> _lastSeenStamps = const {};

  /// Applies [changes] to the block this app owns in `MEMORY.md`.
  ///
  /// The four rules, in the order they are enforced:
  ///
  ///  * **R5** — only `agents.files.list`, `.get` and `.set` are ever sent,
  ///    even though the device holds `operator.admin`.
  ///  * **R3** — the file's `updatedAtMs` is re-read first and the whole write
  ///    is refused if it moved. Refused, not merged: a person looking at a
  ///    diff of yesterday's file must not silently overwrite today's.
  ///  * **R2** — every change is applied to the *parsed block*, so nothing
  ///    outside it can be removed. A line the user typed above the markers is
  ///    not reachable from here.
  ///  * **R1** — the splice itself, in [MemoryBlock.write], which keeps every
  ///    byte outside the markers identical.
  @override
  Future<MemoryWriteResult> applyMemory(List<MemoryChange> changes) async {
    if (changes.isEmpty) return const MemoryWriteResult([]);
    if (!supports(Capability.memoryWrite)) {
      return MemoryWriteResult([
        for (final change in changes)
          MemoryChangeOutcome.refused(
            change,
            refusal: MemoryWriteRefusal.unsupported,
            detail:
                'Writing memory needs operator.admin, which this device '
                'has not been granted.',
          ),
      ]);
    }

    final agentId = await _defaultAgentId();

    // Persona documents are whole files, not entries in a block, so they take
    // a different path — see [_applyPersona]. Split first so a push carrying
    // both kinds does the right thing with each rather than the wrong thing
    // with one.
    final persona = [
      for (final c in changes)
        if (c.entry.kind == MemoryKind.persona) c,
    ];
    final blockChanges = [
      for (final c in changes)
        if (c.entry.kind != MemoryKind.persona) c,
    ];

    final personaOutcomes = persona.isEmpty
        ? const <MemoryChangeOutcome>[]
        : await _applyPersona(agentId, persona);
    if (blockChanges.isEmpty) return MemoryWriteResult(personaOutcomes);

    // R3, before anything else is touched.
    final stamps = await _fileTimestamps(agentId);
    final seen = _lastSeenStamps[clawMemoryFile];
    final now = stamps[clawMemoryFile];
    if (seen != null && now != null && now != seen) {
      return MemoryWriteResult([
        ...personaOutcomes,
        for (final change in blockChanges)
          MemoryChangeOutcome.refused(
            change,
            refusal: MemoryWriteRefusal.staleRead,
            detail: '$clawMemoryFile changed on the server since it was read.',
          ),
      ]);
    }

    final current = await _guard(
      () => gateway.call('agents.files.get', {
        'agentId': agentId,
        'name': clawMemoryFile,
      }),
    );
    final file = (current['file'] as Map?) ?? const {};
    final content = file['missing'] == true ? '' : '${file['content'] ?? ''}';

    // R2: the ops act on what is inside our markers and nothing else.
    final block = MemoryBlock.parse(content);
    final managed = clawMemoriesFromMarkdown(block.body);
    final outcomes = <MemoryChangeOutcome>[...personaOutcomes];

    for (final change in blockChanges) {
      switch (change.op) {
        case MemoryOp.add:
          managed.add(change.entry);
          outcomes.add(MemoryChangeOutcome.applied(change));
        case MemoryOp.update:
          final at = managed.indexWhere(
            (e) => e.origin.nativeId == change.entry.origin.nativeId,
          );
          if (at < 0) {
            // Not in our block. It may well exist in the file — the agent or
            // the user wrote it — and rewriting it from here would be editing
            // someone else's text.
            outcomes.add(
              MemoryChangeOutcome.refused(
                change,
                refusal: MemoryWriteRefusal.notOurs,
                detail: 'That memory is not in the block this app manages.',
              ),
            );
            break;
          }
          managed[at] = change.entry;
          outcomes.add(MemoryChangeOutcome.applied(change));
        case MemoryOp.remove:
          final before = managed.length;
          managed.removeWhere(
            (e) => e.origin.nativeId == change.entry.origin.nativeId,
          );
          outcomes.add(
            managed.length == before
                ? MemoryChangeOutcome.refused(
                    change,
                    refusal: MemoryWriteRefusal.notOurs,
                    detail: 'Only memories this app wrote can be removed.',
                  )
                : MemoryChangeOutcome.applied(change),
          );
      }
    }

    if (!outcomes.skip(personaOutcomes.length).any((o) => o.applied)) {
      return MemoryWriteResult(outcomes);
    }

    // R1: splice, never replace.
    await _guard(
      () => gateway.call('agents.files.set', {
        'agentId': agentId,
        'name': clawMemoryFile,
        'content': MemoryBlock.write(content, renderClawMemoryBlock(managed)),
      }),
    );
    // The file we just wrote is now the one we have seen, or the very next
    // write would refuse itself for having moved.
    _lastSeenStamps = {..._lastSeenStamps, ...await _fileTimestamps(agentId)};
    return MemoryWriteResult(outcomes);
  }

  /// Replaces whole workspace documents — `SOUL.md` and its siblings.
  ///
  /// **The one destructive operation in this bridge.** A persona document is
  /// prose, not a list, so there is no block to splice: pushing one really
  /// does overwrite what was there. Three things follow, and all three are
  /// here rather than in the UI, because a caller that forgot any of them
  /// would lose the file:
  ///
  ///  * **The previous content is kept** in the ledger before the write, so
  ///    the act is reversible. An irreversible overwrite is a feature nobody
  ///    will try twice.
  ///  * **Only the three known documents may be written.** `agents.files.set`
  ///    would happily write `AGENTS.md`, the file that tells the agent how to
  ///    operate, and a bug that sent a persona there would rewrite its
  ///    instructions.
  ///  * **Removal is refused outright.** Deleting `SOUL.md` is not a memory
  ///    operation; it is breaking the agent.
  Future<List<MemoryChangeOutcome>> _applyPersona(
    String agentId,
    List<MemoryChange> changes,
  ) async {
    final outcomes = <MemoryChangeOutcome>[];

    // The refusals that need no server: a delete, or a name outside the
    // allowlist. Settled first so a push of nothing but those costs no round
    // trip at all — and so the answer does not depend on the server being
    // reachable to say "this was never allowed".
    final actionable = <MemoryChange>[];
    for (final change in changes) {
      final name = change.entry.origin.nativeId;
      if (change.op == MemoryOp.remove) {
        outcomes.add(
          MemoryChangeOutcome.refused(
            change,
            refusal: MemoryWriteRefusal.unsupported,
            detail:
                'Deleting $name would break the agent, not forget a memory.',
          ),
        );
        continue;
      }
      if (!isClawPersonaFile(name)) {
        outcomes.add(
          MemoryChangeOutcome.refused(
            change,
            refusal: MemoryWriteRefusal.notOurs,
            detail: '$name is not one of the documents this app may write.',
          ),
        );
        continue;
      }
      actionable.add(change);
    }
    if (actionable.isEmpty) return outcomes;

    final stamps = await _fileTimestamps(agentId);
    for (final change in actionable) {
      final name = change.entry.origin.nativeId;

      // R3, per file: these move independently of MEMORY.md.
      final seen = _lastSeenStamps[name];
      final now = stamps[name];
      if (seen != null && now != null && now != seen) {
        outcomes.add(
          MemoryChangeOutcome.refused(
            change,
            refusal: MemoryWriteRefusal.staleRead,
            detail: '$name changed on the server since it was read.',
          ),
        );
        continue;
      }

      try {
        final current = await gateway.call('agents.files.get', {
          'agentId': agentId,
          'name': name,
        });
        final file = (current['file'] as Map?) ?? const {};
        final previous = file['missing'] == true
            ? ''
            : '${file['content'] ?? ''}';

        await gateway.call('agents.files.set', {
          'agentId': agentId,
          'name': name,
          'content': change.entry.text,
        });

        // The value is the one read *before* the write — a backup of what
        // replaced it would be worthless. But the call happens *after* it, so
        // a `set` that fails leaves the existing backup alone: recording
        // first meant a refused push destroyed the only copy of the version
        // the user actually wanted back.
        await onOverwrite?.call(id, name, previous);
        outcomes.add(MemoryChangeOutcome.applied(change));
      } on ClawRpcException catch (e) {
        outcomes.add(
          MemoryChangeOutcome.refused(
            change,
            refusal: MemoryWriteRefusal.serverRefused,
            detail: e.message,
          ),
        );
      }
    }
    _lastSeenStamps = {..._lastSeenStamps, ...await _fileTimestamps(agentId)};
    return outcomes;
  }

  /// Called with what a document held before it was overwritten.
  ///
  /// A hook rather than a direct call into the ledger, because this adapter
  /// depends on nothing above the seam and should keep it that way. The
  /// workspace wires it to the ledger.
  Future<void> Function(String backendId, String name, String previous)?
  onOverwrite;

  /// The scheduler's jobs, read-only.
  ///
  /// `cron.list` is `operator.read`; `cron.add`, `cron.update`, `cron.remove`
  /// and `cron.run` are all `operator.admin`. So this backend can show the
  /// schedule and — for a chat-scoped device — not change it, which is what
  /// [Capability.cronEditing] exists to express.
  @override
  Future<List<AgentJob>> jobs() async {
    final raw = await _guard(
      () => gateway.call('cron.list', const {'includeDisabled': true}),
    );
    return [
      for (final row in (raw['jobs'] as List?) ?? const [])
        if (row is Map && '${row['id'] ?? ''}'.isNotEmpty)
          AgentJob(
            id: '${row['id']}',
            name: '${row['displayName'] ?? row['name'] ?? row['id']}',
            schedule: _renderSchedule(row['schedule']),
            prompt: _jobPrompt(row['payload']),
            enabled: row['enabled'] != false,
            nextRunAt: _timestamp(row['nextRunAtMs']),
            lastRunAt: _timestamp(row['lastRunAtMs']),
            lastRunStatus: '${row['lastRunStatus'] ?? ''}',
          ),
    ];
  }

  /// Schedules an agent turn on a cron expression.
  ///
  /// `cron.add` demands more than the three fields a caller supplies, and the
  /// two extras are decisions rather than defaults, so they are made here and
  /// stated:
  ///
  ///  * `sessionTarget: isolated` — a scheduled run gets its own session
  ///    rather than appearing partway through a conversation someone is
  ///    reading. `main` would interleave a 09:00 briefing into whatever was
  ///    on screen.
  ///  * `wakeMode: next-heartbeat` — the scheduler's own pacing, rather than
  ///    forcing the gateway awake. `now` exists for jobs whose whole point is
  ///    punctuality, which a client cannot know on the caller's behalf.
  ///
  /// Refused for a device without `operator.admin`, which is why
  /// [Capability.cronEditing] gates the button that reaches this.
  @override
  Future<void> createJob({
    required String name,
    required String schedule,
    required String prompt,
  }) => _guard(
    () => gateway.call('cron.add', {
      'name': name,
      'schedule': {'kind': 'cron', 'expr': schedule},
      'sessionTarget': 'isolated',
      'wakeMode': 'next-heartbeat',
      'payload': {'kind': 'agentTurn', 'message': prompt},
    }),
  );

  /// A schedule as a person would say it.
  ///
  /// OpenClaw models this as a tagged union — `at`, `every`, `cron`,
  /// `on-exit` — where Hermes stores one cron string. Rendered here rather
  /// than in the domain because three of those four have no cron expression
  /// to give, and inventing one would be a schedule that reads as exact and
  /// is not.
  static String _renderSchedule(Object? schedule) {
    if (schedule is! Map) return '';
    return switch (schedule['kind']) {
      'cron' => [
        '${schedule['expr'] ?? ''}',
        if (schedule['tz'] != null) '(${schedule['tz']})',
      ].join(' '),
      'at' => 'once, at ${schedule['at']}',
      'every' => 'every ${_every(schedule['everyMs'])}',
      'on-exit' => 'when `${schedule['command']}` exits',
      _ => '${schedule['kind'] ?? ''}',
    };
  }

  static String _every(Object? ms) {
    final millis = (ms as num?)?.toInt() ?? 0;
    if (millis <= 0) return '?';
    final seconds = millis ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    if (seconds < 86400) return '${seconds ~/ 3600}h';
    return '${seconds ~/ 86400}d';
  }

  /// What the job asks for, when it asks in words at all.
  ///
  /// A job's payload is a union too: an agent turn carries a `message`, but a
  /// `systemEvent` carries `text` and a command carries `argv`. Showing the
  /// last two under a heading that says "prompt" would misdescribe them, so
  /// they are rendered as what they are.
  static String _jobPrompt(Object? payload) {
    if (payload is! Map) return '';
    return switch (payload['kind']) {
      'systemEvent' => 'system event: ${payload['text'] ?? ''}',
      'command' => '\$ ${(payload['argv'] as List?)?.join(' ') ?? ''}',
      _ => '${payload['message'] ?? ''}',
    };
  }

  /// The redacted snapshot `config.get` returns, flattened into sections.
  ///
  /// The gateway hands back the config tree with secrets already blanked —
  /// redaction is the *server's* job and this client must never undo it, so
  /// the values are passed through verbatim. Top-level keys become sections
  /// and leaf paths become rows, because a tree with no schema behind it is a
  /// report, not something to build an editor from.
  @override
  Future<List<ServerConfigSection>> serverConfig() async {
    final raw = await _guard(() => gateway.call('config.get', const {}));
    final snapshot = raw['config'] is Map ? raw['config'] as Map : raw;
    final sections = <ServerConfigSection>[];
    final loose = <(String, String)>[];
    for (final entry in snapshot.entries) {
      final key = '${entry.key}';
      final value = entry.value;
      if (value is Map && value.isNotEmpty) {
        sections.add(
          ServerConfigSection(title: key, rows: _flatten(value, '')),
        );
      } else {
        loose.add((key, _render(value)));
      }
    }
    if (loose.isNotEmpty) {
      sections.insert(0, ServerConfigSection(title: 'General', rows: loose));
    }
    return sections;
  }

  static List<(String, String)> _flatten(
    Map<Object?, Object?> node,
    String at,
  ) {
    final rows = <(String, String)>[];
    for (final entry in node.entries) {
      final path = at.isEmpty ? '${entry.key}' : '$at.${entry.key}';
      final value = entry.value;
      if (value is Map && value.isNotEmpty) {
        rows.addAll(_flatten(value, path));
      } else {
        rows.add((path, _render(value)));
      }
    }
    return rows;
  }

  static String _render(Object? value) => switch (value) {
    null => '—',
    final List list => list.isEmpty ? '(none)' : list.join(', '),
    final Map map => map.isEmpty ? '(none)' : '${map.length} entries',
    _ => '$value',
  };

  /// Nothing, and [Capability.serverMaintenance] is false to match.
  ///
  /// Every reload-shaped method this gateway has — `config.apply`,
  /// `skills.install`, `gateway.restart.request` — is `operator.admin` in the
  /// descriptor table, and this client pairs with read/write/approvals. The
  /// buttons would be refused, so they are not built.
  @override
  Future<List<String>> reloadTargets(SessionHandle handle) async => const [];

  @override
  Future<void> reloadServer(SessionHandle handle, String target) async =>
      throw AgentException(
        AgentFailure.notFound,
        detail: 'This gateway does not take reload requests from a client.',
      );

  @override
  Stream<AgentEvent> events(SessionHandle handle) =>
      _channel(handle.wireId).stream;

  @override
  Stream<AgentSession> get sessionUpdates => _index.stream;

  /// The session index, for every session rather than the open ones.
  ///
  /// `sessions.subscribe` is per connection and carries changes for all of
  /// them, so this is where a session started on a phone or finished by a
  /// scheduled job becomes visible. [_route] can only reach sessions with an
  /// open channel, which is exactly the set a live index is least needed for.
  final _index = StreamController<AgentSession>.broadcast();

  StreamController<AgentEvent> _channel(String wireId) => _sessionEvents
      .putIfAbsent(wireId, StreamController<AgentEvent>.broadcast);

  /// What this *connection* may do — not what the gateway implements.
  ///
  /// The distinction is the bug this method used to have. `sessions.patch` is
  /// scoped `dynamic` in the descriptor table, and the rule behind that word
  /// is an allowlist of fields a write-scoped operator may set:
  /// `key, agentId, label, category, pinned, archived, unread`. **`model` is
  /// not in it**, so switching a model needs `operator.admin` — a scope this
  /// client deliberately never asks for. Declaring [Capability.modelSwitching]
  /// unconditionally therefore built a picker that listed every model
  /// correctly and then failed on the tap, which is the exact failure the
  /// capability system exists to prevent.
  ///
  /// So the answer comes from [_scopes] — what the gateway *granted* this
  /// device, reported in the hello's `auth.scopes` — rather than from a
  /// constant. A device paired with `operator.admin` gets the model picker and
  /// this one does not, which is the honest answer in both cases.
  ///
  /// The remaining falses are genuine absences. There is no
  /// checkpoint surface this client would recognise, and no browsable memory:
  /// `doctor.memory.*` probes the search index's health, which is not the same
  /// question as "what has it learned", and OpenClaw's memory lives in files
  /// the agent reads with tools rather than behind a gateway method.
  @override
  bool supports(Capability capability) => switch (capability) {
    // `operator.read` — lists, history, subscriptions, and every report.
    Capability.history ||
    Capability.toolCalls ||
    Capability.skills ||
    Capability.serverConfig ||
    Capability.usageReporting ||
    Capability.cron ||
    // `agents.files.list` and `agents.files.get` are read; writing them is
    // `operator.admin`, which is why memoryWrite is a separate capability and
    // is not claimed here.
    Capability.memoryRead ||
    Capability.channels => _can(_read),
    // `operator.write` — sending, and everything that rides on a send.
    Capability.fileAttach ||
    Capability.imageAttach ||
    Capability.sessionBranching => _can(_write),
    // `tasks.list` is read and `tasks.cancel` is write; the surface needs
    // both to be whole, and a list with a dead stop button is not.
    Capability.backgroundProcesses => _can(_read) && _can(_write),
    Capability.approvals => _can(_approvals),
    // See the doc comment: the model field is admin-only on this gateway,
    // and so is every mutation of the cron schedule.
    Capability.modelSwitching || Capability.cronEditing => _can(_admin),
    // `agents.files.set` is `operator.admin`, unlike the `.list`/`.get` that
    // memoryRead needs — which is why they are two capabilities.
    Capability.memoryWrite => _can(_admin),
    _ => false,
  };

  static const _read = 'operator.read';
  static const _write = 'operator.write';
  static const _approvals = 'operator.approvals';
  static const _admin = 'operator.admin';

  /// True when the granted scopes cover [scope].
  ///
  /// `operator.admin` satisfies everything — that is the gateway's own rule,
  /// not a convenience — and `operator.write` implies `operator.read`, which
  /// is the one other implication its authorizer encodes.
  bool _can(String scope) {
    final granted = _scopes;
    if (granted.contains(_admin)) return true;
    if (granted.contains(scope)) return true;
    return scope == _read && granted.contains(_write);
  }

  /// The scopes this session can actually use.
  ///
  /// The hello reports what the *device* was approved for — which can be more
  /// than this connection asked for — while the gateway authorizes each RPC
  /// against what the *session* requested. A device approved with
  /// `operator.admin` but connected with `chatScopes` alone gets a hello that
  /// lists admin and a `agents.files.set` that answers `missing scope`. So
  /// the honest answer is the intersection: what we asked for and were
  /// granted, not what the device happens to hold.
  ///
  /// Before the handshake lands, fall back to the request — a connect screen
  /// builds its menus while the socket is still opening, and the request is a
  /// bounded optimistic guess that becomes exact the moment the hello does.
  List<String> get _scopes {
    final granted = gateway.hello?.scopes;
    if (granted == null) return gateway.scopes;
    return [
      for (final scope in gateway.scopes)
        if (granted.contains(scope)) scope,
    ];
  }

  // -- events ----------------------------------------------------------------

  void _route(ClawEvent event) {
    final sessionId = _sessionOf(event);
    if (sessionId == null) return;

    // Ahead of the per-session routing: an index change matters most for a
    // session this client has *not* opened, and the routing below drops those.
    if (event.name == 'sessions.changed' && !_index.isClosed) {
      _index.add(_sessionRowFromEvent(sessionId, event.payload));
    }
    final channel = _sessionEvents[sessionId];
    if (channel == null || channel.isClosed) return;
    for (final mapped in _map(sessionId, event)) {
      channel.add(mapped);
    }
  }

  /// A stored message, as whatever the reader still needs to be told.
  Iterable<AgentEvent> _fromStoredMessage(
    String sessionId,
    Map<String, dynamic> row,
    ResumeCursor? cursor,
  ) sync* {
    final message = clawMessageFromRow(row);

    // Tool rows already arrived as `session.tool`, in more detail and while
    // they were happening. Rendering them twice is the cost of taking both.
    if (message.toolCall != null) return;

    if (message.role == MessageRole.user) {
      // Ours came back to us. It has been on screen since it was typed.
      if (_isOwnSend(clawRowClientId(row))) return;
      yield MessageAppended(
        sessionId: sessionId,
        message: message,
        cursor: cursor,
      );
      return;
    }

    // The settled answer. Compared with what the deltas built rather than
    // appended, because in the ordinary case it is the same text arriving a
    // second time — and in the case that matters, the deltas never came and
    // this is the only copy there is.
    //
    // Not [_reconcile], which treats an empty accumulator as a prefix and
    // stays quiet: right for a snapshot that arrived ahead of its deltas,
    // wrong here. This message is *settled*, so where it differs at all it is
    // the copy that stands.
    final stored = message.text;
    if (stored.isEmpty) return;
    final ours = _accumulated.putIfAbsent(sessionId, StringBuffer.new);
    if (ours.toString() == stored) return;
    ours
      ..clear()
      ..write(stored);
    yield TextReset(sessionId: sessionId, text: stored, cursor: cursor);
  }

  /// One `sessions.changed` payload, as a session row.
  static AgentSession _sessionRowFromEvent(
    String id,
    Map<String, dynamic> payload,
  ) => AgentSession(
    id: id,
    title: '${payload['label'] ?? payload['displayName'] ?? ''}',
    preview: '${payload['lastMessagePreview'] ?? ''}',
    source:
        '${(payload['origin'] as Map?)?['provider'] ?? payload['lastChannel'] ?? ''}',
    model: '${payload['model'] ?? ''}',
    running: payload['hasActiveRun'] == true || payload['status'] == 'running',
    updatedAt: payload['updatedAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(payload['updatedAt'] as int)
        : null,
  );

  /// Which session an event belongs to.
  ///
  /// A gateway that considers the subscription to have scoped things already
  /// may not tag the event at all. With exactly one session open that is
  /// unambiguous; with more than one it is not, and guessing would put one
  /// conversation's reply into another's transcript. Dropping is the lesser
  /// harm, and it is visible.
  String? _sessionOf(ClawEvent event) {
    final tagged = event.payload['sessionKey'] ?? event.payload['key'];
    if (tagged != null) return '$tagged';
    return _sessionEvents.length == 1 ? _sessionEvents.keys.first : null;
  }

  Iterable<AgentEvent> _map(String sessionId, ClawEvent event) sync* {
    final cursor = event.seq == null && event.stateVersion == null
        ? null
        : ResumeCursor({'seq': event.seq, 'stateVersion': event.stateVersion});

    final delta = event.payload['deltaText'];
    if (delta is String && delta.isNotEmpty) {
      // `replace` is the protocol's own word for "this is not a continuation".
      // Protocol v4 sets it on a non-prefix replacement and puts the whole
      // replacement text in deltaText. Reading it means a correction is a
      // stated fact rather than something inferred by comparing strings —
      // which is what the reconciliation below had to do, and still does for
      // the snapshots that carry no flag.
      if (event.payload['replace'] == true) {
        _accumulated[sessionId] = StringBuffer(delta);
        yield TextReset(sessionId: sessionId, text: delta, cursor: cursor);
      } else {
        _accumulated.putIfAbsent(sessionId, StringBuffer.new).write(delta);
        yield TextDelta(sessionId: sessionId, text: delta, cursor: cursor);
      }
    }

    // The cumulative snapshot, which is the *check* and never the source.
    //
    // Only `message`. `text` was accepted here too and should not have been:
    // it is the most generic field name on the wire, so any unrelated event
    // carrying one — a notice, a status line — would be reconciled against
    // the answer, disagree with it, and raise a TextReset that replaced the
    // reply with something that was never part of it. A snapshot has to be
    // named as a snapshot.
    final snapshot = event.payload['message'];
    if (snapshot is String) {
      final correction = _reconcile(sessionId, snapshot);
      if (correction != null) {
        yield TextReset(sessionId: sessionId, text: correction, cursor: cursor);
      }
    }

    // A whole stored message. Somebody else may be talking to this agent —
    // from a phone, a chat channel, another window — and a client that
    // ignores these shows half a conversation with no sign the other half
    // exists. It is also what makes a transcript self-healing: when the
    // deltas for an answer never arrive, the stored copy still does.
    if (event.name == 'session.message') {
      final row = (event.payload['message'] as Map?)?.cast<String, dynamic>();
      if (row == null) return;
      yield* _fromStoredMessage(sessionId, row, cursor);
      return;
    }

    // Tool lifecycle. Ahead of the catch-all below, which would otherwise
    // report every phase of every call as an unrecognised notice.
    if (event.name == 'session.tool') {
      final data = (event.payload['data'] as Map?)?.cast<String, dynamic>();
      if (data != null) {
        final mapped = clawToolEvent(sessionId, data, cursor: cursor);
        if (mapped != null) yield mapped;
      }
      return;
    }

    // An approval that has been answered — by this client or another one.
    // Withdrawn rather than re-raised: matching every event with "approval"
    // in its name meant the resolution put the question straight back on
    // screen, now unanswerable.
    if (event.name.endsWith('approval.resolved')) {
      final id = _approvalId(event.payload);
      if (id != null) {
        _promptSessions.remove(id);
        yield PromptExpired(
          sessionId: sessionId,
          id: PromptId(id),
          cursor: cursor,
        );
      }
      return;
    }

    final approval = _approvalOf(event);
    if (approval != null) {
      _promptSessions[approval.id.value] = sessionId;
      yield PromptRaised(
        sessionId: sessionId,
        prompt: approval,
        cursor: cursor,
      );
      return;
    }

    if (_isFinal(event)) {
      // `stopReason` is the gateway's own word for why. Anything but a clean
      // stop is reported as such rather than smoothed into "completed" — a
      // turn cut short and a turn that finished look identical otherwise.
      final stop = event.payload['stopReason']?.toString() ?? 'stop';
      yield TurnFinished(
        sessionId: sessionId,
        reason: switch (stop) {
          'stop' || 'end_turn' || 'complete' => FinishReason.completed,
          'abort' || 'aborted' || 'cancelled' => FinishReason.interrupted,
          _ => FinishReason.failed,
        },
        detail: stop == 'stop' ? '' : stop,
        cursor: cursor,
      );
      return;
    }

    // `sessions.changed` is both the run lifecycle and the session's own
    // metadata — a derived title arriving, the model resolving, a run
    // starting and ending. Reported as both, because the header shows one and
    // the timeline the other.
    if (event.name == 'sessions.changed') {
      final payload = event.payload;
      if (payload['phase'] == 'start') {
        yield TurnStarted(sessionId: sessionId, cursor: cursor);
      }
      yield SessionChanged(
        sessionId: sessionId,
        cursor: cursor,
        session: AgentSession(
          id: sessionId,
          // A gateway derives a title from the first message *after* the
          // session exists, so a new conversation is named while it is being
          // had. Without this the header keeps whatever it opened with.
          title: '${payload['label'] ?? payload['displayName'] ?? ''}',
          model: '${payload['model'] ?? ''}',
          running:
              payload['hasActiveRun'] == true || payload['status'] == 'running',
        ),
      );
      return;
    }

    // Anything with something to say and no known meaning is still worth
    // surfacing. Only when it *has* something to say: `agent` heartbeats
    // arrive several times a turn carrying nothing a reader could use, and an
    // empty notice per beat is churn through every listener for no gain.
    final notice = event.payload['text']?.toString() ?? '';
    if (delta is! String && snapshot is! String && notice.isNotEmpty) {
      yield BackendNotice(
        sessionId: sessionId,
        kind: event.name,
        text: notice,
        cursor: cursor,
      );
    }
  }

  /// The server's full text, if it disagrees with ours. Null when they match.
  ///
  /// The alternative to raising a correction is picking a side silently, and
  /// then a transcript that has drifted from what the agent actually said
  /// looks exactly like one that has not. A visible correction is the lesser
  /// evil — and a prefix match is not a disagreement, only a snapshot that
  /// arrived before the delta that completes it.
  String? _reconcile(String sessionId, String snapshot) {
    final ours = _accumulated.putIfAbsent(sessionId, StringBuffer.new);
    final text = ours.toString();
    if (text == snapshot) return null;
    if (snapshot.startsWith(text)) {
      ours
        ..clear()
        ..write(snapshot);
      return null;
    }
    ours
      ..clear()
      ..write(snapshot);
    return snapshot;
  }

  /// The id an approval is answered against.
  ///
  /// `exec.approval.resolve` takes it as `id`; the request event has been seen
  /// to spell it `requestId`. Both are read, because guessing one and being
  /// wrong means an approval nobody can answer.
  static String? _approvalId(Map<String, dynamic> payload) {
    final value =
        payload['requestId'] ?? payload['id'] ?? payload['request_id'];
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  }

  static AgentPrompt? _approvalOf(ClawEvent event) {
    // Only a *request* raises a question. `resolved` is handled above and
    // anything else with "approval" in its name — a policy change, a list —
    // is not a question at all.
    if (!event.name.endsWith('approval.requested') &&
        !event.name.endsWith('approval.request')) {
      return null;
    }
    final payload = event.payload;
    final requestId = _approvalId(payload);
    if (requestId == null) return null;
    final choices = (payload['choices'] as List?)?.map((c) => '$c').toList();
    return AgentPrompt(
      id: PromptId(requestId),
      kind: AgentPromptKind.approval,
      question:
          (payload['command'] ?? payload['question'] ?? payload['reason'] ?? '')
              .toString(),
      // The server's set when it sent one. `allow`/`deny` is the documented
      // shape of `exec.approval.resolve` and the only safe default.
      choices: choices == null || choices.isEmpty
          ? const ['allow', 'deny']
          : choices,
    );
  }

  /// Watched on a live gateway, not guessed at.
  ///
  /// A turn ends with an event named `chat` carrying `state: "final"` and a
  /// `stopReason`. There is no `chat.done` and no `final: true`; the earlier
  /// reading waited for both and hung, which looks exactly like an agent that
  /// has stopped responding. The flag is kept as a cheap fallback.
  static bool _isFinal(ClawEvent event) =>
      (event.name == 'chat' && event.payload['state'] == 'final') ||
      event.payload['final'] == true;

  // -- plumbing --------------------------------------------------------------

  /// No idempotency keys are minted here.
  ///
  /// Only `sessions.send` accepts one, and its key comes from the caller —
  /// which is the whole reason [send] takes a `clientId`. Every other
  /// side-effecting method on this backend has a schema that forbids the
  /// field outright.

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on ClawRpcException catch (e) {
      throw _translate(e);
    } on TimeoutException catch (e) {
      throw AgentException(AgentFailure.timeout, cause: e);
    }
  }

  /// OpenClaw's string codes, classified.
  ///
  /// Note that `retryable` and `retryAfterMs` come from the *server* rather
  /// than being inferred from the code — the useful difference from JSON-RPC's
  /// numbers, and the reason [AgentException] carries a retry hint that Hermes
  /// simply never sets.
  static AgentException _translate(ClawRpcException e) => AgentException(
    switch (e) {
      _ when e.needsPairing => AgentFailure.notPaired,
      _ when e.needsGatewayToken => AgentFailure.unauthorized,
      _ when e.retryable => AgentFailure.transient,
      _ => switch (e.code) {
        'DISCONNECTED' => AgentFailure.disconnected,
        'TIMEOUT' => AgentFailure.timeout,
        'FORBIDDEN' => AgentFailure.forbidden,
        'NOT_FOUND' => AgentFailure.notFound,
        'UNKNOWN_METHOD' || 'METHOD_NOT_FOUND' => AgentFailure.unsupported,
        _ => AgentFailure.unknown,
      },
    },
    code: e.detailCode == null ? e.code : '${e.code}/${e.detailCode}',
    detail: e.message,
    retryAfter: e.retryAfterMs == null
        ? null
        : Duration(milliseconds: e.retryAfterMs!),
    cause: e,
  );
}
