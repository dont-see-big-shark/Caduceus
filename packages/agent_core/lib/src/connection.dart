/// Where a backend's connection stands, in terms the UI can render.
library;

import 'package:meta/meta.dart';

/// The states a connection to an agent can be in.
///
/// [awaitingApproval] is the one Hermes never needed and OpenClaw forces.
/// Hermes puts a token in the URL: the socket either opens or it does not, so
/// two outcomes covered everything. OpenClaw's connection is a two-step story
/// — handshake, then device pairing — and a client that has authenticated
/// correctly but is not yet approved is in neither of the old buckets. Showing
/// it as an error is wrong (nothing failed, and retrying will not help) and
/// showing it as connecting is worse (it will sit there until a human on
/// another device does something, with no hint that they must).
enum AgentStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,

  /// Authenticated, but the device is waiting for an operator to approve it.
  /// Nothing is wrong and nothing will change without human action elsewhere.
  awaitingApproval,

  /// Will not recover by retrying. A bad credential, a refused pairing, a
  /// protocol version the client cannot speak.
  fatal,
}

/// A connection state and why it is that.
@immutable
class AgentConnection {
  const AgentConnection(
    this.status, {
    this.attempt = 0,
    this.error,
    this.detail = '',
  });

  static const disconnected = AgentConnection(AgentStatus.disconnected);

  final AgentStatus status;

  /// Which reconnect attempt this is, for a UI that counts them.
  final int attempt;

  final Object? error;

  /// Something worth showing the user beyond the status — the pairing code to
  /// approve, the protocol version that was refused. Free text on purpose:
  /// it is displayed, never parsed.
  final String detail;

  bool get isConnected => status == AgentStatus.connected;

  /// True while the UI should show progress rather than an error.
  bool get isSettling =>
      status == AgentStatus.connecting || status == AgentStatus.reconnecting;

  /// True when only a human, elsewhere, can move this forward.
  bool get needsApproval => status == AgentStatus.awaitingApproval;

  @override
  String toString() => 'AgentConnection(${status.name}'
      '${attempt > 0 ? ', attempt $attempt' : ''}'
      '${error == null ? '' : ', $error'})';
}
