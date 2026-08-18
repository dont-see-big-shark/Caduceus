import 'gateway_client.dart';
import 'models.dart';

/// Typed wrappers over the control-plane methods the console needs.
///
/// Parameter names are taken from the `@method` handlers in `tui_gateway/` on
/// v0.19.x and exercised against a live server. An earlier version of this file
/// guessed them and was wrong in six places — `prompt.submit` takes `text`, not
/// `message`, and returns `session not found (4001)` when `session_id` is
/// omitted. Do not add a wrapper here without checking the handler.
///
/// ## Almost everything takes an explicit `session_id`
///
/// A previous version of this file claimed `session.history`, `session.usage`,
/// `session.context_breakdown` and `session.steer` acted on an implicit
/// connection-scoped session. That was wrong: they resolve the session through
/// the `_sess(params, rid)` helper in `tui_gateway/server.py`, which reads
/// `params["session_id"]`. Omitting it yields `session not found (4001)` even
/// immediately after a successful `session.resume`.
///
/// Only `session.list` and `session.create` take no session id. Everything
/// else is addressed explicitly, which is the easier model — one connection can
/// drive several sessions without activation races.
extension HermesConsole on HermesGateway {
  // -- session lifecycle -----------------------------------------------------

  /// `limit` is optional; the server decides the default page size.
  Future<Map<String, dynamic>> sessionList({int? limit, String? profile}) async =>
      _asMap(await call('session.list', {
        if (limit != null) 'limit': limit,
        if (profile != null && profile.isNotEmpty) 'profile': profile,
      }));

