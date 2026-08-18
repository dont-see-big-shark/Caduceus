/// The conversation surface over a connected [ClawGateway].
///
/// Every method name and every parameter below is taken from the gateway's own
/// TypeBox schemas, read out of the running install (openclaw 2026.7.1-2,
/// `dist/`, `packages/gateway-protocol/src/schema/sessions.ts`). That matters
/// more than it sounds: the schemas are declared `additionalProperties: false`,
/// so a plausible-looking guess is not loosely accepted — it is rejected whole.
///
/// The first draft of this file guessed, and every guess was wrong in a way no
/// amount of testing against a fake socket could have caught, because a fake
/// socket asserts what the client *sent*, never what a server would have
/// *accepted*:
///
///   * `sessions.send` takes `key` and `message`, not `sessionId` and `text`.
///   * `sessions.abort` takes `key`; `chat.abort` is a different method.
///   * `sessions.create` has no `cwd` and no `idempotencyKey` at all, and the
///     title is `label`.
///   * `exec.approval.resolve` takes `{id, decision}` — no request id, no
///     idempotency key.
///   * `sessions.subscribe` does **not** deliver messages. It toggles session
///     *index* events. Transcript events need `sessions.messages.subscribe`,
///     which the first draft never called — so a correct-looking client would
///     have connected, listed, sent, and then waited forever for a reply.
///
/// A session's identity on the wire is its **key**, not the `sessionId` field
/// that also appears in replies. Every method here is keyed on it.
library;

import 'dart:async';

import 'frames.dart';
import 'gateway.dart';

/// One conversation the gateway knows about.
///
/// There is deliberately no message count here. `sessions.list` does not
/// report one, and inventing a zero would put "0 messages" under a row with a
/// transcript in it — a wrong answer rather than a missing one.
class ClawSession {
  const ClawSession({
    required this.key,
    this.label = '',
    this.derivedTitle = '',
    this.preview = '',
    this.updatedAt,
    this.source = '',
    this.model = '',
    this.running = false,
    this.unread = false,
  });

  factory ClawSession.fromJson(Map<String, dynamic> json) {
    final origin = (json['origin'] as Map?)?.cast<String, dynamic>();
    return ClawSession(
      // `key` is the identity every other method takes. A row also carries a
      // `sessionId`, which is the transcript file's id and is *not* what
      // `sessions.send` or `chat.history` want — reading that one gets a
      // well-formed request rejected as a session that does not exist.
      key: '${json['key'] ?? json['sessionKey'] ?? ''}',
      label: '${json['label'] ?? ''}',
      // Only present when the caller asked for it; see [sessions].
      derivedTitle: '${json['derivedTitle'] ?? ''}',
      preview: '${json['lastMessagePreview'] ?? ''}',
      updatedAt: json['updatedAt'] as int?,
      // Where the conversation came from, in the gateway's own words. The
      // session key spells it too, but only sometimes and never reliably —
      // this is the field that always knows.
      source: '${origin?['provider'] ?? json['lastChannel'] ?? ''}',
      model: '${json['model'] ?? ''}',
      running: json['hasActiveRun'] == true || json['status'] == 'running',
      unread: json['unread'] == true,
    );
  }

  /// The session key — the wire identity.
  final String key;

  /// A title someone set by hand. Usually empty.
  final String label;

  /// The gateway's own title, taken from the first user message. Empty unless
  /// [sessions] was asked for it.
  final String derivedTitle;

  /// The most recent message, for a row that has no title worth showing.
  final String preview;

  /// Epoch millis.
  final int? updatedAt;

  /// `webchat`, `telegram`, `cron`… — the gateway's word, not this client's.
  final String source;

  final String model;
  final bool running;
  final bool unread;

  /// What a row shows: a set title, else the one derived from the first
  /// message, else nothing — and never the key, which is a routing address
  /// and reads like one.
  String get title => label.isNotEmpty ? label : derivedTitle;

  @override
  String toString() =>
      'ClawSession($key, "${title.isEmpty ? '(untitled)' : title}")';
}

/// A live turn: the assistant text as it streams, and a future that completes
/// when the turn ends.
class ClawTurn {
  ClawTurn._(this._done);

  final Completer<String> _done;
  final _deltas = StreamController<String>.broadcast();
  final _buffer = StringBuffer();

  /// Each increment of assistant text. Protocol v4 carries `deltaText`; the
  /// cumulative `message` snapshot is used only to reconcile, never re-emitted,
  /// so a listener sees a clean stream of new characters.
  Stream<String> get deltas => _deltas.stream;

  /// The whole reply, once the turn has finished.
  Future<String> get whenDone => _done.future;

  /// The text accumulated so far.
  String get text => _buffer.toString();
}

