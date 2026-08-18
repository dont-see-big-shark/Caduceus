import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';

import 'endpoint.dart';
import 'events.dart';
import 'jsonrpc.dart';
import 'transport.dart';

enum GatewayStatus { disconnected, connecting, connected, reconnecting, fatal }

@immutable
class GatewayConnectionState {
  const GatewayConnectionState(this.status, {this.attempt = 0, this.error});
  final GatewayStatus status;
  final int attempt;
  final Object? error;

  bool get isConnected => status == GatewayStatus.connected;

  @override
  String toString() =>
      'GatewayConnectionState(${status.name}'
      '${attempt > 0 ? ', attempt $attempt' : ''}'
      '${error == null ? '' : ', $error'})';
}

/// Client for the Hermes control plane (`/api/ws`).
///
/// Deliberately does no batching of its own: `tui_gateway/ws.py` already
/// coalesces `*.delta` frames on a 33 ms timer (`_TOKEN_COALESCE_S`) and sets
/// `TCP_NODELAY`, so the transport arrives pre-smoothed at ~30 fps. Adding a
/// second buffer here would only add latency. Frame batching belongs in the
/// render layer, where it was measured to matter.
class HermesGateway {
  HermesGateway(
    this.endpoint, {
    TransportConnector? connector,
    this.callTimeout = const Duration(seconds: 30),
    this.maxReconnectAttempts = 8,
    Duration baseBackoff = const Duration(milliseconds: 500),
    Duration maxBackoff = const Duration(seconds: 30),
    Future<String> Function()? refreshCredential,
    Random? random,
  }) : _connect = connector ?? WebSocketTransport.connect,
       _baseBackoff = baseBackoff,
       _maxBackoff = maxBackoff,
       _refreshCredential = refreshCredential,
       _random = random ?? Random();

  HermesEndpoint endpoint;

  final TransportConnector _connect;
  final Duration callTimeout;
  final int maxReconnectAttempts;
  final Duration _baseBackoff;
  final Duration _maxBackoff;
  final Random _random;

  /// Mints a fresh credential before each attempt. Required for
  /// [GatewayAuthMode.gatedTicket], whose tickets are single-use with a 30 s
  /// TTL and therefore cannot survive a reconnect.
  final Future<String> Function()? _refreshCredential;

  GatewayTransport? _transport;
  StreamSubscription<String>? _sub;
  Timer? _reconnectTimer;
  int _nextId = 1;
  bool _disposed = false;

  final Map<Object, _PendingCall> _pending = {};

  /// When the last frame of any kind arrived.
  ///
  /// A call can time out for two very different reasons: the socket is dead,
  /// or that one method simply never answers. `usage.bars` on 0.19.x is the
  /// second kind — it hangs indefinitely while the connection stays perfectly
  /// healthy. Tearing down a live socket over one bad method would drop every
  /// other session's stream with it, so the timeout only recycles the
  /// transport when *nothing at all* has been received meanwhile.
  DateTime _lastInbound = DateTime.now();

  /// Id of the in-flight liveness probe, if any. See [_startLivenessProbe].
  Object? _probeId;

  final _events = StreamController<GatewayEvent>.broadcast();
  final _notifications = StreamController<GatewayNotification>.broadcast();
  final _state = StreamController<GatewayConnectionState>.broadcast();
  var _current = const GatewayConnectionState(GatewayStatus.disconnected);

  /// Control-plane events, unwrapped from the `"event"` envelope the server
  /// puts every push inside. Switch on [GatewayEvent.type], not on the
  /// JSON-RPC method — the method is `"event"` for all of them.
  Stream<GatewayEvent> get events => _events.stream;

  /// Raw notifications, for frames that are not event envelopes.
  Stream<GatewayNotification> get notifications => _notifications.stream;

  Stream<GatewayConnectionState> get connectionState => _state.stream;
  GatewayConnectionState get state => _current;

  void _setState(GatewayStatus status, {int attempt = 0, Object? error}) {
    _current = GatewayConnectionState(status, attempt: attempt, error: error);
    if (!_state.isClosed) _state.add(_current);
  }

  Future<void> connect() async {
    if (_disposed) throw StateError('HermesGateway has been disposed');
    _reconnectTimer?.cancel();
    await _closeTransport();
    await _openOnce(attempt: 0);
  }

