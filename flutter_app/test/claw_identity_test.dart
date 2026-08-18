/// The OpenClaw device key survives a relaunch, and nothing else escapes.
///
/// Two failures this file exists to catch, both silent in ordinary use:
///
///  * An identity that does not round-trip. Everything looks right — the app
///    connects, the device id is shown, an operator approves it — and then the
///    next launch asks to be approved again, because the key was regenerated.
///  * A seed that leaks out of the store. It is an Ed25519 private key, so
///    anywhere it lands that is not the Keychain (a `toString()`, a log line,
///    SharedPreferences) is a place a pairing can be stolen from.
library;

import 'dart:convert';

import 'package:caduceus/backends/claw_identity.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The key the store is expected to use, spelled out rather than imported.
///
/// Writing it here is the assertion: it must stay distinct from
/// `ConnectionStore`'s `caduceus.token.`, and a change to either prefix is a
/// migration that silently un-pairs every device, so it should fail a test.
String _seedKey(String connectionId) => 'caduceus.claw.seed.$connectionId';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> keychain;

  setUp(() {
    keychain = <String, String>{};
    FlutterSecureStorage.setMockInitialValues(keychain);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('an identity survives being reloaded by a new store', () async {
    final first = await ClawIdentityStore().identityFor('c1');
    final second = await ClawIdentityStore().identityFor('c1');

    expect(second.deviceId, first.deviceId);
    expect(second.publicKey, first.publicKey);
  });

  test('the same store answers consistently, even concurrently', () async {
    final store = ClawIdentityStore();
    final both = await Future.wait([
      store.identityFor('c1'),
      store.identityFor('c1'),
    ]);

    expect(both[1].deviceId, both[0].deviceId);
    // The loser of a generation race would hold an identity whose seed was
    // never stored, so check what a later launch would read.
    expect(await ClawIdentityStore().deviceIdFor('c1'), both[0].deviceId);
  });

  test('two connections get two identities', () async {
    final store = ClawIdentityStore();
    final one = await store.identityFor('c1');
    final two = await store.identityFor('c2');

    expect(two.deviceId, isNot(one.deviceId));
    expect(keychain.keys, containsAll([_seedKey('c1'), _seedKey('c2')]));
  });

  test('forget removes the key, and only that one', () async {
    final store = ClawIdentityStore();
    final kept = await store.identityFor('c2');
    await store.identityFor('c1');

    await store.forget('c1');

    expect(keychain, isNot(contains(_seedKey('c1'))));
    expect(await store.deviceIdFor('c1'), isNull);
    expect(await store.deviceIdFor('c2'), kept.deviceId);
  });

  test('forgetting then asking again yields a different identity', () async {
    final store = ClawIdentityStore();
    final before = await store.identityFor('c1');
    await store.forget('c1');

    expect((await store.identityFor('c1')).deviceId, isNot(before.deviceId));
  });

  test('deviceIdFor is null before there is an identity', () async {
    final store = ClawIdentityStore();

    expect(await store.deviceIdFor('c1'), isNull);
    // Showing an id must not be what creates one.
    expect(keychain, isEmpty);
  });

  group('a corrupt stored key heals instead of throwing', () {
    for (final (name, stored) in [
      ('not base64', 'definitely not base64 !!'),
      ('too short', base64.encode(List.filled(16, 7))),
      ('too long', base64.encode(List.filled(64, 7))),
      ('empty', ''),
    ]) {
      test(name, () async {
        keychain[_seedKey('c1')] = stored;

        final identity = await ClawIdentityStore().identityFor('c1');

        expect(identity.deviceId, hasLength(64));
        expect(base64.decode(keychain[_seedKey('c1')]!), hasLength(32));
        // Healed, not merely survived: the replacement has to stick, or the
        // app asks for approval again on every launch.
        expect(await ClawIdentityStore().deviceIdFor('c1'), identity.deviceId);
      });
    }

    test('deviceIdFor reports nothing rather than throwing', () async {
      keychain[_seedKey('c1')] = 'definitely not base64 !!';

      expect(await ClawIdentityStore().deviceIdFor('c1'), isNull);
    });
  });

  group('the macOS keychain options', () {
    test('the legacy keychain is selected, not merely described', () {
      // The comment has always said the legacy keychain is used because the
      // data-protection one needs an entitlement a local build cannot have.
      // The line that actually selects it was missing here while it was added
      // to ConnectionStore, so a freshly rebuilt app still failed with
      // errSecMissingEntitlement (-34018) on every read and write.
      expect(
        ClawIdentityStore.macOptions.toMap()['usesDataProtectionKeychain'],
        'false',
      );

      // And the default really is the one that would have broken it, so this
      // is a live constraint rather than a restatement.
      expect(
        const MacOsOptions().toMap()['usesDataProtectionKeychain'],
        'true',
        reason:
            'if the plugin default changes, the comment above the options '
            'needs revisiting rather than silently becoming right',
      );
    });
  });

  group('the seed stays in the Keychain', () {
    test('and nowhere else', () async {
      final store = ClawIdentityStore();
      final identity = await store.identityFor('c1');
      final seed = base64.encode(await identity.extractSeed());

      // The one place it is allowed to be.
      expect(keychain[_seedKey('c1')], seed);
      expect(keychain.keys, [_seedKey('c1')]);
      expect(
        keychain.keys.every((k) => k.startsWith('caduceus.claw.seed.')),
        isTrue,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('and out of every string the store hands back', () async {
      final store = ClawIdentityStore();
      final identity = await store.identityFor('c1');
      final seed = await identity.extractSeed();
      final encodings = [base64.encode(seed), base64Url.encode(seed), '$seed'];

      // Whatever might reasonably be rendered or logged by a caller.
      for (final leak in [
        store.toString(),
        identity.toString(),
        identity.deviceId,
        identity.publicKey,
        (await store.deviceIdFor('c1'))!,
      ]) {
        for (final encoding in encodings) {
          expect(leak, isNot(contains(encoding)));
        }
      }
    });
  });
}
