/// Logging in to a server the app already lists.
///
/// The bug these exist for, reported from macOS: the connect screen showed two
/// saved servers and an empty form below them, and tapping a row did nothing
/// visible. Two faults, and the first hid the second.
///
/// `MacOsOptions` was constructed without `usesDataProtectionKeychain: false`,
/// so every Keychain read failed with `errSecMissingEntitlement` on a
/// locally-signed build. The server *list* lives in SharedPreferences and was
/// unaffected, which is why the screen looked fine and only login broke.
///
/// And the screen treated a missing token as `setState(() => _adding = true)`
/// with no message and no prefill — so a refusing Keychain, a server saved
/// without a token, and a tap that missed all looked the same.
library;

import 'package:caduceus/connection_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Keychain that refuses every read, the way macOS does without the
/// entitlement.
class _RefusingKeychain extends FlutterSecureStorage {
  const _RefusingKeychain(this.error);

  final Object error;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw error;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('reading a saved token', () {
    test('a stored token comes back with no reason attached', () async {
      final store = ConnectionStore();
      final saved = await store.save(
        label: 'nas',
        url: 'wss://example.test',
        token: 'secret-token',
        backendId: SavedConnection.openclaw,
      );

      final lookup = await store.readToken(saved.id);
      expect(lookup.token, 'secret-token');
      expect(
        lookup.reason,
        isNull,
        reason: 'a reason means something went wrong, and nothing did',
      );
    });

    test('a server with no token reports null, not an error', () async {
      final lookup = await ConnectionStore().readToken('never-saved');
      expect(lookup.token, isNull);
      expect(
        lookup.reason,
        isNull,
        reason:
            '"never saved" and "the Keychain refused" are different '
            'problems and the screen says different things about them',
      );
    });

    test('a refusing Keychain reports why, and does not throw', () async {
      // The whole failure mode: this used to escape as an unhandled async
      // error out of the launch path, before any server was listed.
      final store = ConnectionStore(
        secure: const _RefusingKeychain(
          'PlatformException(Unexpected security result code, '
          'Code: -34018, Message: A required entitlement is missing)',
        ),
      );

      final lookup = await store.readToken('c1');
      expect(lookup.token, isNull);
      expect(lookup.reason, isNotNull);
      expect(
        lookup.reason,
        contains('-34018'),
        reason: 'the raw code is what a user can search for',
      );
      expect(
        lookup.reason,
        contains('entitlement'),
        reason: 'and the plain words are what tells them it is not their fault',
      );
    });

    test('a locked Keychain says so in its own terms', () async {
      final store = ConnectionStore(
        secure: const _RefusingKeychain(
          'PlatformException(Code: -25308, errSecInteractionNotAllowed)',
        ),
      );
      final lookup = await store.readToken('c1');
      expect(lookup.reason, contains('locked'));
    });

    test(
      'an unrecognised failure is passed through rather than swallowed',
      () async {
        final store = ConnectionStore(
          secure: const _RefusingKeychain('something nobody predicted'),
        );
        final lookup = await store.readToken('c1');
        expect(lookup.reason, contains('something nobody predicted'));
      },
    );

    test(
      'tokenFor still answers null for callers that only want the token',
      () async {
        final store = ConnectionStore(secure: const _RefusingKeychain('boom'));
        await expectLater(store.tokenFor('c1'), completion(isNull));
      },
    );
  });

  group('the macOS keychain options', () {
    test('the legacy keychain is selected, not merely described', () {
      // The comment above these options always said the legacy keychain was
      // used because the data-protection one needs an entitlement a local
      // build cannot have. The line that actually selects it was missing for
      // long enough to ship, and the failure was invisible on every other
      // platform.
      // Asserted against the options the store actually constructs. Building
      // an equivalent MacOsOptions here instead would pass with the fix
      // deleted, which is the difference between a constraint and a
      // restatement — checked by deleting it.
      expect(
        ConnectionStore.macKeychainOptions
            .toMap()['usesDataProtectionKeychain'],
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

  group('what the screen knows without the token', () {
    test('everything except the secret is already on hand', () async {
      // The form was blank when all of this was known — which is what made
      // the bug feel like a dead button rather than a missing credential.
      final store = ConnectionStore();
      final saved = await store.save(
        label: 'nas',
        url: 'wss://fnos.example.test',
        token: 't',
        backendId: SavedConnection.openclaw,
      );

      final listed = (await store.list()).single;
      expect(listed.id, saved.id);
      expect(listed.label, 'nas');
      expect(listed.url, 'wss://fnos.example.test');
      expect(
        listed.backendId,
        SavedConnection.openclaw,
        reason: 'tapping an OpenClaw row must not open a Hermes form',
      );
      expect(listed.displayLabel, 'nas');
    });
  });
}
