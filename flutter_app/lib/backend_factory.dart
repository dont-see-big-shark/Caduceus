/// Building a backend for a saved server.
///
/// Extracted from the connect screen because it was the reason the app could
/// only ever hold one: constructing a backend meant being the connect screen,
/// so nothing else could open a second connection. Everything here was already
/// in `_connect`; the only change is that it is now callable from more than
/// one place.
library;

import 'package:agent_core/agent_core.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';

import 'backends/claw_backend.dart';
import 'backends/claw_identity.dart';
import 'backends/hermes_backend.dart';
import 'connection_store.dart';

/// A backend and, for Hermes, the raw gateway the older panels still need.
///
/// The gateway is exposed only because eight Hermes-only panels talk to it
/// directly and always have. Nothing new should reach for it.
class BuiltBackend {
  const BuiltBackend({required this.backend, this.gateway});

  final AgentBackend backend;
  final HermesGateway? gateway;
}

/// Builds — but does not connect — a backend for [connection].
///
/// Not connected here on purpose. Connecting is where the OpenClaw pairing
/// gate lives, and a caller that wants to *show* that gate needs the backend
/// in hand before it happens.
Future<BuiltBackend> buildBackend(
  SavedConnection connection,
  String token,
) async {
  if (connection.backendId == SavedConnection.openclaw) {
    // The identity is per saved connection, so approving this device on one
    // gateway says nothing about any other, and forgetting a server takes its
    // key with it.
    final identity = await ClawIdentityStore().identityFor(connection.id);
    return BuiltBackend(
      backend: ClawBackend(
        ClawGateway(
          ClawEndpoint(url: Uri.parse(connection.url), token: token),
          identity: identity,
          // Least privilege unless the person asked for writes: a chat
          // client needs read, write and approvals. `operator.admin` (via the
          // connect screen's *Request administrator* control) lets the shared
          // memory base write MEMORY.md through `agents.files.set`. This
          // gateway authenticates by auth token, so a requested admin is
          // granted; the client must still ask, because ClawBackend answers
          // from the intersection of asked and granted.
          scopes: connection.requestAdmin
              ? ClawGateway.adminScopes
              : ClawGateway.chatScopes,
        ),
      ),
    );
  }
  final gateway = HermesGateway(
    HermesEndpoint.parse(connection.url, credential: token),
  );
  return BuiltBackend(
    backend: HermesBackend(gateway, profile: connection.profile),
    gateway: gateway,
  );
}
