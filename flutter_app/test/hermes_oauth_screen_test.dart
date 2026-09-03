import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:caduceus/backend_factory.dart';
import 'package:caduceus/connect_screen.dart';
import 'package:caduceus/connection_store.dart';
import 'package:caduceus/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBackend implements AgentBackend {
  _FakeBackend(this.id);

  @override
  final String id;
  var connects = 0;
  var disposes = 0;

  @override
  String get displayName => id;

  @override
  Future<void> connect() async => connects++;

  @override
  Future<void> dispose() async => disposes++;

  @override
  AgentConnection get connectionState => AgentConnection.disconnected;

  @override
  Stream<AgentConnection> get connection => const Stream.empty();

  @override
  Stream<AgentSession> get sessionUpdates => const Stream.empty();

  @override
  bool supports(Capability capability) => false;

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget buildScreen({
    HermesOAuthClient? oauthClient,
    Future<BuiltBackend> Function(SavedConnection, String)? backendBuilder,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ConnectScreen(
        autoReconnect: false,
        oauthClient: oauthClient,
        backendBuilder: backendBuilder,
      ),
    );
  }

  testWidgets(
    'Hermes connect form defaults to Token mode and shows auth mode toggle',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Verify auth mode segmented buttons exist
      expect(find.text('Token'), findsOneWidget);
      expect(find.text('Account (OAuth)'), findsOneWidget);

      // In Token mode, SESSION TOKEN eyebrow is shown, username and password are not
      expect(find.text('SESSION TOKEN'), findsOneWidget);
      expect(find.text('USERNAME'), findsNothing);
      expect(find.text('PASSWORD'), findsNothing);
    },
  );

  testWidgets('Tapping Account (OAuth) shows Username and Password fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // Tap on Account (OAuth)
    await tester.tap(find.text('Account (OAuth)'));
    await tester.pumpAndSettle();

    // Now USERNAME and PASSWORD eyebrows are visible, SESSION TOKEN is hidden
    expect(find.text('USERNAME'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('SESSION TOKEN'), findsNothing);
  });

  testWidgets(
    'Selecting OpenClaw hides the Hermes OAuth mode segmented selector',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Switch to OpenClaw
      await tester.tap(find.text('OpenClaw'));
      await tester.pumpAndSettle();

      // OpenClaw shows GATEWAY TOKEN and no OAuth toggle
      expect(find.text('GATEWAY TOKEN'), findsOneWidget);
      expect(find.text('Account (OAuth)'), findsNothing);
    },
  );

  testWidgets(
    'Submitting with empty username/password in OAuth mode shows validation error',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Switch to OAuth
      await tester.tap(find.text('Account (OAuth)'));
      await tester.pumpAndSettle();

      // Enter server URL only
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(1), 'https://hermes.test:9119');
      await tester.pumpAndSettle();

      // Tap Connect
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Notice with error message should be displayed
      expect(
        find.text('Please enter both username and password.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Failed OAuth login displays specific server error message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final mockHttp = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Invalid username or credentials provided.',
        }),
        401,
        headers: {'content-type': 'application/json'},
      );
    });

    final oauthClient = HermesOAuthClient(client: mockHttp);
    await tester.pumpWidget(buildScreen(oauthClient: oauthClient));
    await tester.pumpAndSettle();

    // Switch to OAuth
    await tester.tap(find.text('Account (OAuth)'));
    await tester.pumpAndSettle();

    // Enter URL, username, password
    final textFields = find.byType(TextField);
    // 0: label (optional), 1: server URL, 2: username, 3: password
    await tester.enterText(textFields.at(1), 'https://hermes.test:9119');
    await tester.enterText(textFields.at(2), 'admin');
    await tester.enterText(textFields.at(3), 'wrong_password');
    await tester.pumpAndSettle();

    // Tap Connect
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(
      find.text('Invalid username or credentials provided.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Successful OAuth login exchanges credentials for access token and connects',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var loginCalled = false;
      final mockHttp = MockClient((request) async {
        loginCalled = true;
        if (request.headers['content-type']?.contains('json') ?? false) {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          expect(data['username'], 'nous_user');
          expect(data['password'], 'valid_pass_123');
        } else {
          expect(request.bodyFields['username'], 'nous_user');
          expect(request.bodyFields['password'], 'valid_pass_123');
        }
        return http.Response(
          jsonEncode({
            'access_token': 'oauth-session-token-999',
            'token_type': 'bearer',
            'expires_in': 3600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final fakeBackend = _FakeBackend('hermes');
      final oauthClient = HermesOAuthClient(client: mockHttp);
      await tester.pumpWidget(
        buildScreen(
          oauthClient: oauthClient,
          backendBuilder: (conn, tok) async {
            expect(tok, 'oauth-session-token-999');
            return BuiltBackend(backend: fakeBackend);
          },
        ),
      );
      await tester.pumpAndSettle();

      // Switch to OAuth
      await tester.tap(find.text('Account (OAuth)'));
      await tester.pumpAndSettle();

      // Enter credentials
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(1), 'https://hermes.test:9119');
      await tester.enterText(textFields.at(2), 'nous_user');
      await tester.enterText(textFields.at(3), 'valid_pass_123');
      await tester.pumpAndSettle();

      // Tap Connect
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(loginCalled, isTrue);
      expect(fakeBackend.connects, 1);
    },
  );

  testWidgets(
    'Hermes web login via /auth/password-login extracts cookie token and connects',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final mockHttp = MockClient((request) async {
        expect(request.url.path, '/auth/password-login');
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        expect(data['username'], 'jaden');
        expect(data['password'], 'qwe123');
        return http.Response(
          jsonEncode({'ok': true, 'next': '/'}),
          200,
          headers: {
            'content-type': 'application/json',
            'set-cookie':
                '__Host-hermes_session_at="cookie-extracted-token-abc"; Path=/',
          },
        );
      });

      final fakeBackend = _FakeBackend('hermes');
      final oauthClient = HermesOAuthClient(client: mockHttp);
      await tester.pumpWidget(
        buildScreen(
          oauthClient: oauthClient,
          backendBuilder: (conn, tok) async {
            expect(tok, 'cookie-extracted-token-abc');
            expect(conn.authMode, 'oauth');
            return BuiltBackend(backend: fakeBackend);
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Account (OAuth)'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(1), 'https://home.zzz2zzz.icu:9120');
      await tester.enterText(textFields.at(2), 'jaden');
      await tester.enterText(textFields.at(3), 'qwe123');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(fakeBackend.connects, 1);
    },
  );
}
