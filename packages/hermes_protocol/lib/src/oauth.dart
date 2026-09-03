import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// An OAuth 2.0 token response obtained from a Hermes control plane or auth provider.
@immutable
class HermesOAuthToken {
  const HermesOAuthToken({
    required this.accessToken,
    this.tokenType = 'Bearer',
    this.expiresIn,
    this.refreshToken,
    this.scope,
  });

  /// The access token to use when authenticating WebSocket or HTTP requests.
  final String accessToken;

  /// The type of token, typically 'Bearer'.
  final String tokenType;

  /// The lifetime in seconds of the access token, if provided.
  final int? expiresIn;

  /// The refresh token, if provided.
  final String? refreshToken;

  /// The scope of the access token, if provided.
  final String? scope;

  /// Parses a token response from a server JSON payload.
  ///
  /// Tolerates standard RFC 6749 fields (`access_token`) as well as common
  /// variants (`token`, `session_token`).
  factory HermesOAuthToken.fromJson(Map<String, dynamic> json) {
    final raw = json['access_token'] ?? json['token'] ?? json['session_token'];
    if (raw is! String || raw.trim().isEmpty) {
      throw const FormatException(
        'OAuth response does not contain a valid access token.',
      );
    }
    return HermesOAuthToken(
      accessToken: raw.trim(),
      tokenType: json['token_type'] as String? ?? 'Bearer',
      expiresIn: json['expires_in'] is num
          ? (json['expires_in'] as num).toInt()
          : null,
      refreshToken: json['refresh_token'] as String?,
      scope: json['scope'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'token_type': tokenType,
    if (expiresIn != null) 'expires_in': expiresIn,
    if (refreshToken != null) 'refresh_token': refreshToken,
    if (scope != null) 'scope': scope,
  };

  @override
  String toString() =>
      'HermesOAuthToken($tokenType, expires in: ${expiresIn ?? "unknown"}s)';
}

/// Thrown when an OAuth authentication attempt fails.
class HermesOAuthException implements Exception {
  const HermesOAuthException(this.message, {this.statusCode, this.errorType});

  final String message;
  final int? statusCode;
  final String? errorType;

  @override
  String toString() => message;
}

/// Authenticates against Hermes control plane auth gateways using OAuth 2.0
/// Resource Owner Password Credentials Grant (RFC 6749 §4.3).
class HermesOAuthClient {
  HermesOAuthClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// Default candidate token endpoints to try in order.
  static const candidateTokenPaths = <String>[
    '/auth/password-login',
    '/api/auth/oauth/token',
    '/oauth/token',
    '/api/auth/token',
    '/auth/token',
  ];

  /// Exchanges username and password for a [HermesOAuthToken].
  ///
  /// [serverUrl] can be a root URL (`https://agent.example.com:9119`) or a
  /// reverse-proxied subpath (`https://example.com/hermes`).
  ///
  /// Probes candidate OAuth/auth endpoints if [customTokenPath] is not provided.
  Future<HermesOAuthToken> login({
    required String serverUrl,
    required String username,
    required String password,
    String? clientId,
    String? clientSecret,
    String? scope,
    String? customTokenPath,
  }) async {
    final cleanUser = username.trim();
    if (cleanUser.isEmpty || password.isEmpty) {
      throw const HermesOAuthException(
        'Username and password must not be empty.',
      );
    }

    final uri = _parseBaseUri(serverUrl);
    final prefix = _extractPrefix(uri.path);

    final pathsToTry = customTokenPath != null && customTokenPath.isNotEmpty
        ? [
            customTokenPath.startsWith('/')
                ? customTokenPath
                : '/$customTokenPath',
          ]
        : candidateTokenPaths.map((p) => '$prefix$p').toList();

    final formPayload = <String, String>{
      'grant_type': 'password',
      'username': cleanUser,
      'password': password,
      if (clientId != null && clientId.isNotEmpty) 'client_id': clientId,
      if (clientSecret != null && clientSecret.isNotEmpty)
        'client_secret': clientSecret,
      if (scope != null && scope.isNotEmpty) 'scope': scope,
    };

    String? lastError;
    int? lastStatus;

    for (final path in pathsToTry) {
      final tokenUri = uri.replace(path: path, queryParameters: null);
      final isPasswordLogin = path.endsWith('password-login');

      try {
        http.Response response;

        if (isPasswordLogin) {
          // Hermes native web password login endpoint expects JSON body
          response = await _client
              .post(
                tokenUri,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
                body: jsonEncode({
                  'provider': 'basic',
                  'username': cleanUser,
                  'password': password,
                  'next': '',
                }),
              )
              .timeout(timeout);
        } else {
          // Standard RFC 6749 OAuth endpoint: try application/x-www-form-urlencoded
          response = await _client
              .post(
                tokenUri,
                headers: {
                  'Content-Type': 'application/x-www-form-urlencoded',
                  'Accept': 'application/json',
                },
                body: formPayload,
              )
              .timeout(timeout);

          // If the server explicitly rejected the media type, retry with application/json
          if (response.statusCode == 415) {
            response = await _client
                .post(
                  tokenUri,
                  headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                  },
                  body: jsonEncode(formPayload),
                )
                .timeout(timeout);
          }
        }

        if (response.statusCode == 200) {
          // 1. Try parsing JSON body for access token
          try {
            final dynamic decoded = jsonDecode(response.body);
            if (decoded is Map<String, dynamic>) {
              final raw =
                  decoded['access_token'] ??
                  decoded['token'] ??
                  decoded['session_token'];
              if (raw is String && raw.trim().isNotEmpty) {
                return HermesOAuthToken.fromJson(decoded);
              }
            }
          } catch (_) {
            // Body might not be standard JSON token response
          }

          // 2. Check Set-Cookie headers for session access token (__Host-hermes_session_at)
          final cookieHeader = response.headers['set-cookie'];
          if (cookieHeader != null && cookieHeader.isNotEmpty) {
            final at =
                _extractCookieValue(cookieHeader, '__Host-hermes_session_at') ??
                _extractCookieValue(cookieHeader, 'hermes_session_at');
            final rt =
                _extractCookieValue(cookieHeader, '__Host-hermes_session_rt') ??
                _extractCookieValue(cookieHeader, 'hermes_session_rt');

            if (at != null && at.trim().isNotEmpty) {
              return HermesOAuthToken(
                accessToken: at.trim(),
                refreshToken: rt?.trim(),
                tokenType: 'Bearer',
              );
            }
          }
        }

        // If it's a redirect (301, 302, 303, 307, 308), this path is a web route redirecting
        // unauthenticated requests (e.g. to /login). It is not an auth API endpoint; try next path.
        if (response.statusCode >= 300 && response.statusCode < 400) {
          lastStatus = response.statusCode;
          continue;
        }

        // If it's a 404 Not Found or 405 Method Not Allowed, try next path.
        if (response.statusCode == 404 || response.statusCode == 405) {
          lastStatus = response.statusCode;
          continue;
        }

        // 400 Bad Request, 401 Unauthorized, 403 Forbidden etc. - endpoint exists but auth failed
        final parsedError = _extractErrorMessage(
          response.body,
          response.statusCode,
        );
        throw HermesOAuthException(
          parsedError.message,
          statusCode: response.statusCode,
          errorType: parsedError.errorType,
        );
      } on HermesOAuthException {
        rethrow;
      } on TimeoutException {
        throw const HermesOAuthException(
          'Connection timed out while attempting to sign in.',
        );
      } on http.ClientException catch (e) {
        lastError = 'Network error: ${e.message}';
      } catch (e) {
        lastError = '$e';
      }
    }

    throw HermesOAuthException(
      lastError ??
          'Could not find a valid OAuth token endpoint on $serverUrl. '
              'Verify the server URL and that OAuth authentication is enabled.',
      statusCode: lastStatus,
    );
  }

  /// Mints a single-use WebSocket ticket from `/api/auth/ws-ticket` using the [accessToken].
  ///
  /// Required for public/gated Hermes servers where direct `?token=` query params
  /// on `/api/ws` are rejected and a short-lived ticket (`?ticket=`) is needed.
  Future<String> mintWsTicket({
    required String serverUrl,
    required String accessToken,
  }) async {
    final uri = _parseBaseUri(serverUrl);
    final prefix = _extractPrefix(uri.path);
    final ticketUri = uri.replace(
      path: '$prefix/api/auth/ws-ticket',
      queryParameters: null,
    );

    final cleanToken = accessToken.trim().replaceAll('"', '');
    final response = await _client
        .post(
          ticketUri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $cleanToken',
            'Cookie': '__Host-hermes_session_at="$cleanToken"',
          },
          body: jsonEncode({}),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final dynamic data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['ticket'] is String) {
        return data['ticket'] as String;
      }
    }