/// Sessions and chat, over one connected gateway.
extension ClawConversation on ClawGateway {
  /// Every conversation the gateway holds.
  ///
  /// `sessions.list` is the method — confirmed against the gateway's own
  /// handler table. There is no `sessions.recent`; an earlier draft carried a
  /// fallback to one, which would only ever have produced a second failure.
  /// [withTitles] asks the gateway to read the head and tail of each
  /// transcript, so a row can show what the conversation is about instead of
  /// its routing address. It costs a file read per session, which is why it is
  /// opt-in and why [limit] matters — but a sidebar of
  /// `agent:main:dashboard:9d1628ad-…` identifies nothing to a reader.
  Future<List<ClawSession>> sessions({
    int limit = 100,
    bool withTitles = true,
  }) async {
    final result = await call('sessions.list', {
      'limit': limit,
      if (withTitles) ...{
        'includeDerivedTitles': true,
        'includeLastMessage': true,
      },
    });
    final raw =
        (result['sessions'] as List?) ??
        (result['items'] as List?) ??
        const [];
    return [
      for (final s in raw.whereType<Map>())
        ClawSession.fromJson(s.cast<String, dynamic>()),
    ];
  }

  /// Starts a new conversation, and returns its key.
  ///
  /// Takes no idempotency key, unlike [send] — the schema does not allow one,
  /// and `additionalProperties: false` means passing it anyway fails the whole
  /// request. There is no `cwd` either: an OpenClaw session's workspace comes
  /// from its agent, not from the client.
  ///
  /// One attachment, in the shape the gateway normalises RPC payloads into.
  ///
  /// The schema types an attachment as unknown — the one thing about
  /// `sessions.send` its contract does not pin down — so this comes from the
  /// normaliser instead: a `content` of canonical base64 is the only required
  /// field, with `fileName` and `mimeType` beside it.
  static Map<String, dynamic> attachment({
    required String fileName,
    required String mimeType,
    required String contentBase64,
  }) => {
    'fileName': fileName,
    'mimeType': mimeType,
    'content': contentBase64,
  };

  /// [label] must be unique across the gateway — reusing one answers
  /// `INVALID_REQUEST: label already in use`, which reads like a client bug
  /// and is a naming collision.
  ///
  /// [fork] branches [parentSessionKey]'s transcript into the new session,
  /// which is how OpenClaw spells session branching.
  Future<String> createSession({
    String? label,
    String? model,
    String? parentSessionKey,
    bool fork = false,
  }) async {
    final result = await call('sessions.create', {
      if (label != null && label.isNotEmpty) 'label': label,
      if (model != null && model.isNotEmpty) 'model': model,
      if (parentSessionKey != null && parentSessionKey.isNotEmpty)
        'parentSessionKey': parentSessionKey,
      if (fork) 'fork': true,
    });
    return '${result['key'] ?? ''}';
  }

  /// One session's row, by key.
  ///
  /// The same shape a list row has, and asked for the same way — a session
  /// opened directly, from a link or a preset, otherwise knows nothing about
  /// itself and shows its routing address as a heading.
  Future<ClawSession?> describeSession(String key) async {
    final result = await call('sessions.describe', {
      'key': key,
      'includeDerivedTitles': true,
      'includeLastMessage': true,
    });
    final row = result['session'] ?? result['entry'] ?? result['row'];
    if (row is! Map) return null;
    return ClawSession.fromJson(row.cast<String, dynamic>());
  }

  /// Subscribes to the session *index* — rows appearing, titles changing.
  ///
  /// Not the transcript. This is the distinction that would have cost the most
  /// to find by experiment: a client that subscribes here and waits for a
  /// reply waits forever, because the reply travels on the other subscription.
  /// Takes no parameters; it is a per-connection toggle.
  Future<void> subscribeSessions() => call('sessions.subscribe');

  Future<void> unsubscribeSessions() => call('sessions.unsubscribe');

  /// Subscribes to one session's transcript and tool events.
  ///
  /// This is the one that delivers a conversation. Explicit, unlike Hermes,
  /// which pushes everything regardless — so it must be released when done or
  /// the gateway keeps streaming to nobody.
  Future<void> subscribeMessages(String key) =>
      call('sessions.messages.subscribe', {'key': key});

  Future<void> unsubscribeMessages(String key) =>
      call('sessions.messages.unsubscribe', {'key': key});

  /// Resolves a tool execution the agent is blocked on.
  ///
  /// The schema is `{id, decision}` and nothing else — no request id under
  /// that name, and no idempotency key, both of which an earlier draft sent
  /// and both of which would have failed the request outright. [decision] is
  /// one of the choices the request offered, sent verbatim.
  Future<void> resolveApproval({
    required String id,
    required String decision,
  }) => call('exec.approval.resolve', {'id': id, 'decision': decision});