  Future<void> _openOnce({required int attempt}) async {
    _setState(
      attempt == 0 ? GatewayStatus.connecting : GatewayStatus.reconnecting,
      attempt: attempt,
    );

    try {
      if (_refreshCredential != null && endpoint.credentialIsSingleUse) {
        endpoint = endpoint.withCredential(await _refreshCredential());
      }

      final transport = await _connect(endpoint.gatewayWsUri);
      _transport = transport;
      _lastInbound = DateTime.now();
      _sub = transport.inbound.listen(
        _onFrame,
        // hermes-android's abandoned client omitted onError entirely, so a
        // socket error became an unhandled async exception.
        onError: (Object e, StackTrace s) => _onDisconnected(e),
        onDone: () => _onDisconnected(null),
        cancelOnError: false,
      );
      _setState(GatewayStatus.connected);
    } on TransportUpgradeException catch (e) {
      // A refused upgrade will be refused identically forever. Retrying an
      // auth failure just burns battery and hides the real problem from the
      // user, so this is terminal until the caller supplies a new credential.
      _failAllPending(e);
      _setState(GatewayStatus.fatal, attempt: attempt, error: e);
      rethrow;
    } catch (e) {
      _failAllPending(e);
      _scheduleReconnect(attempt + 1, e);
      rethrow;
    }
  }

  void _onDisconnected(Object? error) {
    _sub?.cancel();
    _sub = null;
    _transport = null;
    _failAllPending(error ?? const GatewayDisconnected());
    if (_disposed || _current.status == GatewayStatus.fatal) return;
    _scheduleReconnect(1, error);
  }

