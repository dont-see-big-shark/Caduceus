/// Compile-time inputs for reproducible development runs.
library;

import 'package:flutter/foundation.dart';

import 'backends/claw_identity.dart';
import 'connection_store.dart';

/// Connection values supplied to a specific run.
///
/// Every field is intentionally empty by default. Credentials belong in the
/// Keychain after a user connects, not in source or in a binary that every
/// build inherits.
@immutable
class StartupPresets {
  const StartupPresets({
    this.connectionUrl = '',
    this.connectionToken = '',
    this.connectionBackendId = SavedConnection.hermes,
    this.openSessionId = '',
    this.automaticPrompt = '',
    this.openClawUrl = '',
    this.openClawToken = '',
    this.openClawSeed = '',
    this.hermesUrl = '',
    this.hermesToken = '',
  });

  static const openClawConnectionId = '1786619241890131';
  static const hermesConnectionId = '1785639995520898';

  final String connectionUrl;
  final String connectionToken;
  final String connectionBackendId;
  final String openSessionId;
  final String automaticPrompt;
  final String openClawUrl;
  final String openClawToken;
  final String openClawSeed;
  final String hermesUrl;
  final String hermesToken;

  bool get hasConnection =>
      connectionUrl.isNotEmpty && connectionToken.isNotEmpty;
  bool get hasOpenClaw => openClawUrl.isNotEmpty && openClawToken.isNotEmpty;
  bool get hasHermes => hermesUrl.isNotEmpty && hermesToken.isNotEmpty;
}

const startupPresets = StartupPresets(
  connectionUrl: String.fromEnvironment('SERVER_URL'),
  connectionToken: String.fromEnvironment('TOKEN'),
  connectionBackendId: String.fromEnvironment(
    'BACKEND',
    defaultValue: SavedConnection.hermes,
  ),
  openSessionId: String.fromEnvironment('OPEN_SESSION'),
  automaticPrompt: String.fromEnvironment('SAY'),
  openClawUrl: String.fromEnvironment('OPENCLAW_URL'),
  openClawToken: String.fromEnvironment('OPENCLAW_TOKEN'),
  openClawSeed: String.fromEnvironment('OPENCLAW_SEED'),
  hermesUrl: String.fromEnvironment('HERMES_URL'),
  hermesToken: String.fromEnvironment('HERMES_TOKEN'),
);

/// Saves complete development presets, without overwriting existing entries.
///
/// Partial presets are ignored: a URL without its credential would create a
/// saved row that can never connect and gives the user a misleading failure.
Future<void> seedStartupPresets(
  ConnectionStore store, [
  StartupPresets presets = startupPresets,
]) async {
  final existing = await store.list();

  if (presets.hasOpenClaw &&
      !existing.any((c) => c.id == StartupPresets.openClawConnectionId)) {
    await store.save(
      id: StartupPresets.openClawConnectionId,
      label: 'OpenClaw',
      url: presets.openClawUrl,
      token: presets.openClawToken,
      backendId: SavedConnection.openclaw,
      requestAdmin: true,
    );
    if (presets.openClawSeed.isNotEmpty) {
      await ClawIdentityStore().installSeed(
        StartupPresets.openClawConnectionId,
        presets.openClawSeed,
      );
    }
  }

  if (presets.hasHermes &&
      !existing.any((c) => c.id == StartupPresets.hermesConnectionId)) {
    await store.save(
      id: StartupPresets.hermesConnectionId,
      label: 'Hermes',
      url: presets.hermesUrl,
      token: presets.hermesToken,
      backendId: SavedConnection.hermes,
    );
  }
}
