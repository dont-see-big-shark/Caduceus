/// Dart client for the Hermes Agent control plane.
///
/// Targets the `tui_gateway` JSON-RPC WebSocket (`/api/ws`) rather than the
/// OpenAI-compatible HTTP surface, for two measured reasons:
///
///  * `approval.respond` and the rest of the console API exist only there.
///  * `tui_gateway/ws.py` sets `TCP_NODELAY` and coalesces `*.delta` frames on
///    a 33 ms timer; `gateway/platforms/api_server.py` does neither, so the SSE
///    path can accumulate Nagle delay on every flush.
///
/// See `docs/PROTOCOL.md` for how this was established against v0.19.1.
library;

export 'src/console.dart';
export 'src/diagnostics.dart';
export 'src/endpoint.dart';
export 'src/events.dart';
export 'src/events_types.dart';
export 'src/gateway_client.dart';
export 'src/jsonrpc.dart';
export 'src/models.dart';
export 'src/transport.dart';
