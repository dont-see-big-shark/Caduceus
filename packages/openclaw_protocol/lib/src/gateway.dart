/// A client for the OpenClaw gateway.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'device_identity.dart';
import 'frames.dart';

/// The socket, behind an interface, so the handshake can be tested without one.
///
/// Same seam as `hermes_protocol`'s `GatewayTransport`, and for the same
/// reason: the interesting part of this client is a five-field signature over
/// a pipe-joined string, and nothing about verifying it should need a server.
abstract interface class ClawTransport {
  Stream<String> get inbound;
  void send(String data);
  Future<void> close();
}

class WebSocketClawTransport implements ClawTransport {
  WebSocketClawTransport(this._socket);

  static Future<WebSocketClawTransport> connect(
    Uri url, {
    Map<String, dynamic> headers = const {},
  }) async =>
      WebSocketClawTransport(
        await WebSocket.connect(url.toString(), headers: headers),
      );

  final WebSocket _socket;

  @override
  Stream<String> get inbound => _socket.map((d) => '$d');

  @override
  void send(String data) => _socket.add(data);

  @override
  Future<void> close() => _socket.close();
}

/// Which kind of client is connecting.
///
/// The gateway validates these against a closed set and rejects anything else
/// with *"must be equal to one of the allowed values"*. `cli`, `ui` and `node`
/// are the three it accepts; `operator`, `desktop`, `app` and `web` are not.
enum ClawClientMode { cli, ui, node }

/// What the connection is allowed to be.
///
/// Separate from [ClawClientMode] and separately validated — `cli` and `ui` are
/// modes but not roles, and sending one as a role answers *"invalid role"*.
enum ClawRole { operator, node }

/// Where a gateway is and how to reach it.
class ClawEndpoint {
  const ClawEndpoint({
    required this.url,
    this.token = '',
    this.deviceToken = '',
    this.bootstrapToken = '',
    this.headers = const {},
  });

  final Uri url;

  /// `gateway.auth.token` on the server side.
  ///
  /// Held here rather than baked into a header because it is **part of the
  /// signed device payload**, so the signature cannot be computed until the
  /// credential is chosen.
  final String token;

  /// The token the gateway issued to *this device* when it was paired.
  ///
  /// Distinct from [token], which authenticates the client against the
  /// gateway's own `gateway.auth.token`. An already-paired device presents
  /// this, and the reference client sends it as `token` *and* `deviceToken` at
  /// once — so that is what this does.
  final String deviceToken;

  /// Presented instead of [token] when this device has never been paired.
  ///
  /// A gateway that accepts it pairs the device on the spot rather than
  /// filing a request for a human to approve, which is the difference between
  /// a client that can be set up unattended and one that cannot.
  final String bootstrapToken;

  /// Extra request headers — a reverse proxy's session cookie, typically.
  /// These authenticate the *tunnel*, never the gateway itself.
  final Map<String, String> headers;

  /// Never the credential: this is a string that ends up in logs and on
  /// screenshots.
  @override
  String toString() => '${url.host}${url.hasPort ? ':${url.port}' : ''}';
}

/// Connects, authenticates, and carries requests and events.
class ClawGateway {
  ClawGateway(
    this.endpoint, {
    required this.identity,
    this.clientId = 'cli',
    this.mode = ClawClientMode.cli,
    this.role = ClawRole.operator,
    this.clientVersion = '0.1.0',
    this.platform = 'macos',
    this.deviceFamily = '',
    this.scopes = const [],
    Future<ClawTransport> Function(ClawEndpoint)? connector,
  }) : _connector = connector ?? _defaultConnector;

  static Future<ClawTransport> _defaultConnector(ClawEndpoint e) =>
      WebSocketClawTransport.connect(e.url, headers: e.headers);

  final ClawEndpoint endpoint;
  final ClawDeviceIdentity identity;

  /// Also validated against a closed set. `cli`, `gateway-client` and `test`
  /// are accepted; `web`, `desktop` and `mobile` are not.
  final String clientId;
  final ClawClientMode mode;
  final ClawRole role;
  final String clientVersion;
  final String platform;

  /// Field 11 of the signed payload, and easy to forget because it is usually
  /// empty. If the gateway has one recorded for this device and the client
  /// signs without it, the signature is over a different string and the server
  /// reports *"device identity changed and must be re-approved"* — which reads
  /// like a key problem and is not one.
  final String deviceFamily;