  /// Typed form of [sessionList].
  Future<List<SessionSummary>> sessions({int? limit, String? profile}) async {
    final raw = await sessionList(limit: limit, profile: profile);
    return ((raw['sessions'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SessionSummary.fromJson)
        .toList();
  }

  /// Creates *and activates* a new session. Does not accept a session id —
  /// the server mints one (`uuid4().hex[:8]`) and returns it as `session_id`.
  Future<Map<String, dynamic>> sessionCreate({
    String? model,
    String? cwd,
    String? profile,
    String? parentSessionId,
    List<Map<String, dynamic>>? seedMessages,
  }) async =>
      _asMap(await call('session.create', {
        if (model != null) 'model': model,
        if (cwd != null) 'cwd': cwd,
        if (profile != null) 'profile': profile,
        if (parentSessionId != null) 'parent_session_id': parentSessionId,
        if (seedMessages != null) 'messages': seedMessages,
      }));

  /// Opens a session and returns its transcript. Prefer [openSession].
  Future<Map<String, dynamic>> sessionResume(
    String sessionId, {
    bool? lazy,
    String? profile,
  }) async =>
      _asMap(await call('session.resume', {
        'session_id': sessionId,
        if (lazy != null) 'lazy': lazy,
        if (profile != null) 'profile': profile,
      }));

  /// Opens a session and returns its full transcript.
  ///
  /// This — not `session.history` — is how a client loads an existing
  /// conversation.
  Future<ResumedSession> openSession(
    String sessionId, {
    String? profile,
  }) async =>
      ResumedSession.fromJson(await sessionResume(sessionId, profile: profile));

  /// Takes `session_id`.
  Future<Map<String, dynamic>> sessionInterrupt(String sessionId) async =>
      _asMap(await call('session.interrupt', {'session_id': sessionId}));

  /// `count` is how many messages to carry over into the branch.
  Future<Map<String, dynamic>> sessionBranch(
    String sessionId, {
    int? count,
    String? name,
  }) async =>
      _asMap(await call('session.branch', {
        'session_id': sessionId,
        if (count != null) 'count': count,
        if (name != null) 'name': name,
      }));

  // -- per-session queries ----------------------------------------------------

  /// Answers `session not found` (4001) for sessions returned by
  /// `session.list`, even immediately after a successful resume. Use
  /// [openSession] to load a transcript; this is kept only for completeness.
  Future<Map<String, dynamic>> sessionHistory(String sessionId) async =>
      _asMap(await call('session.history', {'session_id': sessionId}));

  Future<Map<String, dynamic>> sessionUsage(String sessionId) async =>
      _asMap(await call('session.usage', {'session_id': sessionId}));

  Future<Map<String, dynamic>> sessionContextBreakdown(String sessionId) async =>
      _asMap(await call('session.context_breakdown', {'session_id': sessionId}));

  /// Redirects a running turn without discarding it.
  Future<Map<String, dynamic>> sessionSteer(
    String sessionId,
    String text,
  ) async =>
      _asMap(await call('session.steer', {
        'session_id': sessionId,
        'text': text,
      }));

  Future<Map<String, dynamic>> sessionUndo(String sessionId) async =>
      _asMap(await call('session.undo', {'session_id': sessionId}));

  /// Permanently removes a session and its transcript.
  Future<Map<String, dynamic>> sessionDelete(String sessionId) async =>
      _asMap(await call('session.delete', {'session_id': sessionId}));

  /// Renames a session. The server also sets titles itself, emitting a
  /// `session.title` event.
  Future<Map<String, dynamic>> sessionTitle(
    String sessionId,
    String title,
  ) async =>
      _asMap(await call('session.title', {
        'session_id': sessionId,
        'title': title,
      }));

  /// Drops the session from the gateway's live set without deleting it.
  Future<Map<String, dynamic>> sessionClose(String sessionId) async =>
      _asMap(await call('session.close', {'session_id': sessionId}));

  /// Summarises history to reclaim context, optionally around a topic.
  Future<Map<String, dynamic>> sessionCompress(
    String sessionId, {
    String? focusTopic,
  }) async =>
      _asMap(await call('session.compress', {
        'session_id': sessionId,
        if (focusTopic != null) 'focus_topic': focusTopic,
      }));

  // -- slash commands --------------------------------------------------------

  /// Every slash command the server knows, as `[name, description]` pairs.
  /// Around 30 KB on a stock install, so fetch once and cache.
  Future<List<SlashCommand>> slashCommands() async {
    final raw = await commandsCatalog();
    return ((raw['pairs'] as List?) ?? const [])
        .whereType<List>()
        .where((p) => p.isNotEmpty)
        .map((p) => SlashCommand(
              name: p.first.toString(),
              description: p.length > 1 ? p[1].toString() : '',
            ))
        .toList();
  }

  Future<Map<String, dynamic>> commandResolve(String name) async =>
      _asMap(await call('command.resolve', {'name': name}));

  /// Runs a slash command in a session. [arg] is everything after the name.
  Future<Map<String, dynamic>> commandDispatch({
    required String sessionId,
    required String name,
    String arg = '',
  }) async =>
      _asMap(await call('command.dispatch', {
        'session_id': sessionId,
        'name': name,
        'arg': arg,
      }));

  /// Sets a config value.
  ///
  /// [scope] defaults to `session` deliberately: this writes to the server's
  /// configuration, and a global scope would change behaviour for every session
  /// on someone's machine. Never omit it.
  Future<Map<String, dynamic>> configSet({
    required String sessionId,
    required String key,
    required Object value,
    String scope = 'session',
    bool confirmExpensiveModel = false,
  }) async =>
      _asMap(await call('config.set', {
        'session_id': sessionId,
        'key': key,
        'value': value,
        'scope': scope,
        if (confirmExpensiveModel) 'confirm_expensive_model': true,
      }));

  Future<Map<String, dynamic>> configGet(String key) async =>
      _asMap(await call('config.get', {'key': key}));

  /// Switches the model for one session only.
  ///
  /// [provider] disambiguates. The server parses this value the same way the
  /// CLI parses `/model` arguments — `"sonnet --provider anthropic"` is its
  /// own documented example — and when a model name is declared by more than
  /// one configured provider it refuses to guess, answering *"'x' is declared
  /// by multiple configured providers (…). Re-run with --provider <slug>"*.
  /// A picker that groups models by provider already knows which one the user
  /// pointed at, so there is no reason to make them find out the hard way.
  Future<Map<String, dynamic>> setModel({
    required String sessionId,
    required String model,
    String? provider,
    bool confirmExpensive = false,
  }) =>
      configSet(
        sessionId: sessionId,
        key: 'model',
        value: provider == null || provider.isEmpty
            ? model
            : '$model --provider $provider',
        confirmExpensiveModel: confirmExpensive,
      );

  /// Model inventory for the picker. [refresh] re-queries providers, which is
  /// slow — leave it false for the common case.
  Future<Map<String, dynamic>> modelOptionsFor(
    String sessionId, {
    bool refresh = false,
  }) async =>
      _asMap(await call('model.options', {
        'session_id': sessionId,
        if (refresh) 'refresh': true,
      }));

  // -- prompting -------------------------------------------------------------

  /// Submits a prompt. Output arrives as `message.delta` events on
  /// [HermesGateway.events], not in this call's result.
  ///
  /// `session_id` is required — omitting it yields `session not found (4001)`
  /// even when a session is active.
  Future<Map<String, dynamic>> promptSubmit({
    required String sessionId,
    required String text,
    bool? queued,
  }) async =>
      _asMap(await call('prompt.submit', {
        'session_id': sessionId,
        'text': text,
        if (queued != null) 'queued': queued,
      }));

  Future<Map<String, dynamic>> promptBackground({
    required String sessionId,
    required String text,
  }) async =>
      _asMap(await call('prompt.background', {
        'session_id': sessionId,
        'text': text,
      }));

  // -- approvals -------------------------------------------------------------

  /// Resolves a pending approval.
  ///
  /// Takes a `choice` string (server default `deny`) rather than a boolean, and
  /// resolves against the session's key — there is no per-request id in the
  /// call. `all: true` applies the choice to every pending request.
  /// [choice] must be one of the values the server sent in
  /// [ApprovalRequest.choices] — `once`, `session`, `always` or `deny`.
  /// The server stores it verbatim without validating, so an invented value
  /// such as "allow" silently fails to approve.
  Future<Map<String, dynamic>> approvalRespond({
    required String sessionId,
    required String choice,
    bool all = false,
    String? reason,
  }) async =>
      _asMap(await call('approval.respond', {
        'session_id': sessionId,
        'choice': choice,
        'all': all,
        // Free-text explanation relayed to the agent on an explicit deny, so
        // it can adapt rather than only hearing "denied".
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }));

  Future<Map<String, dynamic>> approveOnce(String sessionId) =>
      approvalRespond(sessionId: sessionId, choice: 'once');
  Future<Map<String, dynamic>> denyOnce(String sessionId, {String? reason}) =>
      approvalRespond(sessionId: sessionId, choice: 'deny', reason: reason);

  // -- blocking prompts from the agent ---------------------------------------

  /// Answers a `clarify.request` — the agent asking the user a question
  /// mid-turn.
  ///
  /// These are **blocking**: the server's `_block` helper emits the request
  /// and parks the agent thread until an answer arrives (up to 300 s, or
  /// forever when the clarify timeout is disabled). A client that ignores
  /// them does not merely miss a feature, it hangs the turn — the same
  /// symptom as a dropped connection.
  ///
  /// [requestId] comes from the request's payload, not from the session.
  Future<Map<String, dynamic>> clarifyRespond({
    required String requestId,
    required String answer,
  }) async =>
      _asMap(await call('clarify.respond', {
        'request_id': requestId,
        'answer': answer,
      }));

  /// Answers a `sudo.request`. The value is the user's own password, typed by
  /// the user; nothing else may fill it in.
  Future<Map<String, dynamic>> sudoRespond({
    required String requestId,
    required String password,
  }) async =>
      _asMap(await call('sudo.respond', {
        'request_id': requestId,
        'password': password,
      }));

  /// Answers a `secret.request` — an API key or token the agent needs, which
  /// the server stores under the requested environment variable.
  Future<Map<String, dynamic>> secretRespond({
    required String requestId,
    required String value,
  }) async =>
      _asMap(await call('secret.respond', {
        'request_id': requestId,
        'value': value,
      }));

  /// Answers a `terminal.read.request`.
  ///
  /// [text] is a JSON string: the tool hands it to the agent verbatim.
  Future<Map<String, dynamic>> terminalReadRespond({
    required String requestId,
    required String text,
  }) async =>
      _asMap(await call('terminal.read.respond', {
        'request_id': requestId,
        'text': text,
      }));

  // -- discovery -------------------------------------------------------------

  // -- scheduled jobs --------------------------------------------------------

  /// Scheduled agent runs. The gateway exposes only `list` and `add`; pause,
  /// resume and delete live on the A-plane `/api/jobs/*` REST surface.
  Future<List<CronJob>> cronList() async {
    final raw = _asMap(await call('cron.manage', {'action': 'list'}));
    return ((raw['jobs'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CronJob.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> cronAdd({
    required String name,
    required String schedule,
    required String prompt,
  }) async =>
      _asMap(await call('cron.manage', {
        'action': 'add',
        'name': name,
        'schedule': schedule,
        'prompt': prompt,
      }));

  // -- attachments -----------------------------------------------------------

  /// Stages a non-image file into the session workspace.
  ///
  /// A remote client must send [dataUrl] — the gateway cannot see this Mac's
  /// disk, and `path` alone only works when both ends share a filesystem. The
  /// result's `ref_text` is an `@file:` reference to paste into the prompt.
  Future<FileAttachment> fileAttach({
    required String sessionId,
    String? path,
    String? dataUrl,
    String? name,
  }) async =>
      FileAttachment.fromJson(_asMap(await call('file.attach', {
        'session_id': sessionId,
        if (path != null && path.isNotEmpty) 'path': path,
        if (dataUrl != null && dataUrl.isNotEmpty) 'data_url': dataUrl,
        if (name != null && name.isNotEmpty) 'name': name,
      })));

  /// Attaches an image from bytes — the remote-client path. `image.attach`
  /// takes a path the *gateway* must be able to open, which is useless from
  /// another machine.
  Future<Map<String, dynamic>> imageAttachBytes({
    required String sessionId,
    required String contentBase64,
    String? filename,
    String? ext,
  }) async =>
      _asMap(await call('image.attach_bytes', {
        'session_id': sessionId,
        'content_base64': contentBase64,
        if (filename != null && filename.isNotEmpty) 'filename': filename,
        if (ext != null && ext.isNotEmpty) 'ext': ext,
      }));

  /// Drops a staged image by its gateway-side path.
  Future<Map<String, dynamic>> imageDetach({
    required String sessionId,
    required String path,
  }) async =>
      _asMap(await call('image.detach', {
        'session_id': sessionId,
        'path': path,
      }));

  // -- checkpoints -----------------------------------------------------------

  /// Filesystem checkpoints the agent took while editing.
  ///
  /// Returns an empty list when the feature is disabled for the session rather
  /// than an error, so the caller can just show "no checkpoints".
  Future<List<Checkpoint>> rollbackList(String sessionId) async {
    final raw = _asMap(await call('rollback.list', {'session_id': sessionId}));
    return ((raw['checkpoints'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Checkpoint.fromJson)
        .toList();
  }

  /// `stat` plus a truncated unified diff for one checkpoint.
  Future<Map<String, dynamic>> rollbackDiff({
    required String sessionId,
    required String hash,
  }) async =>
      _asMap(await call('rollback.diff', {
        'session_id': sessionId,
        'hash': hash,
      }));

  /// Restores the whole checkpoint, or a single [filePath] from it.
  ///
  /// A full restore is refused while a turn is running (4009) — interrupt
  /// first. This rewrites files on the server, so confirm before calling.
  Future<Map<String, dynamic>> rollbackRestore({
    required String sessionId,
    required String hash,
    String? filePath,
  }) async =>
      _asMap(await call('rollback.restore', {
        'session_id': sessionId,
        'hash': hash,
        if (filePath != null && filePath.isNotEmpty) 'file_path': filePath,
      }));

  // -- background processes --------------------------------------------------

  Future<List<RunningProcess>> processList(String sessionId) async {
    final raw = _asMap(await call('process.list', {'session_id': sessionId}));
    return ((raw['processes'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RunningProcess.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> processKill({
    required String sessionId,
    required String processId,
  }) async =>
      _asMap(await call('process.kill', {
        'session_id': sessionId,
        'process_id': processId,
      }));

  // -- completion ------------------------------------------------------------

  /// Path and `@`-reference completion for the composer.
  ///
  /// [word] is the token under the cursor, including its leading `@`. Resolved
  /// against the session's cwd, which is on the *server* — a local file picker
  /// cannot stand in for this.
  Future<List<PathCompletion>> completePath({
    required String word,
    String? sessionId,
  }) async {
    final raw = _asMap(await call('complete.path', {
      'word': word,
      if (sessionId != null) 'session_id': sessionId,
    }));
    return ((raw['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PathCompletion.fromJson)
        .toList();
  }

  // -- session working directory --------------------------------------------

  /// Refused while a turn is running (4009).
  Future<Map<String, dynamic>> sessionCwdSet({
    required String sessionId,
    required String cwd,
  }) async =>
      _asMap(await call('session.cwd.set', {
        'session_id': sessionId,
        'cwd': cwd,
      }));

  Future<Map<String, dynamic>> sessionStatus(String sessionId) async =>
      _asMap(await call('session.status', {'session_id': sessionId}));

  Future<Map<String, dynamic>> toolsList({String? sessionId}) async =>
      _asMap(await call('tools.list', {
        if (sessionId != null) 'session_id': sessionId,
      }));

  Future<Map<String, dynamic>> commandsCatalog() async =>
      _asMap(await call('commands.catalog'));

  // -- agent activity --------------------------------------------------------

  /// Live subagents, plus the spawn limits and whether spawning is paused.
  Future<Map<String, dynamic>> delegationStatus() async =>
      _asMap(await call('delegation.status'));

  /// Saved subagent spawn trees for a session.
  Future<List<Map<String, dynamic>>> spawnTrees(
    String sessionId, {
    int limit = 50,
  }) async {
    final raw = _asMap(await call('spawn_tree.list', {
      'session_id': sessionId,
      'limit': limit,
    }));
    return ((raw['trees'] ?? raw['entries'] ?? raw['items']) as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Session and message counts over the last [days].
  Future<Map<String, dynamic>> insights({int days = 30}) async =>
      _asMap(await call('insights.get', {'days': days}));

  // -- server status ---------------------------------------------------------

  /// Token-usage bars as the TUI renders them.
  Future<Map<String, dynamic>> usageBars() async =>
      _asMap(await call('usage.bars'));

  /// Battery state of the machine running the agent — it may be a laptop on
  /// its own power budget, which is worth knowing before a long run.
  Future<Map<String, dynamic>> systemBattery() async =>
      _asMap(await call('system.battery'));

  Future<Map<String, dynamic>> setupStatus() async =>
      _asMap(await call('setup.status'));

  Future<Map<String, dynamic>> verificationStatus() async =>
      _asMap(await call('verification.status'));

  /// The effective configuration, as the server resolved it.
  Future<Map<String, dynamic>> configShow() async =>
      _asMap(await call('config.show'));

  // -- maintenance -----------------------------------------------------------

  /// Re-reads `.env` on the server. Affects every session, so confirm first.
  Future<Map<String, dynamic>> reloadEnv() async =>
      _asMap(await call('reload.env'));

  /// Restarts MCP servers. Slow, and briefly removes their tools.
  ///
  /// Runs on the gateway's RPC pool precisely because it can take a while, so
  /// it gets a longer budget than the default — a 30 s ceiling would fail a
  /// call that was going to succeed.
  Future<Map<String, dynamic>> reloadMcp({
    String? sessionId,
    Duration timeout = const Duration(minutes: 2),
  }) async =>
      _asMap(await call(
        'reload.mcp',
        {if (sessionId != null) 'session_id': sessionId},
        timeout,
      ));

  Future<Map<String, dynamic>> skillsReload() async =>
      _asMap(await call('skills.reload'));

  // -- more session lifecycle -------------------------------------------------

  /// Makes a session the gateway's current one. Most methods take an explicit
  /// `session_id` instead, so this is only needed for the few that do not.
  Future<Map<String, dynamic>> sessionActivate(String sessionId) async =>
      _asMap(await call('session.activate', {'session_id': sessionId}));

  Future<Map<String, dynamic>> sessionMostRecent() async =>
      _asMap(await call('session.most_recent'));

  /// Sessions live in the gateway's process right now — not the persisted
  /// list. Useful for spotting a turn running under another client.
  Future<Map<String, dynamic>> sessionActiveList({String? currentSessionId}) async =>
      _asMap(await call('session.active_list', {
        if (currentSessionId != null) 'current_session_id': currentSessionId,
      }));

  /// Forces a write of the transcript to the database.
  Future<Map<String, dynamic>> sessionSave(String sessionId) async =>
      _asMap(await call('session.save', {'session_id': sessionId}));

  // -- subagent control ------------------------------------------------------

  Future<Map<String, dynamic>> subagentInterrupt(String subagentId) async =>
      _asMap(await call('subagent.interrupt', {'subagent_id': subagentId}));

  /// Stops or resumes new subagent spawning. Running children keep going.
  Future<Map<String, dynamic>> delegationPause({required bool paused}) async =>
      _asMap(await call('delegation.pause', {'paused': paused}));

  /// Kills **every** background process the gateway knows about, not just this
  /// session's. `process.kill` is the scoped one.
  Future<Map<String, dynamic>> processStopAll() async =>
      _asMap(await call('process.stop'));

  // -- projects ---------------------------------------------------------------

  /// Project → repo → lane structure with session counts.
  Future<Map<String, dynamic>> projectsTree() async =>
      _asMap(await call('projects.tree'));

  Future<Map<String, dynamic>> projectSessions(String projectId) async =>
      _asMap(await call('projects.project_sessions', {'project_id': projectId}));

  // -- provider credentials --------------------------------------------------

  /// Stores an API key for a provider and returns its refreshed model list.
  ///
  /// [apiKey] must be a value the *user* typed. It goes straight to their own
  /// server and is never persisted by this client. Answers 4006 on a managed
  /// install, where credentials are read-only.
  Future<Map<String, dynamic>> modelSaveKey({
    required String slug,
    required String apiKey,
  }) async =>
      _asMap(await call('model.save_key', {
        'slug': slug,
        'api_key': apiKey,
      }));

  /// Removes a provider's stored credentials from the server.
  Future<Map<String, dynamic>> modelDisconnect(String slug) async =>
      _asMap(await call('model.disconnect', {'slug': slug}));

  // -- misc session surface --------------------------------------------------

  /// Redirects the running turn while keeping the work done so far.
  ///
  /// Distinct from [sessionSteer]: steer adds guidance, redirect replaces the
  /// objective.
  Future<Map<String, dynamic>> sessionRedirect({
    required String sessionId,
    required String text,
  }) async =>
      _asMap(await call('session.redirect', {
        'session_id': sessionId,
        'text': text,
      }));

  /// Manifests, package manager and other structured facts for a directory.
  Future<Map<String, dynamic>> projectFacts({String? cwd}) async =>
      _asMap(await call('project.facts', {if (cwd != null) 'cwd': cwd}));

  /// Handoff state for a session — whether it is being passed to another
  /// surface, and how that is going.
  Future<Map<String, dynamic>> handoffState(String sessionId) async =>
      _asMap(await call('handoff.state', {'session_id': sessionId}));

  /// Browser bridge status. `action: 'status'` is the read-only form; the
  /// connect path is deliberately not wrapped, since it attaches the agent to
  /// a browser session on the server.
  Future<Map<String, dynamic>> browserStatus() async =>
      _asMap(await call('browser.manage', {'action': 'status'}));

  // -- what the agent has learned --------------------------------------------

  /// The journey timeline.
  ///
  /// The method's real job is to pre-render a terminal animation, so it wants
  /// `cols`/`rows`/`frames`. Ask for the smallest legal grid — the character
  /// art is discarded and only the structured buckets are used.
  Future<LearningJourney> learningJourney() async => LearningJourney.fromJson(
      _asMap(await call('learning.frames', {
        'cols': 20,
        'rows': 10,
        'frames': 1,
      })));

  /// Current content of a journey node, for an edit prefill.
  Future<Map<String, dynamic>> learningDetail(String id) async =>
      _asMap(await call('learning.detail', {'id': id}));

  /// Rewrites a node's content — a SKILL.md file or a memory chunk.
  Future<Map<String, dynamic>> learningEdit(String id, String content) async =>
      _asMap(await call('learning.edit', {'id': id, 'content': content}));

  /// Removes a node. Skills are archived and restorable; memories are not.
  Future<Map<String, dynamic>> learningDelete(String id) async =>
      _asMap(await call('learning.delete', {'id': id}));

  /// Installed skills. `action: 'search'` also exists but reaches out to
  /// GitHub, so it is deliberately not wrapped here.
  Future<List<Map<String, dynamic>>> skillsList() async {
    final raw = _asMap(await call('skills.manage', {'action': 'list'}));
    final skills = raw['skills'];
    // The live server answers with a name → description *map*, not the list
    // the surrounding methods use. Both shapes are accepted rather than
    // guessing which one a given build sends.
    if (skills is Map) {
      return skills.entries
          .map((e) => <String, dynamic>{
                'name': '${e.key}',
                'description': e.value is Map
                    ? (e.value as Map)['description']?.toString() ?? ''
                    : '${e.value}',
              })
          .toList();
    }
    return ((skills as List?) ?? const [])
        .map((e) => e is Map<String, dynamic> ? e : {'name': '$e'})
        .toList();
  }

  Future<List<Map<String, dynamic>>> pluginsList() async {
    final raw = _asMap(await call('plugins.list'));
    return ((raw['plugins'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Toolsets, including MCP servers, with their enabled flags.
  ///
  /// There is a `tools.configure` companion that flips these — it is
  /// deliberately not wrapped. It writes the *global* CLI config, so a stray
  /// click would change behaviour for every session on the server, including
  /// ones this client never opened.
  Future<List<Map<String, dynamic>>> toolsets({String? sessionId}) async {
    final raw = await toolsList(sessionId: sessionId);
    return ((raw['toolsets'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<Map<String, dynamic>> agentsList() async =>
      _asMap(await call('agents.list'));

  Future<Map<String, dynamic>> modelOptions() async =>
      _asMap(await call('model.options'));
}

Map<String, dynamic> _asMap(Object? result) =>
    result is Map<String, dynamic> ? result : const {};
