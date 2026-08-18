import 'package:caduceus/connection_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyValueKeychain extends FlutterSecureStorage {
  const _EmptyValueKeychain();
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  test(
    'an empty Keychain value reads as no token, not as an empty one',
    () async {
      final store = ConnectionStore(secure: const _EmptyValueKeychain());
      final lookup = await store.readToken('any');
      expect(lookup.token, isNull);
    },
  );
}