  /// The stored transcript, display-normalised by the gateway for UI clients.
  ///
  /// Note the parameter is `sessionKey` here and `key` on the `sessions.*`
  /// methods. That is the gateway's inconsistency, not a typo, and it is the
  /// kind of thing only the schema can tell you.
  Future<List<Map<String, dynamic>>> history(
    String sessionKey, {
    int? limit,
  }) async {
    final result = await call('chat.history', {
      'sessionKey': sessionKey,
      if (limit != null) 'limit': limit,
    });
    final rows = (result['messages'] as List?) ?? const [];
    return [
      for (final row in rows.whereType<Map>()) row.cast<String, dynamic>(),
    ];
  }

  /// The models this agent is allowed to use — the default view.
  ///
  /// The default `models.list` view is the agent's allowlist: exactly the
  /// models `sessions.patch` will accept, which is what a model picker must
  /// show. `view: "all"` returns the whole catalog including models the
  /// gateway knows about but has no credential or allowlist entry for — most
  /// of which `sessions.patch` refuses with "model not allowed", which is the
  /// difference between "you can pick this" and "it exists somewhere".
  Future<List<Map<String, dynamic>>> models({String? view}) async {
    final result = await call('models.list', {
      if (view != null) 'view': view,
    });
    final rows = (result['models'] as List?) ?? const [];
    return [
      for (final row in rows.whereType<Map>()) row.cast<String, dynamic>(),
    ];
  }

  /// Sets per-session overrides — the model, chiefly — and reports what the
  /// gateway resolved them to.
  Future<Map<String, dynamic>> patchSession(
    String key, {
    String? model,
    String? label,
  }) => call('sessions.patch', {
    'key': key,
    if (model != null && model.isNotEmpty) 'model': model,
    if (label != null) 'label': label,
  });

  /// Sends a message and returns a [ClawTurn] that streams the reply.
  ///
  /// [clientId] is the idempotency key — the caller's to generate, the same on
  /// a retry, because the gateway requires one on side-effecting calls and a
  /// key minted inside a retry loop defeats its own purpose.
  ///
  /// The reply is assembled from delta events carrying `deltaText`; the turn
  /// completes when the gateway signals the message is final. [_isFinal] holds
  /// that reading in one place so there is a single line to correct.
  ///
  /// Requires [subscribeMessages] to have been called for [key] — the reply
  /// travels on the transcript subscription, not on the session-index one.
  ClawTurn send(
    String key,
    String message, {
    required String clientId,
    List<Map<String, dynamic>> attachments = const [],
  }) {
    final turn = ClawTurn._(Completer<String>());
    late final StreamSubscription<ClawEvent> sub;
    sub = events.listen((event) {
      if (!_isForSession(event, key)) return;
      final delta = event.payload['deltaText'];
      if (delta is String && delta.isNotEmpty) {
        turn._buffer.write(delta);
        turn._deltas.add(delta);
      }
      if (_isFinal(event)) {
        if (!turn._done.isCompleted) turn._done.complete(turn.text);
        unawaited(turn._deltas.close());
        unawaited(sub.cancel());
      }
    });

    unawaited(
      call('sessions.send', {
        'key': key,
        'message': message,
        if (attachments.isNotEmpty) 'attachments': attachments,
      }, clientId).catchError((Object e) {
        if (!turn._done.isCompleted) turn._done.completeError(e);
        unawaited(turn._deltas.close());
        unawaited(sub.cancel());
        return <String, dynamic>{};
      }),
    );
    return turn;
  }

  /// Stops the running turn in a session.
  Future<void> abort(String key) => call('sessions.abort', {'key': key});

  static bool _isForSession(ClawEvent event, String key) {
    final sid = event.payload['sessionKey'] ?? event.payload['key'];
    // A gateway that does not tag events with a session id (because the
    // subscription already scoped them) leaves this null; accept those rather
    // than silently dropping the reply.
    return sid == null || '$sid' == key;
  }

  /// Whether an event ends the turn.
  ///
  /// Watched on a live gateway rather than guessed at, and the guess was
  /// wrong in every particular: there is no `chat.done` event and no
  /// `final: true` flag. A turn ends with an event **named `chat`** carrying
  /// **`state: "final"`**, alongside a `stopReason`. The same `chat` event
  /// with `state: "delta"` is what carries `deltaText`.
  ///
  /// The `final: true` reading is kept only as a fallback, because it costs a
  /// clause and a client that hangs waiting for the end of a turn is
  /// indistinguishable from a hung agent.
  static bool _isFinal(ClawEvent event) =>
      (event.name == 'chat' && event.payload['state'] == 'final') ||
      event.payload['final'] == true;
}
