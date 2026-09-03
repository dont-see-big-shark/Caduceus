import 'dart:convert';

import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('HermesOAuthToken', () {
    test('parses standard RFC 6749 response', () {
      final token = HermesOAuthToken.fromJson({
        'access_token': 'test-access-token-123',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'refresh_token': 'test-refresh-token',
        'scope': 'agent.read agent.write',
      });

      expect(token.accessToken, 'test-access-token-123');
      expect(token.tokenType, 'Bearer');
      expect(token.expiresIn, 3600);
      expect(token.refreshToken, 'test-refresh-token');
      expect(token.scope, 'agent.read agent.write');
    });

    test('tolerates alternative token fields (token, session_token)', () {
      final t1 = HermesOAuthToken.fromJson({'token': 'tok-abc'});
      expect(t1.accessToken, 'tok-abc');

      final t2 = HermesOAuthToken.fromJson({'session_token': 'session-xyz'});
      expect(t2.accessToken, 'session-xyz');
    });

    test('throws on missing or empty token', () {
      expect(
        () => HermesOAuthToken.fromJson({}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => HermesOAuthToken.fromJson({'access_token': '   '}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HermesOAuthClient', () {
    test(
      'authenticates via native /auth/password-login and extracts cookie',
      () async {
        final mock = MockClient((request) async {
          expect(request.url.path, '/auth/password-login');
          expect(request.headers['content-type'], contains('application/json'));
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['provider'], 'basic');
          expect(body['username'], 'jaden');
          expect(body['password'], 'qwe123');

          return http.Response(
            jsonEncode({'ok': true, 'next': '/'}),
            200,
            headers: {
              'content-type': 'application/json',
              'set-cookie':
                  '__Host-hermes_session_at="jwt-session-access-token"; HttpOnly; Path=/, '
                  '__Host-hermes_session_rt="jwt-session-refresh-token"; HttpOnly; Path=/',
            },
          );
        });

        final client = HermesOAuthClient(client: mock);
        final token = await client.login(
          serverUrl: 'https://home.zzz2zzz.icu:9120',
          username: 'jaden',
          password: 'qwe123',
        );

        expect(token.accessToken, 'jwt-session-access-token');
        expect(token.refreshToken, 'jwt-session-refresh-token');
      },
    );

    test(
      'skips HTTP 302 redirects and falls back to matching endpoint',
      () async {
        final visited = <String>[];
        final mock = MockClient((request) async {
          visited.add(request.url.path);
          if (request.url.path == '/auth/password-login') {
            // Simulate 302 redirect to /login
            return http.Response('', 302, headers: {'location': '/login'});
          }
          if (request.url.path == '/api/auth/oauth/token') {
            return http.Response('Not Found', 404);
          }
          if (request.url.path == '/oauth/token') {
            return http.Response(
              jsonEncode({'access_token': 'oauth-fallback-token'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final client = HermesOAuthClient(client: mock);
        final token = await client.login(
          serverUrl: 'https://hermes.example.com',
          username: 'admin',
          password: 'secret',
        );

        expect(
          visited,
          containsAllInOrder([
            '/auth/password-login',
            '/api/auth/oauth/token',
            '/oauth/token',
          ]),
        );
        expect(token.accessToken, 'oauth-fallback-token');
      },
    );

    test('respects proxy mount path prefix', () async {
      late String actualPath;
      final mock = MockClient((request) async {
        actualPath = request.url.path;
        return http.Response(
          jsonEncode({'access_token': 'proxied-token'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = HermesOAuthClient(client: mock);
      await client.login(
        serverUrl: 'https://proxy.example.com:8443/agents/hermes-box/',
        username: 'user1',
        password: 'pwd',
      );

      expect(actualPath, '/agents/hermes-box/auth/password-login');
    });

    test('mints ws ticket via /api/auth/ws-ticket', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/api/auth/ws-ticket');
        expect(request.headers['authorization'], 'Bearer valid-jwt-token');
        return http.Response(
          jsonEncode({'ticket': 'single-use-ticket-xyz', 'ttl_seconds': 30}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = HermesOAuthClient(client: mock);
      final ticket = await client.mintWsTicket(
        serverUrl: 'https://home.zzz2zzz.icu:9120',
        accessToken: 'valid-jwt-token',
      );

      expect(ticket, 'single-use-ticket-xyz');
    });

    test(
      'throws HermesOAuthException on 401 with detailed server message',
      () async {
        final mock = MockClient((request) async {
          return http.Response(
            jsonEncode({'detail': 'Invalid credentials'}),
            401,
            headers: {'content-type': 'application/json'},
          );
        });

        final client = HermesOAuthClient(client: mock);
        expect(
          () => client.login(
            serverUrl: 'https://hermes.example.com',
            username: 'wronguser',
            password: 'badpassword',
          ),
          throwsA(
            isA<HermesOAuthException>()
                .having((e) => e.message, 'message', 'Invalid credentials')
                .having((e) => e.statusCode, 'statusCode', 401),
          ),
        );
      },
    );

    test(
      'throws validation error when username or password is empty',
      () async {
        final client = HermesOAuthClient();
        expect(
          () => client.login(
            serverUrl: 'https://test',
            username: '',
            password: 'pwd',
          ),
          throwsA(isA<HermesOAuthException>()),
        );
        expect(
          () => client.login(
            serverUrl: 'https://test',
            username: 'usr',
            password: '',
          ),
          throwsA(isA<HermesOAuthException>()),
        );
      },
    );
  });
}
