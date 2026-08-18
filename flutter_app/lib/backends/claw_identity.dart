/// Where an OpenClaw device key lives between launches.
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';

/// Persists the Ed25519 identity a gateway pairs with.
///
/// OpenClaw admits a new device only once an operator approves it, and the
/// approval is bound to the device id — which is derived from the keypair. So
/// a client that generates a fresh key on every launch has to be approved on
/// every launch, which makes the pairing flow useless. The seed has to outlive
/// the process.
///
/// The seed *is* the private key, so it gets at least the care
/// `ConnectionStore` gives the gateway token: the macOS Keychain, and never
/// SharedPreferences, which is a plaintext plist. Only the derived `deviceId`
/// and `publicKey` are meant to be shown or sent, and nothing here returns,
/// logs, or prints the seed itself.
class ClawIdentityStore {
  ClawIdentityStore({FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage(mOptions: macOptions);

  /// The same workaround `ConnectionStore` documents, for the same reason.
  ///
  /// The data-protection keychain (the plugin default) requires a
  /// `keychain-access-groups` entitlement, which only resolves under a real
  /// signing team — a locally-signed build fails every read and write with
  /// `errSecMissingEntitlement` (-34018). The legacy file-based keychain needs
  /// no entitlement and is still per-app and encrypted at rest.
  ///
  /// `usesDataProtectionKeychain: false` is the line that selects it; the
  /// plugin's default is `true`. Both stores must be flipped together when a
  /// signed distribution build adds the entitlement; a device key stranded in
  /// the other keychain reads back as "never paired".
  @visibleForTesting
  static const macOptions = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock,
    usesDataProtectionKeychain: false,
  );

  /// Deliberately not `ConnectionStore`'s `caduceus.token.` prefix: a seed and
  /// a token are different secrets with different lifetimes, and keeping the
  /// namespaces apart means neither store can read or delete the other's
  /// entries by accident.
  static const _seedPrefix = 'caduceus.claw.seed.';

  /// Ed25519 seeds are 32 bytes. Anything else did not come from us.
  static const _seedBytes = 32;

  final FlutterSecureStorage _secure;

  /// Generation in flight, per connection.
  ///
  /// Two callers asking at once would otherwise each generate a key and race
  /// to store it, leaving the loser holding an identity whose seed was never
  /// persisted — it would connect, get approved, and be gone after a restart.
  final Map<String, Future<ClawDeviceIdentity>> _pending = {};

  String _keyFor(String connectionId) => '$_seedPrefix$connectionId';

  /// The identity to connect [connectionId] with, generating one if needed.
  ///
  /// Keyed per saved connection rather than once per app, deliberately. Two
  /// gateways sharing one identity would mean one operator's approval decides
  /// what an unrelated server trusts, that either server can recognise the
  /// device the other paired with, and that revoking access to one forces
  /// rotating the key the other has already approved. Per connection, each
  /// pairing stands and falls alone.
  /// Installs a known seed (base64) for [connectionId] when none is stored.
  ///
  /// Used to carry an already-approved desktop device identity into a mobile
  /// build: same seed, same derived device id, so the gateway keeps trusting
  /// the device instead of asking an operator to approve it again. Never
  /// overwrites an existing seed — a real pairing already on this device wins.
  Future<bool> installSeed(String connectionId, String base64Seed) async {
    if (await _secure.read(key: _keyFor(connectionId)) != null) return false;
    await _secure.write(key: _keyFor(connectionId), value: base64Seed);
    return true;
  }

  Future<ClawDeviceIdentity> identityFor(String connectionId) {
    final pending = _pending[connectionId];
    if (pending != null) return pending;
    final resolving = _resolve(connectionId);
    _pending[connectionId] = resolving;
    return resolving.whenComplete(() => _pending.remove(connectionId));
  }

  /// The device id an operator has to approve, or null if there is none yet.
  ///
  /// Reading must not have the side effect of creating: a "waiting to be
  /// approved" screen that minted a key just by being opened would file a
  /// pairing request for a connection the user may never make.
  Future<String?> deviceIdFor(String connectionId) async =>
      (await _restore(connectionId))?.deviceId;

  /// Deletes the key for a connection.
  ///
  /// Call this whenever a connection is forgotten. `ConnectionStore.remove`
  /// deletes the token for the same reason: an orphan in the Keychain outlives
  /// every piece of UI that could offer to remove it, and this orphan is a
  /// private key.
  Future<void> forget(String connectionId) async {
    _pending.remove(connectionId);
    await _secure.delete(key: _keyFor(connectionId));
  }

  Future<ClawDeviceIdentity> _resolve(String connectionId) async {
    final stored = await _restore(connectionId);
    if (stored != null) return stored;

    final identity = await ClawDeviceIdentity.generate();
    await _secure.write(
      key: _keyFor(connectionId),
      value: base64.encode(await identity.extractSeed()),
    );
    return identity;
  }

  /// Rebuilds the stored identity, or null when there is no usable one.
  ///
  /// A value that is not valid base64, not [_seedBytes] long, or that Ed25519
  /// refuses is treated as absent rather than fatal — one bad Keychain entry
  /// must not be able to make the app unlaunchable, and the recovery (a new
  /// key, approved again) is one the user can actually complete.
  Future<ClawDeviceIdentity?> _restore(String connectionId) async {
    final stored = await _secure.read(key: _keyFor(connectionId));
    if (stored == null || stored.isEmpty) return null;

    final List<int> seed;
    try {
      seed = base64.decode(stored);
    } on FormatException {
      _discarded(connectionId, 'it is not valid base64');
      return null;
    }
    if (seed.length != _seedBytes) {
      _discarded(connectionId, 'it is ${seed.length} bytes, not $_seedBytes');
      return null;
    }
    try {
      return await ClawDeviceIdentity.fromSeed(seed);
    } catch (_) {
      // Deliberately unfiltered: the point is that no failure to read one
      // stored key can take the app down, and a key derivation can fail with
      // an Error as easily as an Exception.
      _discarded(connectionId, 'Ed25519 rejected it');
      return null;
    }
  }

  /// Reports a discarded key without quoting any of it.
  ///
  /// The caught error is not passed along on purpose: a [FormatException]
  /// quotes the input it choked on, and that input is key material.
  void _discarded(String connectionId, String because) => developer.log(
    'Ignoring the stored OpenClaw device key for connection $connectionId: '
    '$because. The next connection generates a fresh identity, which an '
    'operator has to approve again.',
    name: 'caduceus.claw.identity',
    level: 900,
  );
}
