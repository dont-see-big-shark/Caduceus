import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'endpoint.dart';
import 'transport.dart';

/// What actually went wrong, as far as it can be determined.
enum GatewayFault {
  reachable,
  hostUnreachable,
  portClosed,
  notHermes,

  /// Server is in gated mode; a session token will always be refused there.
  credentialWrongMode,

  /// Server accepts tokens but rejected this one.
  credentialRejected,

  /// Reached and healthy, cause not determined.
  unknown,
}

/// The result of probing a control plane that refused a WebSocket upgrade.
@immutable
class GatewayDiagnosis {
  const GatewayDiagnosis(this.fault, this.summary, this.remedy);
  final GatewayFault fault;
  final String summary;

  /// Something the user can actually do — a command to run or a setting to
  /// change. Never a bare status code.
  final String remedy;

  @override
  String toString() => '$summary\n  → $remedy';
}

/// Explains a refused WebSocket upgrade.
///
/// All three server-side rejection paths (`_DASHBOARD_EMBEDDED_CHAT_ENABLED`
/// false, `_ws_auth_ok` false, `_ws_request_is_allowed` false) call
/// `ws.close()` before `accept()`, which Starlette turns into an identical
/// plain HTTP 403. The close codes 4401/4403 never reach the client, so the
/// socket alone cannot distinguish "wrong password" from "wrong mode" from
/// "feature disabled".
///
/// `GET /api/status` is unauthenticated on a loopback bind and reports
/// `auth_required` / `auth_providers`, which is enough to tell the common cases
/// apart. This is the difference between the community's undiagnosable
/// "connection refused" reports and an error a user can act on.
class GatewayDiagnostics {
  GatewayDiagnostics({http.Client? client, this.timeout = const Duration(seconds: 5)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// Explains why a connection attempt failed.
  ///
  /// [cause] is the error that was actually thrown. It matters: only a refused
  /// WebSocket upgrade is evidence of a credential problem. An earlier version
  /// ignored it and reported "Hermes rejected this token" for *any* failure —
  /// including errors raised long after a successful connect — which is worse
  /// than showing the raw error, because it is confidently wrong.
  Future<GatewayDiagnosis> diagnose(
    HermesEndpoint endpoint, {
    Object? cause,
  }) async {
    if (cause != null && cause is! TransportUpgradeException) {
      return GatewayDiagnosis(
        GatewayFault.unknown,
        'The connection failed, but not because the server refused it: $cause',
        'This is not a credential problem. Check the details above; if it '
            'persists, the error text is the thing to report.',
      );
    }
    return _diagnoseCredential(endpoint);
  }

  Future<GatewayDiagnosis> _diagnoseCredential(HermesEndpoint endpoint) async {
    final http.Response response;
    try {
      response = await _client.get(endpoint.statusUri).timeout(timeout);
    } catch (e) {
      return _unreachable(endpoint, e);
    }

    if (response.statusCode != 200) {
      return GatewayDiagnosis(
        GatewayFault.notHermes,
        'Something is listening on ${endpoint.host}:${endpoint.port}, but '
            '/api/status returned HTTP ${response.statusCode}.',
        'Check the port. The control plane is `hermes serve` (default 9119), '
            'which is not the same service as the OpenAI-compatible API server '
            '(default 8642).',
      );
    }

    Map<String, dynamic> status;
    try {
      final decoded = jsonDecode(response.body);
      status = decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const GatewayDiagnosis(
        GatewayFault.notHermes,
        'The port answered but did not return Hermes status JSON.',
        'Confirm nothing else is bound to that port.',
      );
    }

    final authRequired = status['auth_required'] == true;
    final providers = (status['auth_providers'] as List?)?.join(', ') ?? '';

    // A gated server rejects `?token=` unconditionally — no amount of
    // retrying or re-copying the token will help, so say so plainly.
    if (authRequired && endpoint.authMode == GatewayAuthMode.loopbackToken) {
      return GatewayDiagnosis(
        GatewayFault.credentialWrongMode,
        'This Hermes is in gated mode'
            '${providers.isEmpty ? '' : ' (auth providers: $providers)'}, where '
            'session tokens are always rejected. It needs a single-use ticket.',
        'Easiest fix: reach it over an SSH or Tailscale tunnel so Hermes stays '
            'bound to loopback, then a session token works. Otherwise sign in to '
            'the dashboard so the app can mint a 30-second ticket per connection.',
      );
    }

    if (!authRequired && endpoint.authMode == GatewayAuthMode.gatedTicket) {
      return const GatewayDiagnosis(
        GatewayFault.credentialWrongMode,
        'This Hermes is on a loopback bind and expects a session token, but the '
            'app offered a ticket.',
        'Switch this connection to token auth and supply the value of '
            'HERMES_DASHBOARD_SESSION_TOKEN.',
      );
    }

    if (!authRequired) {
      return const GatewayDiagnosis(
        GatewayFault.credentialRejected,
        'Hermes is reachable and accepting session tokens, but rejected this '
            'one.',
        'The token is regenerated on every restart unless pinned. Start Hermes '
            'with HERMES_DASHBOARD_SESSION_TOKEN set to a fixed value, then use '
            'that value here.',
      );
    }

    return const GatewayDiagnosis(
      GatewayFault.credentialRejected,
      'Hermes is reachable and gated, but the ticket was refused.',
      'Tickets are single-use and expire after 30 seconds — mint a fresh one '
          'immediately before connecting, including on every reconnect.',
    );
  }

  GatewayDiagnosis _unreachable(HermesEndpoint endpoint, Object error) {
    final text = '$error'.toLowerCase();
    if (text.contains('refused')) {
      return GatewayDiagnosis(
        GatewayFault.portClosed,
        'Nothing is listening on ${endpoint.host}:${endpoint.port}.',
        'Start it with `hermes serve`, or check the tunnel is still forwarding '
            'that port.',
      );
    }
    return GatewayDiagnosis(
      GatewayFault.hostUnreachable,
      'Could not reach ${endpoint.host}:${endpoint.port} — $error',
      'Check the device is on the same network, or that Tailscale is connected.',
    );
  }

  void close() => _client.close();
}
