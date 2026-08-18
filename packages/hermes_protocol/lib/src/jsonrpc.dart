import 'dart:convert';

import 'package:meta/meta.dart';

/// Frames on the tui_gateway socket are JSON-RPC 2.0, but the channel is not
/// request/response only: the server pushes notifications with a `method` and
/// no `id` at any time, including one (`gateway.ready`) before the client has
/// sent anything. A client that only correlates by `id` silently drops them.
sealed class GatewayFrame {
  const GatewayFrame();

  /// Classifies one inbound frame. Returns [MalformedFrame] rather than
  /// throwing — a peer that sends one bad frame should not tear down a live
  /// session, and the caller decides whether to log or ignore.
  static GatewayFrame parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      return MalformedFrame(raw, 'not JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      return MalformedFrame(raw, 'expected a JSON object');
    }

    final id = decoded['id'];
    final method = decoded['method'];

    // Notification: method, no id. This is the server-push path.
    if (id == null && method is String) {
      final params = decoded['params'];
      return GatewayNotification(
        method,
        params is Map<String, dynamic> ? params : const {},
      );
    }

    if (id != null) {
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        return GatewayErrorResponse(
          id,
          code: error['code'] is int ? error['code'] as int : 0,
          message: error['message']?.toString() ?? 'unknown error',
          data: error['data'],
        );
      }
      return GatewayResult(id, decoded['result']);
    }

    return MalformedFrame(raw, 'neither a notification nor a response');
  }

  static String encodeRequest(
    Object id,
    String method,
    Map<String, dynamic> params,
  ) =>
      jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
        'id': id,
      });
}

/// Server-initiated event. High-frequency `*.delta` frames arrive here.
@immutable
class GatewayNotification extends GatewayFrame {
  const GatewayNotification(this.method, this.params);
  final String method;
  final Map<String, dynamic> params;

  @override
  String toString() => 'GatewayNotification($method)';
}

@immutable
class GatewayResult extends GatewayFrame {
  const GatewayResult(this.id, this.result);
  final Object id;
  final Object? result;
}

@immutable
class GatewayErrorResponse extends GatewayFrame {
  const GatewayErrorResponse(
    this.id, {
    required this.code,
    required this.message,
    this.data,
  });
  final Object id;
  final int code;
  final String message;
  final Object? data;
}

@immutable
class MalformedFrame extends GatewayFrame {
  const MalformedFrame(this.raw, this.reason);
  final String raw;
  final String reason;

  @override
  String toString() => 'MalformedFrame($reason)';
}

/// A JSON-RPC error returned by the gateway.
class GatewayRpcException implements Exception {
  GatewayRpcException(this.method, this.code, this.message, [this.data]);
  final String method;
  final int code;
  final String message;
  final Object? data;

  /// -32601. Worth distinguishing: it means this Hermes build does not have the
  /// method, which is a capability signal rather than a failure.
  bool get isUnknownMethod => code == -32601;

  @override
  String toString() => 'GatewayRpcException($method): $message (code $code)';
}

/// Helper extension to extract user-facing error messages from RPC exceptions or standard errors.
extension GatewayErrorFormatting on Object {
  String get userFacingMessage =>
      this is GatewayRpcException ? (this as GatewayRpcException).message : toString();
}
