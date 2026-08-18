/// [AgentBackend] over the Hermes control plane.
library;

import 'dart:async';
import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

import 'hermes_mapping.dart';

/// Hermes, behind the neutral interface.
///
/// Thin on purpose. The gateway client already does reconnect, correlation and
/// framing; this translates vocabulary and nothing else, so a bug is either
/// clearly in the wire client or clearly in the mapping. The two places it
/// keeps state are both forced by the protocol and are called out below.
///
/// [gateway] stays reachable because the seven Hermes-only feature panels
/// (checkpoints, cron, journey, projects, processes, agents, server)
/// talk to it directly and always did. They are gated on a [Capability], not
/// squeezed through the core interface — a universal interface wide enough for
/// all of them would force every other backend to stub seven features it does
/// not have.
class HermesBackend implements AgentBackend {
  /// Starts listening immediately, rather than waiting for [connect].
  ///
  /// The gateway is usually already connected by the time an adapter is
  /// wrapped around it — the connect screen opens the socket and hands it
  /// over — so an adapter that only subscribes inside its own `connect()`
  /// never subscribes at all, and every event is dropped while the connection
  /// looks perfectly healthy.
  HermesBackend(this.gateway, {this.profile = 'default'}) {
    _wire();
  }

  final HermesGateway gateway;

  /// Profile used to scope Hermes session operations.
  final String profile;

  @override
  String get id => 'hermes';

  @override
  String get displayName => 'Hermes Agent';

  /// The transcript `session.resume` already returned, keyed by live handle.
  ///
  /// Not a cache in the optimisation sense — it is the *only* copy. Hermes
  /// delivers history as part of opening a session, and its `session.history`
  /// RPC answers `session not found (4001)` for ids that `session.list` just
  /// returned, even straight after a successful resume. So [history] has
  /// nothing to call and must hand back what [open] was given.
  final Map<String, List<AgentMessage>> _transcripts = {};

  /// The live state `session.resume` reported, keyed by live handle.
  ///
  /// Cached for the same reason as [_transcripts], and it is the same reply:
  /// Hermes tells a client what is happening in a session exactly once, at the
  /// moment it opens it. There is no method to ask again.
  final Map<String, OpenedSession> _opened = {};

  /// What kind of question each outstanding prompt was, and where it came
  /// from.
  ///
  /// [respond] is handed an id and an answer, which is all a caller can
  /// reasonably know. Hermes needs more than that: three different `*.respond`
  /// methods take the three kinds, and an approval is answered against the
  /// *session* id rather than the request id. The adapter raised the prompt,
  /// so the adapter is the thing that still knows — which is the interface
  /// working, not a hole in it.
  final Map<String, _PendingPrompt> _pending = {};

  final _connection = StreamController<AgentConnection>.broadcast();
  final Map<String, StreamController<AgentEvent>> _sessionEvents = {};
  StreamSubscription<GatewayConnectionState>? _stateSub;
  StreamSubscription<GatewayEvent>? _eventSub;
  AgentConnection _state = AgentConnection.disconnected;
  var _wired = false;

  @override
  AgentConnection get connectionState => _state;

  @override
  Stream<AgentConnection> get connection async* {
    // Emitted first so a listener that subscribes after the socket is already
    // up is not left staring at a blank status until something changes.
    yield _state;
    yield* _connection.stream;
  }

  @override
  Future<void> connect() async {
    _wire();
    await gateway.connect();
  }

