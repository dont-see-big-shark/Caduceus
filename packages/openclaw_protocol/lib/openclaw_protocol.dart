/// A Dart client for the OpenClaw gateway WebSocket protocol (v4).
///
/// The handshake in here was established against a live gateway, by sending
/// deliberately incomplete frames and reading what the server said was missing.
/// Every constant it depends on — the device-id derivation, the base64url
/// encodings, the signed payload's field order, the closed sets `client.id`,
/// `client.mode` and `role` are validated against — is documented at the line
/// that uses it, because none of it appears in the published protocol docs.
library;

export 'src/device_identity.dart';
export 'src/frames.dart';
export 'src/gateway.dart';
export 'src/sessions.dart';
