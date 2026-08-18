/// The gateway's wire envelope.
///
/// Not JSON-RPC, though it rhymes with it: `type` discriminates instead of the
/// presence of `method`, success is an explicit `ok` boolean rather than the
/// absence of `error`, and error codes are strings carrying retry advice.
library;

import 'package:meta/meta.dart';

/// A server→client push.
@immutable
class ClawEvent {
  const ClawEvent({
    required this.name,
    required this.payload,
    this.seq,
    this.stateVersion,
  });

  factory ClawEvent.fromJson(Map<String, dynamic> json) => ClawEvent(
    name: '${json['event'] ?? ''}',
    payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    seq: json['seq'] as int?,
    stateVersion: json['stateVersion']?.toString(),
  );

  final String name;
  final Map<String, dynamic> payload;

  /// Monotonic per connection. Present so a reconnecting client can tell
  /// whether it missed anything; Hermes has no equivalent, which is why the
  /// domain layer treats it as an opaque cursor.
  final int? seq;
  final String? stateVersion;

  @override
  String toString() => 'ClawEvent($name, seq: $seq)';
}

/// A failed request.
///
/// [retryable] and [retryAfterMs] come from the server rather than being
/// inferred from the code, which is the useful difference from JSON-RPC's
/// numeric errors: a client can honour a rate limit it was not told about at
/// compile time.
@immutable
class ClawRpcException implements Exception {
  const ClawRpcException({
    required this.method,
    required this.code,
    required this.message,
    this.detailCode,
    this.retryable = false,
    this.retryAfterMs,
    this.details = const {},
  });

  factory ClawRpcException.fromError(
    String method,
    Map<String, dynamic> error,
  ) {
    final details = (error['details'] as Map?)?.cast<String, dynamic>() ?? {};
    return ClawRpcException(
      method: method,
      code: '${error['code'] ?? 'UNKNOWN'}',
      message: '${error['message'] ?? ''}',
      detailCode: details['code']?.toString(),
      retryable: error['retryable'] == true,
      retryAfterMs: error['retryAfterMs'] as int?,
      details: details,
    );
  }

  final String method;
  final String code;
  final String message;

  /// The finer-grained cause, e.g. `AUTH_TOKEN_MISSING` or
  /// `DEVICE_AUTH_DEVICE_ID_MISMATCH`. This is the field worth switching on —
  /// `code` is usually just `INVALID_REQUEST`.
  final String? detailCode;

  final bool retryable;
  final int? retryAfterMs;
  final Map<String, dynamic> details;

  /// True when the gateway wants a `gateway.auth.token` this client has not
  /// got right. Distinguished because it is not a bug to fix in code — it is a
  /// credential the user has to supply.
  ///
  /// The server separates *absent* from *wrong*, and so does this: told only
  /// "unauthorized", someone will go looking for a mistake in the signature.
  bool get needsGatewayToken =>
      detailCode == 'AUTH_TOKEN_MISSING' ||
      detailCode == 'AUTH_TOKEN_MISMATCH';

  /// The credential was supplied and rejected, rather than never sent.
  bool get gatewayTokenWrong => detailCode == 'AUTH_TOKEN_MISMATCH';

  /// True when the device is not paired yet. Also not a code fix: an operator
  /// has to approve it.
  bool get needsPairing => code == 'NOT_PAIRED';

  @override
  String toString() =>
      'ClawRpcException($method): $code'
      '${detailCode == null ? '' : '/$detailCode'} — $message';
}

/// What the server sends back on a successful `connect`.
@immutable
class ClawHello {
  const ClawHello({
    required this.protocol,
    required this.serverVersion,
    required this.connectionId,
    required this.role,
    required this.scopes,
    required this.maxPayload,
  });

  factory ClawHello.fromJson(Map<String, dynamic> json) {
    final server = (json['server'] as Map?)?.cast<String, dynamic>() ?? const {};
    final auth = (json['auth'] as Map?)?.cast<String, dynamic>() ?? const {};
    final policy = (json['policy'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ClawHello(
      protocol: json['protocol'] as int? ?? 0,
      serverVersion: '${server['version'] ?? ''}',
      connectionId: '${server['connId'] ?? ''}',
      role: '${auth['role'] ?? ''}',
      scopes:
          (auth['scopes'] as List?)?.map((s) => '$s').toList() ?? const [],
      maxPayload: policy['maxPayload'] as int? ?? 0,
    );
  }

  final int protocol;
  final String serverVersion;
  final String connectionId;
  final String role;
  final List<String> scopes;
  final int maxPayload;

  @override
  String toString() =>
      'ClawHello(protocol $protocol, $serverVersion, role $role, '
      '${scopes.length} scopes)';
}