  void _scheduleReconnect(int attempt, Object? error) {
    if (_disposed) return;
    if (attempt > maxReconnectAttempts) {
      _setState(GatewayStatus.fatal, attempt: attempt, error: error);
      return;
    }
    _setState(GatewayStatus.reconnecting, attempt: attempt, error: error);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoffFor(attempt), () {
      // Swallowed deliberately: _openOnce already reported the outcome through
      // connectionState, and there is no caller awaiting this attempt.
      _openOnce(attempt: attempt).ignore();
    });
  }

  /// Exponential backoff with full jitter, capped. Jitter matters when several
  /// clients (phone, laptop, tablet) lose a tunnel at the same moment.
  @visibleForTesting
  Duration backoffFor(int attempt) {
    final exp = _baseBackoff.inMilliseconds * pow(2, attempt - 1);
    final capped = min(exp.toDouble(), _maxBackoff.inMilliseconds.toDouble());
    return Duration(milliseconds: _random.nextInt(capped.toInt() + 1));
  }

  void _onFrame(String raw) {
    _lastInbound = DateTime.now();
    final frame = GatewayFrame.parse(raw);
    switch (frame) {
      case GatewayNotification():
        if (!_notifications.isClosed) _notifications.add(frame);
        final event = GatewayEvent.fromNotification(frame);
        if (event != null && !_events.isClosed) _events.add(event);
      case GatewayResult(:final id, :final result):
        _pending.remove(id)?.complete(result);
      case GatewayErrorResponse(
        :final id,
        :final code,
        :final message,
        :final data,
      ):
        final call = _pending.remove(id);
        call?.completeError(
          GatewayRpcException(call.method, code, message, data),
        );
      case MalformedFrame():
        // Dropped on purpose. One bad frame must not kill a live session, and
        // there is no id to fail a caller against.
        break;
    }
  }

  /// Invoke a control-plane method and await its result.
  /// Invoke a control-plane method and await its result.
  ///
  /// [timeout] overrides [callTimeout] for methods that are legitimately slow
  /// — `reload.mcp` restarts every MCP server, and a 30 s ceiling would fail a
  /// call that was going to succeed.
  Future<Object?> call(
    String method, [
    Map<String, dynamic> params = const {},
    Duration? timeout,
  ]) {
    if (_disposed) throw StateError('HermesGateway has been disposed');
    final transport = _transport;
    if (transport == null) {
      return Future.error(const GatewayDisconnected());
    }

    final id = _nextId++;
    final completer = Completer<Object?>();
    // The timer is cancelled on *every* exit path — success, error, and
    // disconnect — so a completed call cannot leave a pending entry behind.
    final limit = timeout ?? callTimeout;
    final timer = Timer(limit, () {
      _pending
          .remove(id)
          ?.completeError(
            GatewayRpcException(method, -32000, 'timeout after $limit'),
          );
      // Silence is the signal, not slowness. If other frames arrived while
      // this call was outstanding the socket is fine and only this method is
      // stuck; recycling would take every live stream down with it.
      if (DateTime.now().difference(_lastInbound) < limit) return;
      // Silence alone is still not proof: on an idle connection a hung method
      // and a dead socket look identical. Ask a question known to answer, and
      // only tear down if that goes unanswered too.
      if (id == _probeId) {
        _probeId = null;
        _recycleTransport();
      } else if (_probeId == null) {
        _startLivenessProbe().ignore();
      }
    });
    _pending[id] = _PendingCall(method, completer, timer);

    try {
      transport.send(GatewayFrame.encodeRequest(id, method, params));
    } catch (e) {
      _pending.remove(id)?.completeError(e);
    }
    return completer.future;
  }

  /// Tells a hung call apart from a dead socket.
  ///
  /// Deliberately a method the server does *not* implement. An error frame is
  /// still a frame, and `-32601` is produced at dispatch — before any handler,
  /// lock or database — so nothing on the server can make this hang. A real
  /// method cannot promise that: `session.list` was the first choice here and
  /// it wedged on the reference server while `agents.list` on the same socket
  /// kept answering in 282 ms, which is exactly the failure this probe exists
  /// to distinguish.
  Future<void> _startLivenessProbe() async {
    // call() assigns ids synchronously from _nextId, so this is the id the
    // probe below will take.
    _probeId = _nextId;
    // A quarter of the call budget, so a stuck connection is still detected
    // within a fraction of the time a caller already agreed to wait.
    final budget = Duration(
      milliseconds: max(50, min(10000, callTimeout.inMilliseconds ~/ 4)),
    );
    try {
      await call('caduceus.ping', const {}, budget);
    } catch (_) {
      // Every outcome is handled elsewhere: an unknown-method error means the
      // socket carried a frame both ways, a timeout is dealt with by the timer
      // above, and a disconnect means the recycle already happened. What must
      // not happen is this future reaching the zone unhandled — it outlives
      // the client on dispose and crashes the app after the fact.
    } finally {
      _probeId = null;
    }
  }

  /// Makes one request whose success or protocol error both prove liveness.
  ///
  /// `caduceus.ping` is intentionally not a real server method: dispatching it
  /// and returning `-32601` happens before any handler can block, so either
  /// outcome means the transport carried a frame both ways.
  Future<void> verifyConnection() async {
    try {
      await call('caduceus.ping', const {}, const Duration(seconds: 5));
    } on GatewayRpcException {
      // A response from the server is itself the proof being asked for.
    }
  }

  /// Discards a socket that is presumed dead and starts reconnecting.
  ///
  /// Safe to call when there is nothing to discard; a transport already gone
  /// means the disconnect path has run.
  void _recycleTransport() {
    if (_disposed) return;
    final transport = _transport;
    if (transport == null) return;
    _transport = null;
    _sub?.cancel();
    _sub = null;
    // Best-effort: the socket may already be unwritable, and the close is
    // only a courtesy to the server at this point.
    transport.close().ignore();
    _onDisconnected(const GatewayDisconnected());
  }

  Future<void> _closeTransport() async {
    final transport = _transport;
    _transport = null;
    await _sub?.cancel();
    _sub = null;
    _failAllPending(const GatewayDisconnected());
    await transport?.close();
  }

  void _failAllPending(Object error) {
    // Copy first: completeError can synchronously run listeners that call back
    // into this client and mutate _pending underneath the iteration.
    final calls = List.of(_pending.values);
    _pending.clear();
    for (final call in calls) {
      call.completeError(error);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _failAllPending(const GatewayDisconnected());
    await _sub?.cancel();
    _sub = null;
    await _transport?.close();
    _transport = null;
    _setState(GatewayStatus.disconnected);
    await _events.close();
    await _notifications.close();
    await _state.close();
  }
}

class GatewayDisconnected implements Exception {
  const GatewayDisconnected();
  @override
  String toString() =>
      'GatewayDisconnected: not connected to the control plane';
}

class _PendingCall {
  _PendingCall(this.method, this._completer, this._timer);
  final String method;
  final Completer<Object?> _completer;
  final Timer _timer;

  void complete(Object? value) {
    _timer.cancel();
    if (!_completer.isCompleted) _completer.complete(value);
  }

  void completeError(Object error) {
    _timer.cancel();
    if (!_completer.isCompleted) _completer.completeError(error);
  }
}