  @override
  Future<bool> verifyConnection() async {
    try {
      await gateway.verifyConnection();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _wire() {
    if (_wired) return;
    _wired = true;
    // Seeded from what the gateway *is*, not from a guess. `connectionState`
    // does not replay, so an adapter that starts at `disconnected` and waits
    // reports a healthy connection as broken until something happens to
    // change it — which for a quiet connection is never.
    _state = _translateState(gateway.state);
    _stateSub = gateway.connectionState.listen((s) {
      _state = _translateState(s);
      if (!_connection.isClosed) _connection.add(_state);
    });
    _eventSub = gateway.events.listen(_route);
  }

  static AgentConnection _translateState(GatewayConnectionState s) =>
      AgentConnection(
        switch (s.status) {
          GatewayStatus.disconnected => AgentStatus.disconnected,
          GatewayStatus.connecting => AgentStatus.connecting,
          GatewayStatus.connected => AgentStatus.connected,
          GatewayStatus.reconnecting => AgentStatus.reconnecting,
          GatewayStatus.fatal => AgentStatus.fatal,
        },
        attempt: s.attempt,
        error: s.error,
      );

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _eventSub?.cancel();
    for (final c in _sessionEvents.values) {
      await c.close();
    }
    _sessionEvents.clear();
    await _connection.close();
    await gateway.dispose();
  }

  @override
  Future<List<AgentSession>> sessions({int limit = 50}) async {
    final rows = await _guard(
      () => gateway.sessions(limit: limit, profile: profile),
    );
    return rows.map(agentSessionFromHermes).toList();
  }

  @override
  Future<SessionHandle> open(String sessionId) async {
    final resumed = await _guard(
      () => gateway.openSession(sessionId, profile: profile),
    );
    // Hermes hands back a *different* live handle from the id that was asked
    // for, and every later frame — RPC and event alike — is addressed with
    // the live one. Routing on the durable id silently drops every event.
    _transcripts[resumed.liveId] = resumed.messages
        .map((m) => agentMessageFromHermes(m, endpoint: gateway.endpoint))
        .toList();
    _opened[resumed.liveId] = openedSessionFromHermes(sessionId, resumed);
    return SessionHandle(
      sessionId: resumed.persistedId.isEmpty ? sessionId : resumed.persistedId,
      wireId: resumed.liveId,
    );
  }

  @override
  Future<SessionHandle> create({
    String? title,
    String? cwd,
    String? model,
  }) async {
    final created = await _guard(
      () => gateway.sessionCreate(cwd: cwd, model: model, profile: profile),
    );
    final live = created['session_id']?.toString() ?? '';
    // `stored_session_id`, not `resumed` — `session.create` spells the durable
    // id differently from `session.resume`, and reading the handle as the
    // durable one means a new session matches no row in the sidebar, so
    // creating one looks like nothing happened.
    final durable = (created['stored_session_id'] ?? created['session_id'])
        ?.toString();
    _transcripts[live] = const [];
    // A new session has no history and no turn running, but it does already
    // have a model — the reply says which one it starts on, and asking again
    // would show the header blank until something else happened to move it.
    final info = (created['info'] as Map?)?.cast<String, dynamic>() ?? const {};
    _opened[live] = OpenedSession(
      session: AgentSession(
        id: durable?.isNotEmpty == true ? durable! : live,
        model: info['model']?.toString() ?? '',
        cwd: info['cwd']?.toString() ?? '',
        branch: info['branch']?.toString() ?? '',
      ),
    );
    return SessionHandle(
      sessionId: durable?.isNotEmpty == true ? durable! : live,
      wireId: live,
    );
  }

  /// A no-op, and correctly so: Hermes pushes every session's events down one
  /// socket whether anyone asked or not, so there is nothing to unsubscribe
  /// from. Closing the local stream is the whole of it.
  @override
  Future<void> release(SessionHandle handle) async {
    _transcripts.remove(handle.wireId);
    _opened.remove(handle.wireId);
    await _sessionEvents.remove(handle.wireId)?.close();
  }

  @override
  Future<OpenedSession> opened(SessionHandle handle) async =>
      _opened[handle.wireId] ??
      OpenedSession(session: AgentSession(id: handle.sessionId));

  @override
  Future<List<AgentMessage>> history(SessionHandle handle) async =>
      _transcripts.remove(handle.wireId) ?? const [];

  /// [clientId] is accepted and dropped. Hermes has no idempotency key, so a
  /// resend is a second prompt; the parameter exists because the *caller* must
  /// mint the key for the backend that does have one, and a caller that only
  /// generates it when it seems needed will not have one at the moment of a
  /// retry.
  @override
  Future<void> send(
    SessionHandle handle,
    String text, {
    required String clientId,
    List<Attachment> attachments = const [],
    bool queued = false,
  }) async {
    // References the staged files earn, appended to the prompt below.
    //
    // `file.attach` stages the bytes and hands back a `ref_text` — "what the
    // user actually pastes into the prompt". Staging alone tells the model
    // nothing: without the reference in the message the file sits in the
    // workspace unmentioned, which looks exactly like an attachment that was
    // dropped. Images need no such thing; `image.attach_bytes` puts the
    // picture in the turn itself.
    final references = <String>[];
    for (final attachment in attachments) {
      if (attachment.isImage) {
        // Both paths send bytes. `image.attach` and `file.attach`'s `path`
        // both name a file the *gateway* must be able to open, which is
        // nothing at all when the gateway is on another machine.
        await _guard(
          () => gateway.imageAttachBytes(
            sessionId: handle.wireId,
            contentBase64: base64Encode(attachment.bytes),
            filename: attachment.name,
            ext: attachment.name.contains('.')
                ? attachment.name.split('.').last.toLowerCase()
                : null,
          ),
        );
        continue;
      }
      final staged = await _guard(
        () => gateway.fileAttach(
          sessionId: handle.wireId,
          name: attachment.name,
          dataUrl:
              'data:${attachment.mimeType};base64,'
              '${base64Encode(attachment.bytes)}',
        ),
      );
      final reference = staged.refText.trim().isEmpty
          ? staged.path.trim()
          : staged.refText.trim();
      if (reference.isNotEmpty) references.add(reference);
    }
    final body = references.isEmpty
        ? text
        : '${text.trimRight()}\n\n${references.join('\n')}';
    await _guard(
      () => gateway.promptSubmit(
        sessionId: handle.wireId,
        text: body,
        // Null rather than false: the server distinguishes "not asked for"
        // from "asked not to", and `session.steer` — the other way a client
        // might park a prompt — succeeds against an idle session and does
        // nothing, which is how a message disappears silently.
        queued: queued ? true : null,
      ),
    );
  }

  @override
  Future<void> interrupt(SessionHandle handle) =>
      _guard(() => gateway.sessionInterrupt(handle.wireId));

  @override
  Future<void> respond(PromptId id, PromptAnswer answer) async {
    final pending = _pending[id.value];
    if (pending == null) {
      throw AgentException(
        AgentFailure.notFound,
        detail: 'That question is no longer open.',
      );
    }
    await _guard(() async {
      switch (pending.kind) {
        case _PromptRoute.clarify:
          await gateway.clarifyRespond(
            requestId: id.value,
            answer: answer.text,
          );
        case _PromptRoute.password:
          await gateway.sudoRespond(requestId: id.value, password: answer.text);
        case _PromptRoute.secret:
          await gateway.secretRespond(requestId: id.value, value: answer.text);
        case _PromptRoute.approval:
          // Keyed on the session, not the request: `resolve_gateway_approval`
          // looks the gate up by session id and stores the choice string
          // verbatim without validating it, so an invented value is silently
          // not an approval.
          await gateway.approvalRespond(
            sessionId: pending.sessionId,
            choice: answer.text,
          );
      }
      return null;
    });
    _pending.remove(id.value);
  }

  /// Flattened out of `model.options`, which is shaped as providers each
  /// holding a list of model names.
  ///
  /// A provider with no credential is listed and marked unavailable rather
  /// than dropped: the gateway reports it because it *could* be used, and
  /// hiding it turns "connect this provider" into a model that does not
  /// appear to exist.
  @override
  Future<List<AgentModel>> models(SessionHandle handle) async {
    // The session id is required, not decorative: `model.options` answers
    // `session not found (4001)` without one, the same way `prompt.submit`
    // does.
    final inventory = ModelInventory.fromJson(
      await _guard(
        () => gateway.modelOptionsFor(handle.wireId, refresh: false),
      ),
    );
    return [
      for (final provider in inventory.providers)
        for (final name in provider.models)
          AgentModel(
            id: name,
            name: name,
            provider: provider.slug,
            available: provider.authenticated,
          ),
    ];
  }

  @override
  Future<void> selectModel(SessionHandle handle, String modelId) async {
    await _guard(
      () => gateway.setModel(sessionId: handle.wireId, model: modelId),
    );
  }

  /// `session.branch` copies the whole transcript when given no count, which
  /// is what branching means to a reader: the same conversation, continued
  /// somewhere else.
  @override
  Future<SessionHandle> branch(SessionHandle handle) async {
    final result = await _guard(() => gateway.sessionBranch(handle.wireId));
    final id = (result['stored_session_id'] ?? result['session_id'])
        ?.toString();
    if (id == null || id.isEmpty) {
      throw AgentException(
        AgentFailure.unknown,
        detail: 'The branch was made but the server did not name it.',
      );
    }
    return open(id);
  }

  /// Three independent reads, folded into one list.
  ///
  /// Concurrent, and each one catches for itself. Not a plain `Future.wait`:
  /// a server that has no plugins answers with an error rather than an empty
  /// list, and a single `wait` turns that into a panel that will not open at
  /// all. Not sequential either — three round trips to fill one panel is a
  /// visible wait on a phone.
  @override
  Future<List<AgentSkill>> skills(SessionHandle handle) async {
    Future<List<AgentSkill>> collect(
      Future<List<Map<String, dynamic>>> Function() read,
      AgentSkill? Function(Map<String, dynamic>) map,
    ) async {
      try {
        return [
          for (final row in await read())
            if (map(row) case final AgentSkill entry) entry,
        ];
      } on Object {
        // Deliberately swallowed. See the doc comment.
        return const [];
      }
    }

    final groups = await Future.wait([
      collect(() => gateway.toolsets(sessionId: handle.wireId), (row) {
        final name = row['name']?.toString().trim() ?? '';
        if (name.isEmpty) return null;
        final count = row['tool_count'];
        return AgentSkill(
          name: name,
          group: SkillGroup.tool,
          description: row['description']?.toString() ?? '',
          enabled: row['enabled'] != false,
          detail: count == null ? '' : '$count tools',
        );
      }),
      collect(gateway.skillsList, (row) {
        final name = row['name']?.toString().trim() ?? '';
        if (name.isEmpty) return null;
        return AgentSkill(
          name: name,
          group: SkillGroup.skill,
          description: row['description']?.toString() ?? '',
        );
      }),
      collect(gateway.pluginsList, (row) {
        final name = row['name']?.toString().trim() ?? '';
        if (name.isEmpty) return null;
        final version = row['version']?.toString() ?? '';
        return AgentSkill(
          name: name,
          group: SkillGroup.plugin,
          enabled: row['enabled'] != false,
          detail: version.isEmpty ? '' : 'v$version',
        );
      }),
    ]);
    return [for (final group in groups) ...group];
  }

  /// The skill library: every `learning.frames` node with `style: 'skill'`.
  ///
  /// A Hermes skill is a SKILL.md file held as a learning node. The frames
  /// listing names them and says nothing else (a skill node's `body` is
  /// empty); the content comes from `learning.detail` per node, fetched
  /// concurrently and best-effort — one unreadable skill costs that skill,
  /// not the library. `learning.add` does not exist, so these are exactly the
  /// skills this agent already has; they are always eligible, because a
  /// learned skill is by definition one the agent can load.
  @override
  Future<List<SkillEntry>> skillLibrary() async {
    // Bounded, like the per-file reads below: a frames call the gateway never
    // answers must fail the library (and let the view call this backend
    // unreachable) rather than leave the panel spinning forever.
    final journey = await gateway.learningJourney().timeout(
      _skillLibraryTimeout,
    );
    final nodes = [
      for (final bucket in journey.buckets)
        for (final node in bucket.nodes)
          if (node.isSkill) node,
    ];
    final contents = await Future.wait([
      for (final node in nodes) _skillContent(node.id),
    ]);
    return [
      for (var i = 0; i < nodes.length; i++)
        SkillEntry(
          key: nodes[i].id,
          title: nodes[i].id,
          backendId: id,
          nativeId: nodes[i].id,
          description: _frontmatterDescription(contents[i]),
          eligible: true,
          content: contents[i],
        ),
    ];
  }

  /// The SKILL.md for a learning node, or null when it cannot be read.
  ///
  /// Timeout-guarded: a gateway call the server never answers must cost that
  /// skill's content, not the whole library — without this, one wedged
  /// `learning.detail` leaves the panel spinning forever.
  Future<String?> _skillContent(String nodeId) async {
    try {
      final raw = await gateway
          .learningDetail(nodeId)
          .timeout(_skillReadTimeout);
      final content = raw['content'];
      return content is String && content.trim().isNotEmpty ? content : null;
    } on Object {
      // Deliberately swallowed. See [skillLibrary].
      return null;
    }
  }

  /// How long one skill-file read may take before its content is given up on.
  static const _skillReadTimeout = Duration(seconds: 20);

  /// How long the whole library read may take before it counts as a failure.
  static const _skillLibraryTimeout = Duration(seconds: 45);

  /// The `description:` line from a SKILL.md's YAML frontmatter, if it has one.
  ///
  /// Best-effort. A folded value (`description: >`) means the real text is on
  /// the following lines, so the marker itself is treated as absent rather
  /// than shown as a description that is just ">".
  static String _frontmatterDescription(String? content) {
    if (content == null) return '';
    final match = RegExp(
      r'^description:\s*(.+)$',
      multiLine: true,
    ).firstMatch(content);
    var value = match?.group(1)?.trim() ?? '';
    if (value.isEmpty || value == '>' || value == '|') return '';
    // Strip one pair of surrounding quotes — `description: "text"`.
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }

  /// Two calls, because Hermes splits the answer.
  ///
  /// `session.usage` counts tokens and `session.context_breakdown` says how
  /// full the window is; the pair is in *both* under different names, so this
  /// reads whichever answered rather than betting on one shape. The old code
  /// dumped the raw JSON and buried the one number anyone opens this for
  /// twelve lines down.
  @override
  Future<AgentUsage> usage(SessionHandle handle) async {
    final usage = await _guard(() => gateway.sessionUsage(handle.wireId));
    Map<String, dynamic> context = const {};
    try {
      context = await gateway.sessionContextBreakdown(handle.wireId);
    } on Object {
      // The token counts are still worth showing without the window.
    }

    int? pair(String key) {
      for (final part in [context, usage]) {
        final value = part[key];
        if (value is num) return value.toInt();
      }
      return null;
    }

    return AgentUsage(
      contextUsed: pair('context_used') ?? 0,
      contextMax: pair('context_max') ?? 0,
      inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
      totalTokens: (usage['total_tokens'] as num?)?.toInt() ?? 0,
      // Everything else, kept rather than dropped: the figure someone came
      // looking for is often one the domain has no field for.
      details: [
        for (final part in [usage, context])
          for (final entry in part.entries)
            if (entry.value is! Map && entry.value is! List)
              (entry.key, '${entry.value}'),
      ],
    );
  }

  @override
  Future<List<AgentTask>> tasks(SessionHandle handle) async {
    final running = await _guard(() => gateway.processList(handle.wireId));
    return [
      for (final p in running)
        AgentTask(
          // The registry calls its own id `session_id`, which is *not* the
          // conversation's — `RunningProcess` already untangles that, and
          // this is the id `process.kill` takes.
          id: p.id,
          title: p.command.isEmpty ? p.id : p.command,
          status: p.exitCode == null ? p.status : '${p.status} (${p.exitCode})',
          detail: [
            if (p.cwd.isNotEmpty) p.cwd,
            if (p.pid != 0) 'pid ${p.pid}',
          ].join(' · '),
          outputTail: p.outputTail,
          startedAt: p.uptimeSeconds == 0
              ? null
              : DateTime.now().subtract(Duration(seconds: p.uptimeSeconds)),
          // Only a live one can be killed, and `status` is the server's word
          // for whether it is. A stop button on an exited process would
          // report success having done nothing.
          canStop: p.exitCode == null && p.status != 'exited',
        ),
    ];
  }

  @override
  Future<void> stopTask(SessionHandle handle, String id) => _guard(
    () => gateway.processKill(sessionId: handle.wireId, processId: id),
  );

  /// `process.stop` kills every process the gateway knows about, not just
  /// this session's. `process.kill` is the scoped one.
  @override
  Future<void> stopAllTasks() => _guard(gateway.processStopAll);

  /// The learning journey, as memory entries.
  ///
  /// `fullLabel` is the text, never `label` — the latter is pre-truncated to
  /// fit a terminal column, and reading it puts an ellipsis in the middle of
  /// every memory the bridge shows. But `fullLabel` is itself truncated on
  /// memory nodes — the complete text travels as `body` — and skill nodes
  /// send no body at all: their content is the SKILL.md file, fetched by
  /// `learning.detail`. So the bridge reads `body` when the frames payload
  /// carries it, and asks `learning.detail` for the rest. A detail call that
  /// fails keeps the label rather than dropping the row.
  ///
  /// A node's `style` is the only kind signal Hermes gives, and the split it
  /// makes is real rather than cosmetic: deleting a skill archives it and
  /// deleting a memory does not, which a later phase has to honour.
  @override
  Future<List<MemoryEntry>> memory() async {
    final journey = await _guard(gateway.learningJourney);
    final nodes = [
      for (final bucket in journey.buckets)
        for (final node in bucket.nodes)
          if (node.id.isNotEmpty) (bucket: bucket, node: node),
    ];
    // Fetch skill bodies concurrently — 50 serial `learning.detail` calls
    // would turn a panel open into a multi-second spinner. Memory nodes carry
    // their body in the frames payload and cost nothing here.
    final texts = await Future.wait([
      for (final row in nodes) _nodeText(row.node),
    ]);
    final entries = <MemoryEntry>[];
    for (var i = 0; i < nodes.length; i++) {
      final bucket = nodes[i].bucket;
      final node = nodes[i].node;
      entries.add(
        MemoryEntry(
          id: 'hermes:${node.id}',
          kind: node.isSkill ? MemoryKind.skill : MemoryKind.fact,
          title: node.meta,
          text: texts[i],
          // The bucket's day, which is the only time Hermes attaches to a
          // node. Not a modification time — the journey is bucketed by
          // when a thing was *learned* — so it is shown as such and never
          // used to decide which side is newer.
          updatedAt: DateTime.tryParse(bucket.date),
          origin: MemoryOrigin(backendId: 'hermes', nativeId: node.id),
        ),
      );
    }
    return entries;
  }

  /// The text to show for [node]: its full `body` when the server sent one,
  /// otherwise the SKILL.md fetched through `learning.detail`, otherwise the
  /// display label rather than dropping the row.
  Future<String> _nodeText(LearningNode node) async {
    if (node.body.isNotEmpty) return node.body;
    if (!node.isSkill) return node.label;
    try {
      final detail = await _guard(() => gateway.learningDetail(node.id));
      final content = detail['content']?.toString() ?? '';
      if (content.isNotEmpty) return content;
    } on Object {
      // A journey that renders is worth more than one row that refuses to
      // load. Fall through to the label.
    }
    return node.label;
  }

  /// Update and remove, never add.
  ///
  /// **There is no `learning.add`.** Anything learned elsewhere can be shown
  /// beside Hermes' memory but cannot be written into it, and declaring that
  /// here is what keeps the UI from offering a push that could only fail.
  @override
  Set<MemoryOp> get supportedMemoryOps => const {
    MemoryOp.update,
    MemoryOp.remove,
  };

  /// Applies [changes] one node at a time.
  ///
  /// Per change rather than per batch, because the interesting case is mixed:
  /// a push carrying two updates and one new memory applies the updates and
  /// reports the third as impossible, and a caller that failed the lot would
  /// make the user re-pick the two that were fine.
  ///
  /// **No staleness guard is possible here.** A Hermes node carries no mtime,
  /// version or etag, so there is nothing to compare a write against — see
  /// `MEMORY_BRIDGE.md` R3. The asymmetry with OpenClaw is stated in the UI
  /// rather than papered over with a guard that does not guard anything.
  @override
  Future<MemoryWriteResult> applyMemory(List<MemoryChange> changes) async {
    final outcomes = <MemoryChangeOutcome>[];
    for (final change in changes) {
      if (change.op == MemoryOp.add) {
        outcomes.add(
          MemoryChangeOutcome.refused(
            change,
            refusal: MemoryWriteRefusal.unsupported,
            detail: 'This server has no method for creating a memory.',
          ),
        );
        continue;
      }
      // The node id, not the ledger id: `learning.edit` and `learning.delete`
      // take the server's own address for it.
      final nodeId = change.entry.origin.nativeId;
      if (nodeId.isEmpty) {
        outcomes.add(
          MemoryChangeOutcome.refused(
            change,
            refusal: MemoryWriteRefusal.notOurs,
            detail: 'That memory has no address on this server.',
          ),
        );
        continue;
      }
      try {
        await _guard(
          () => change.op == MemoryOp.update
              ? gateway.learningEdit(nodeId, change.entry.text)
              : gateway.learningDelete(nodeId),
        );
        outcomes.add(MemoryChangeOutcome.applied(change));
      } on AgentException catch (e) {
        // One node refusing must not stop the rest; the screen lists what
        // happened to each.
        outcomes.add(
          MemoryChangeOutcome.refused(
            change,
            refusal: MemoryWriteRefusal.serverRefused,
            detail: e.detail.isEmpty ? '$e' : e.detail,
          ),
        );
      }
    }
    return MemoryWriteResult(outcomes);
  }

  @override
  Future<List<AgentJob>> jobs() async {
    final rows = await _guard(gateway.cronList);
    return [
      for (final job in rows)
        AgentJob(
          // No separate id on this backend: `cron.manage` keys a job by name.
          id: job.name,
          name: job.name,
          schedule: job.schedule,
          prompt: job.prompt,
          enabled: job.enabled,
        ),
    ];
  }

  @override
  Future<void> createJob({
    required String name,
    required String schedule,
    required String prompt,
  }) => _guard(
    () => gateway.cronAdd(name: name, schedule: schedule, prompt: prompt),
  );

  @override
  Future<List<ServerConfigSection>> serverConfig() async {
    final raw = await _guard(gateway.configShow);
    return [
      for (final section in (raw['sections'] as List?) ?? const [])
        if (section is Map)
          ServerConfigSection(
            title: '${section['title'] ?? ''}',
            rows: [
              for (final row in (section['rows'] as List? ?? const []))
                if (row is List && row.length >= 2) ('${row[0]}', '${row[1]}'),
            ],
          ),
    ];
  }

  /// Fixed, because Hermes' three reloads are three distinct methods rather
  /// than one method with an argument. The labels are what the buttons say.
  static const _reloads = ['.env', 'MCP servers', 'skills'];

  @override
  Future<List<String>> reloadTargets(SessionHandle handle) async => _reloads;

  @override
  Future<void> reloadServer(SessionHandle handle, String target) => _guard(
    () => switch (target) {
      '.env' => gateway.reloadEnv(),
      // Restarting MCP servers is slow enough that the default timeout fails
      // a call that was going to succeed.
      'MCP servers' => gateway.reloadMcp(sessionId: handle.wireId),
      'skills' => gateway.skillsReload(),
      _ => throw AgentException(
        AgentFailure.notFound,
        detail: 'This server cannot reload "$target".',
      ),
    },
  );

  @override
  Stream<AgentEvent> events(SessionHandle handle) =>
      _channel(handle.wireId).stream;

  /// Never emits.
  ///
  /// Hermes has no session-index subscription: `session.info` describes one
  /// session and arrives only for sessions this client resumed. A sidebar that
  /// refreshes when asked is what that absence looks like, and inventing
  /// updates from the per-session stream would report only the sessions
  /// already on screen — the ones a live index is least needed for.
  @override
  Stream<AgentSession> get sessionUpdates => const Stream.empty();

  StreamController<AgentEvent> _channel(String wireId) => _sessionEvents
      .putIfAbsent(wireId, StreamController<AgentEvent>.broadcast);

  /// Hermes is the reference implementation, so it declares everything the
  /// app has ever built a surface for. That is exactly why phase 3 gates the
  /// panels while it is still the only backend: nothing changes visibly, and
  /// the gates get to be wrong somewhere it can be noticed.
  @override
  bool supports(Capability capability) => switch (capability) {
    Capability.channels => false,
    _ => true,
  };

  // -- events ----------------------------------------------------------------

  void _route(GatewayEvent event) {
    final wireId = event.sessionId;
    if (wireId == null) return;
    // Only sessions somebody opened. A broadcast controller created on demand
    // for every id the server mentions would accumulate one per session the
    // user has never looked at.
    final channel = _sessionEvents[wireId];
    if (channel == null || channel.isClosed) return;
    final mapped = _map(wireId, event);
    if (mapped != null) channel.add(mapped);
  }

  /// The translation, plus the one thing the translation cannot do: remember
  /// which of Hermes' four answer paths a raised question belongs to, so
  /// [respond] can be given nothing but an id and still route correctly.
  ///
  /// The route follows from the kind alone, which it did not before
  /// [AgentPromptKind.approval] existed — an approval had to be recognised by
  /// looking back at the wire event it came from. Needing that was the
  /// argument for the enum case.
  AgentEvent? _map(String sessionId, GatewayEvent event) {
    final mapped = agentEventFromHermes(
      sessionId,
      event,
      endpoint: gateway.endpoint,
    );
    switch (mapped) {
      case PromptExpired(:final id):
        _pending.remove(id.value);
      case PromptRaised(:final prompt):
        _pending[prompt.id.value] = _PendingPrompt(switch (prompt.kind) {
          AgentPromptKind.clarify => _PromptRoute.clarify,
          AgentPromptKind.password => _PromptRoute.password,
          AgentPromptKind.secret => _PromptRoute.secret,
          AgentPromptKind.approval => _PromptRoute.approval,
        }, sessionId);
      default:
        break;
    }
    return mapped;
  }

  // -- errors ----------------------------------------------------------------

  /// Runs a gateway call and translates whatever comes out of it.
  ///
  /// Every method on this class goes through here, so nothing above the
  /// adapter ever sees a JSON-RPC code — which is the point of the seam, and
  /// is checked by the fact that `agent_core` does not import `hermes_protocol`
  /// and could not name one.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on GatewayRpcException catch (e) {
      throw AgentException(
        _classify(e),
        code: '${e.code}',
        detail: e.message,
        cause: e,
      );
    } on TransportUpgradeException catch (e) {
      throw AgentException(
        e.isRejected ? AgentFailure.unauthorized : AgentFailure.disconnected,
        code: '${e.statusCode}',
        detail: e.detail ?? '',
        cause: e,
      );
    } on TimeoutException catch (e) {
      throw AgentException(AgentFailure.timeout, cause: e);
    } on StateError catch (e) {
      // The gateway raises this for "disposed" and for calls made with no
      // socket. Both are "not connected" from up here.
      throw AgentException(
        AgentFailure.disconnected,
        detail: e.message,
        cause: e,
      );
    }
  }

  /// 4001 is `session not found`, which the server also answers for a session
  /// `session.list` returned a moment ago. Everything else numeric is opaque
  /// enough that guessing would be worse than saying so.
  static AgentFailure _classify(GatewayRpcException e) => switch (e.code) {
    4001 => AgentFailure.notFound,
    4003 || -32001 => AgentFailure.forbidden,
    -32601 => AgentFailure.unsupported,
    -32602 => AgentFailure.unknown,
    _ => AgentFailure.unknown,
  };

  // -- shared-memory sync (agent-mediated) ----------------------------------

  /// Asks Hermes' own agent to remember [text] via its `memory` tool.
  ///
  /// `SHARED_MEMORY.md` §2: Hermes has no create RPC — `learning.add`,
  /// `memory.*` and `files.*` are all `-32601` on the live gateway — so a new
  /// fact reaches it by asking. The agent writes a `§` entry into
  /// `~/.hermes/memories/MEMORY.md`, which surfaces in `learning.frames` as a
  /// `memory:memory:N` node within ~30 s. This method asks, then polls the
  /// journey until the landed node is found, and returns what *actually*
  /// landed (not the requested text — the agent may reword, and the sync
  /// anchor must record reality). A refusal, an approval gate, a full
  /// MEMORY.md, or a rewrite beyond recognition returns a reason instead.
  Future<({String? nativeId, String? landedText, String detail})>
  syncMemoryViaAgent(String text) async {
    final created = await _guard(() => gateway.sessionCreate());
    final sessionId = (created['session_id'] ?? created['id'] ?? '').toString();
    if (sessionId.isEmpty) {
      return (
        nativeId: null,
        landedText: null,
        detail: 'Could not create a session.',
      );
    }
    try {
      final prompt =
          'Use your memory tool (action=add, target=memory) to add exactly '
          'the following line to MEMORY.md, without changing any words:\n$text';
      await _guard(
        () => gateway.call('prompt.submit', {
          'session_id': sessionId,
          'text': prompt,
        }, const Duration(seconds: 90)),
      );

      // Poll for the landed node. Fingerprint containment tolerates the
      // agent appending or lightly rephrasing; a rewrite that drops the
      // fact's fingerprint is treated as "did not land" — an honest failure.
      final target = MemoryFingerprint.of(text).value;
      for (var attempt = 0; attempt < 10; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 6));
        final journey = await _guard(gateway.learningJourney);
        for (final bucket in journey.buckets) {
          for (final node in bucket.nodes) {
            if (node.id.isEmpty || node.isSkill) continue;
            final body = node.body.isNotEmpty ? node.body : node.label;
            final normalised = MemoryFingerprint.of(body).value;
            if (normalised.contains(target)) {
              return (nativeId: node.id, landedText: body, detail: '');
            }
          }
        }
      }
      return (
        nativeId: null,
        landedText: null,
        detail: 'Hermes did not write the memory within ~60s.',
      );
    } finally {
      try {
        await _guard(
          () => gateway.call('session.close', {
            'session_id': sessionId,
          }, const Duration(seconds: 10)),
        );
      } on Object {
        // Closing a scratch session is cleanup; a socket already gone is fine.
      }
    }
  }

  /// Rewrites one memory node in place — the *restore shared* path.
  ///
  /// [nativeId] is a `memory:memory:N` node id; memory nodes take plain text,
  /// so no SKILL.md frontmatter is needed. Null on success, else the server's
  /// refusal in its own words.
  Future<String?> restoreMemoryNode(String nativeId, String text) async {
    final result = await _guard(() => gateway.learningEdit(nativeId, text));
    if (result['ok'] == true) return null;
    return result['message']?.toString() ?? 'edit refused';
  }

  /// Deletes one memory node — the *drop with copies* path.
  ///
  /// Null on success, else the server's refusal in its own words.
  Future<String?> removeMemoryNode(String nativeId) async {
    final result = await _guard(() => gateway.learningDelete(nativeId));
    if (result['ok'] == true) return null;
    return result['message']?.toString() ?? 'delete refused';
  }
}

enum _PromptRoute { clarify, password, secret, approval }

class _PendingPrompt {
  const _PendingPrompt(this.kind, this.sessionId);
  final _PromptRoute kind;

  /// Needed only by [_PromptRoute.approval], which is answered against the
  /// session rather than the request.
  final String sessionId;
}