  /// What this connection asks to be allowed to do.
  ///
  /// Part of the signed payload (field 6), and part of what an operator
  /// approves — so asking for nothing is not the safe default it looks like.
  /// A device paired with no scopes is paired and useless: `sessions.list`
  /// alone needs `operator.read`, and the approval has already been given by
  /// the time that shows up as `FORBIDDEN`.
  ///
  /// Ask for [chatScopes] unless there is a reason not to.
  final List<String> scopes;

  /// The least privilege a conversation client can work with.
  ///
  /// `operator.read` for lists, history and subscriptions; `operator.write`
  /// for sending; `operator.approvals` for answering an exec approval — which
  /// is the one surface where the user's answer is the whole point.
  ///
  /// Deliberately excludes `operator.admin`, which satisfies every other scope
  /// and would make this client able to rewrite the gateway's configuration;
  /// `operator.pairing`, which would let it approve other devices including
  /// itself; and `operator.talk.secrets`. A chat client needs none of the
  /// three, and an approval prompt that asks for them invites a habit of
  /// saying yes to whatever is on the screen.
  static const chatScopes = [
    'operator.read',
    'operator.write',
    'operator.approvals',
  ];

  /// chatScopes plus `operator.admin` — for a client the person wants to
  /// write with.
  ///
  /// `operator.admin` satisfies every other scope, so this client can rewrite
  /// the gateway's configuration, install skills, and write memory
  /// (`agents.files.set`) — which the shared knowledge base (`SHARED_MEMORY.md`)
  /// needs. Not the default for a chat client, and asked for only where the
  /// person explicitly wants writes. On this deployment it is safe because
  /// authentication is the auth token (device auth is disabled), so the token
  /// is already the administrator credential.
  static const adminScopes = [
    'operator.read',
    'operator.write',
    'operator.approvals',
    'operator.admin',
  ];

  final Future<ClawTransport> Function(ClawEndpoint) _connector;

  ClawTransport? _transport;
  StreamSubscription<String>? _subscription;
  final _events = StreamController<ClawEvent>.broadcast();
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  Completer<ClawHello>? _handshake;
  var _nextId = 0;

  Stream<ClawEvent> get events => _events.stream;

  ClawHello? _hello;
  ClawHello? get hello => _hello;

