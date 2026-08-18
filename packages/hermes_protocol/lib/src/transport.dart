import 'dart:async';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The socket the gateway client drives.
///
/// Abstracted so the reconnect and correlation logic — where the real bugs
/// live — can be tested deterministically with a fake, without a server, a
/// network, or a device.
abstract class GatewayTransport {
  Stream<String> get inbound;
  void send(String data);
  Future<void> close();
}

typedef TransportConnector = Future<GatewayTransport> Function(Uri url);

/// Raised when the WebSocket upgrade is refused.
///
/// The three server-side rejection causes — embedded chat disabled, bad
/// credential, disallowed origin — all call `ws.close()` before `accept()`,
/// which Starlette surfaces as a plain HTTP 403. The close code never reaches
/// the client, so [statusCode] alone cannot say which one it was. Feed it to
/// [GatewayDiagnostics] to find out.
class TransportUpgradeException implements Exception {
  TransportUpgradeException(this.statusCode, [String? detail])
      : detail = detail == null ? null : redactCredentials(detail);
  final int statusCode;
  final String? detail;

  /// `dart:io` puts the full request URL in its exception message, credential
  /// and all. That message flows into logs and crash reports, so the token or
  /// ticket has to come out before it is ever stored or displayed.
  static String redactCredentials(String text) => text.replaceAllMapped(
        RegExp(r'([?&](?:token|ticket|internal|api[_-]?key)=)([^&\s#'"'"']*)',
            caseSensitive: false),
        (m) => '${m[1]}<redacted>',
      );

  /// 403 means *some* gate rejected us; it does not by itself mean bad auth.
  bool get isRejected => statusCode == 403 || statusCode == 401;

  @override
  String toString() =>
      'TransportUpgradeException(HTTP $statusCode${detail == null ? '' : ': $detail'})';
}

/// Real transport over `package:web_socket_channel`.
class WebSocketTransport implements GatewayTransport {
  WebSocketTransport._(this._channel);

  final WebSocketChannel _channel;

  /// How often to send a WebSocket ping while the socket is otherwise idle.
  ///
  /// Not decoration. Without it a control-plane socket can die silently — a
  /// reverse proxy drops an idle connection, a laptop sleeps, a tunnel is
  /// re-established — and nothing tells the client. Writes still "succeed"
  /// into the dead half-open socket, no reply ever comes, and the next prompt
  /// fails with a bare 30-second timeout while the UI still reads "connected".
  ///
  /// `dart:io` closes the socket itself when a pong does not come back within
  /// this interval, which turns that silent death into an `onDone` — and from
  /// there the client's existing reconnect and session re-activation take over.
  /// 20 s is comfortably under the 60 s idle timeout typical of the reverse
  /// proxies these deployments sit behind.
  static const defaultPingInterval = Duration(seconds: 20);

  static Future<GatewayTransport> connect(Uri url) => open(url);

  /// [connect] with a custom keepalive. `null` disables pings entirely.
  static Future<GatewayTransport> open(
    Uri url, {
    Duration? pingInterval = defaultPingInterval,
  }) async {
    final channel = IOWebSocketChannel.connect(url, pingInterval: pingInterval);
    try {
      // `ready` completes only once the upgrade succeeds, so a refused upgrade
      // surfaces here rather than as a mysterious immediate close later.
      await channel.ready;
    } on WebSocketChannelException catch (e) {
      final code = _statusFromError(e.inner ?? e);
      if (code != null) throw TransportUpgradeException(code, '$e');
      rethrow;
    }
    return WebSocketTransport._(channel);
  }

  /// `dart:io` reports a refused upgrade as a WebSocketException whose message
  /// carries the status code. There is no structured field for it.
  static int? _statusFromError(Object error) {
    final match = RegExp(r'status(?: code)?[: ]+(\d{3})', caseSensitive: false)
        .firstMatch('$error');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  @override
  Stream<String> get inbound =>
      _channel.stream.map((m) => m is String ? m : String.fromCharCodes(m as List<int>));

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}
