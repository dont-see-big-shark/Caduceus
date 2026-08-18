/// The Ed25519 identity a client proves it holds when it connects.
///
/// Every value in here is byte-for-byte what the gateway computes on its side,
/// established by connecting to a real server and reading its rejections until
/// they stopped — not from documentation, which does not specify any of it. The
/// three that matter, and the error each one produces when wrong:
///
///  * `deviceId` is the **hex** SHA-256 of the *raw* 32-byte public key.
///    Anything else answers `DEVICE_AUTH_DEVICE_ID_MISMATCH`.
///  * `publicKey` is the raw key in **unpadded base64url**, not the PEM and not
///    standard base64.
///  * `signature` is over a `|`-joined string whose field order is fixed, in
///    the same unpadded base64url.
///
/// Reference: `src/infra/device-identity-store.ts` (`fingerprintPublicKey`),
/// `src/infra/ed25519-signature.ts`, `packages/gateway-client/src/device-auth.ts`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:caduceus_native/caduceus_native.dart';
import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// Unpadded base64url — the gateway's `base64UrlEncode`.
String base64UrlUnpadded(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A device keypair, and the two derived strings the gateway checks.
@immutable
class ClawDeviceIdentity {
  const ClawDeviceIdentity({
    required this.deviceId,
    required this.publicKey,
    required SimpleKeyPair keyPair,
  }) : _keyPair = keyPair;

  /// Generates a fresh identity. The caller is responsible for persisting the
  /// seed: a device that regenerates its key on every launch has to be paired
  /// again on every launch.
  static Future<ClawDeviceIdentity> generate() async {
    final keyPair = await Ed25519().newKeyPair();
    return fromKeyPair(keyPair);
  }

  /// Restores from a stored 32-byte seed.
  static Future<ClawDeviceIdentity> fromSeed(List<int> seed) async =>
      fromKeyPair(await Ed25519().newKeyPairFromSeed(seed));

  static Future<ClawDeviceIdentity> fromKeyPair(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    final raw = publicKey.bytes;
    final nativeHash = CryptoNative.sha256(Uint8List.fromList(raw));
    final deviceId = nativeHash != null
        ? _hex(nativeHash)
        : _hex((await Sha256().hash(raw)).bytes);

    return ClawDeviceIdentity(
      deviceId: deviceId,
      publicKey: base64UrlUnpadded(raw),
      keyPair: keyPair,
    );
  }

  /// SHA-256 of the raw public key, in lowercase hex.
  final String deviceId;

  /// The raw public key in unpadded base64url.
  final String publicKey;

  final SimpleKeyPair _keyPair;

  /// The 32-byte seed, for storing this identity somewhere safe.
  Future<List<int>> extractSeed() => _keyPair.extractPrivateKeyBytes();

  Future<String> sign(String payload) async {
    final signature = await Ed25519().sign(
      utf8.encode(payload),
      keyPair: _keyPair,
    );
    return base64UrlUnpadded(signature.bytes);
  }
}

/// The exact string a device signature is taken over.
///
/// `buildDeviceAuthPayloadV3`. Field order is load-bearing and the gateway
/// compares the result byte for byte, so nothing here may be reordered,
/// omitted, or left null — an absent value is the empty string between two
/// pipes. `platform` and `deviceFamily` are lowercased first, which is the one
/// piece of normalisation the server does and the client must match.
///
/// The **token is part of the payload**. A client that signs before choosing
/// its credential signs the wrong thing.
String deviceAuthPayloadV3({
  required String deviceId,
  required String clientId,
  required String clientMode,
  required String role,
  required List<String> scopes,
  required int signedAtMs,
  required String nonce,
  String token = '',
  String platform = '',
  String deviceFamily = '',
}) => [
  'v3',
  deviceId,
  clientId,
  clientMode,
  role,
  scopes.join(','),
  '$signedAtMs',
  token,
  nonce,
  platform.toLowerCase(),
  deviceFamily.toLowerCase(),
].join('|');