  /// Connects and completes the challenge-response handshake.
  ///
  /// The server speaks first — a `connect.challenge` carrying a nonce and a
  /// timestamp — and both go into the signature, so there is nothing to send
  /// until it arrives. That is why this is not `send-then-await`.
  Future<ClawHello> connect({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    await _closeTransport();
    final transport = _transport = await _connector(endpoint);
    _handshake = Completer<ClawHello>();
    _subscription = transport.inbound.listen(
      _onFrame,
      onError: _fail,
      onDone: () => _fail(const ClawRpcException(
        method: 'connect',
        code: 'DISCONNECTED',
        message: 'the gateway closed the connection',
      )),
    );
    return _handshake!.future.timeout(timeout);
  }

  Future<void> _onFrame(String raw) async {
    final Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return;
    }

    switch (frame['type']) {
      case 'event':
        final event = ClawEvent.fromJson(frame);
        if (event.name == 'connect.challenge') {
          await _answerChallenge(event.payload);
          return;
        }
        if (_events.hasListener) _events.add(event);
      case 'res':
        final id = '${frame['id']}';
        final completer = _pending.remove(id);
        if (frame['ok'] == true) {
          final payload =
              (frame['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
          if (id == '_connect') {
            _hello = ClawHello.fromJson(payload);
            _handshake?.complete(_hello);
          }
          completer?.complete(payload);
        } else {
          final error = ClawRpcException.fromError(
            id == '_connect' ? 'connect' : id,
            (frame['error'] as Map?)?.cast<String, dynamic>() ?? const {},
          );
          if (id == '_connect' && !(_handshake?.isCompleted ?? true)) {
            _handshake!.completeError(error);
          }
          completer?.completeError(error);
        }
    }
  }

  /// `signatureToken` in the reference client: whichever credential is
  /// actually presented is the one folded into the signature.
  String get _signatureToken => endpoint.token.isNotEmpty
      ? endpoint.token
      : endpoint.deviceToken.isNotEmpty
          ? endpoint.deviceToken
          : endpoint.bootstrapToken;

  Future<void> _answerChallenge(Map<String, dynamic> payload) async {
    final nonce = '${payload['nonce'] ?? ''}';
    final signedAt = payload['ts'] as int? ?? 0;

    // Signed before it is sent, and over the token as well as the nonce — see
    // deviceAuthPayloadV3. Choosing a credential after signing produces a
    // signature the gateway will reject with a message about device identity,
    // which is a misleading place to start debugging.
    final signature = await identity.sign(
      deviceAuthPayloadV3(
        deviceId: identity.deviceId,
        clientId: clientId,
        clientMode: mode.name,
        role: role.name,
        scopes: scopes,
        signedAtMs: signedAt,
        nonce: nonce,
        // Whichever credential is actually being presented is the one that
        // must be signed — `signatureToken` in the reference client.
        token: _signatureToken,
        platform: platform,
        deviceFamily: deviceFamily,
      ),
    );

    _transport?.send(
      jsonEncode({
        'type': 'req',
        'id': '_connect',
        'method': 'connect',
        'params': {
          'minProtocol': 1,
          'maxProtocol': 4,
          'client': {
            'id': clientId,
            'version': clientVersion,
            'platform': platform,
            'mode': mode.name,
            // On `client`, not `device` — the schema rejects it there with
            // "unexpected property", which is the only way to find out.
            if (deviceFamily.isNotEmpty) 'deviceFamily': deviceFamily,
          },
          'role': role.name,
          'scopes': scopes,
          if (_signatureToken.isNotEmpty || endpoint.deviceToken.isNotEmpty)
            'auth': {
              if (_signatureToken.isNotEmpty) 'token': _signatureToken,
              if (endpoint.deviceToken.isNotEmpty)
                'deviceToken': endpoint.deviceToken,
              if (endpoint.bootstrapToken.isNotEmpty &&
                  endpoint.token.isEmpty &&
                  endpoint.deviceToken.isEmpty)
                'bootstrapToken': endpoint.bootstrapToken,
            },
          'device': {
            'id': identity.deviceId,
            'publicKey': identity.publicKey,
            'signature': signature,
            'signedAt': signedAt,
            'nonce': nonce,
          },
        },
      }),
    );
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (!(_handshake?.isCompleted ?? true)) _handshake!.completeError(error);
    for (final completer in _pending.values.toList()) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  Future<void> _closeTransport() async {
    final transport = _transport;
    final handshake = _handshake;
    _transport = null;
    _handshake = null;
    await _subscription?.cancel();
    _subscription = null;
    if (!(handshake?.isCompleted ?? true)) {
      handshake!.completeError(
        const ClawRpcException(
          method: 'connect',
          code: 'DISCONNECTED',
          message: 'the connection was replaced',
        ),
      );
    }
    for (final completer in _pending.values.toList()) {
      if (!completer.isCompleted) {
        completer.completeError(
          const ClawRpcException(
            method: 'call',
            code: 'DISCONNECTED',
            message: 'the connection was replaced',
          ),
        );
      }
    }
    _pending.clear();
    await transport?.close();
  }

  /// One RPC.
  ///
  /// [idempotencyKey] is required by the gateway on side-effecting methods and
  /// is the caller's to generate — a key invented in here would be new on every
  /// retry, which is the one thing it must not be.
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> params = const {},
    String? idempotencyKey,
  ]) {
    final transport = _transport;
    if (transport == null) {
      throw const ClawRpcException(
        method: 'call',
        code: 'DISCONNECTED',
        message: 'not connected',
      );
    }
    final id = '${++_nextId}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    transport.send(
      jsonEncode({
        'type': 'req',
        'id': id,
        'method': method,
        'params': {
          ...params,
          if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
        },
      }),
    );
    // The gateway's own request timeout is 30 s; failing marginally after it
    // means a timeout here always means the server really did go quiet.
    return completer.future.timeout(
      const Duration(seconds: 32),
      onTimeout: () {
        _pending.remove(id);
        throw ClawRpcException(
          method: method,
          code: 'TIMEOUT',
          message: 'no response in 32s',
          retryable: true,
        );
      },
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _transport?.close();
    await _events.close();
  }
}