    final parsedError = _extractErrorMessage(
      response.body,
      response.statusCode,
    );
    throw HermesOAuthException(
      'Failed to mint WebSocket ticket: ${parsedError.message}',
      statusCode: response.statusCode,
    );
  }

  static String? _extractCookieValue(String cookies, String name) {
    final pattern = RegExp('$name="?([^";]+)"?');
    final match = pattern.firstMatch(cookies);
    final val = match?.group(1);
    if (val == null) return null;
    return val.replaceAll('"', '').trim();
  }

  static Uri _parseBaseUri(String text) {
    var raw = text.trim();
    if (raw.isEmpty) {
      throw const HermesOAuthException('Server URL must not be empty.');
    }
    if (!raw.contains('://')) {
      final isLocal =
          raw.startsWith('localhost') ||
          raw.startsWith('127.0.0.1') ||
          raw.startsWith('0.0.0.0');
      raw = '${isLocal ? "http" : "https"}://$raw';
    }
    return Uri.parse(raw);
  }

  static String _extractPrefix(String rawPath) {
    var p = rawPath.trim();
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    if (p.isEmpty || p == '/') return '';
    return p.startsWith('/') ? p : '/$p';
  }

  static ({String message, String? errorType}) _extractErrorMessage(
    String body,
    int statusCode,
  ) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error']?.toString();
        final desc =
            decoded['error_description']?.toString() ??
            decoded['detail']?.toString() ??
            decoded['message']?.toString();

        if (desc != null && desc.trim().isNotEmpty) {
          return (message: desc.trim(), errorType: error);
        }
        if (error != null && error.trim().isNotEmpty) {
          return (message: error.trim(), errorType: error);
        }
      }
    } catch (_) {
      // Body was not JSON.
    }

    if (statusCode == 401) {
      return (
        message: 'Invalid username or password.',
        errorType: 'unauthorized',
      );
    }
    if (statusCode == 403) {
      return (
        message: 'Access forbidden for this user.',
        errorType: 'forbidden',
      );
    }
    return (
      message: 'Authentication failed with HTTP $statusCode.',
      errorType: 'http_$statusCode',
    );
  }
}
