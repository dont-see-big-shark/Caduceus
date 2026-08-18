import 'package:meta/meta.dart';

/// How a client authenticates to the Hermes control plane.
///
/// Measured against v0.19.1 (`_ws_auth_reason` in `hermes_cli/web_server.py`),
/// not taken from documentation — the published guidance describes older builds.
enum GatewayAuthMode {
  /// Server bound to loopback with no auth provider. Credential is
  /// `?token=<session token>`, compared in constant time.
  ///
  /// This is the mode Caduceus targets by default: reaching the machine over
  /// SSH or Tailscale leaves Hermes bound to loopback, so this simple path
  /// applies and no ticket dance is needed.
  loopbackToken,

  /// Server bound publicly. The legacy `?token=` is *unconditionally rejected*;
  /// the credential is a single-use `?ticket=` with a 30 second TTL, minted
  /// through the dashboard auth layer and re-minted on every reconnect.
  gatedTicket,
}

/// Where a Hermes control plane lives and how to authenticate to it.
@immutable
class HermesEndpoint {
  const HermesEndpoint({
    required this.host,
    required this.port,
    required this.credential,
    this.authMode = GatewayAuthMode.loopbackToken,
    this.secure = false,
    this.pathPrefix = '',
  });

  /// The default shape: a tunnel (SSH / Tailscale) forwarding the gateway to a
  /// local port, so the server still considers itself loopback-bound.
  factory HermesEndpoint.tunnelled({
    required String token,
    int port = 9119,
    String host = '127.0.0.1',
  }) =>
      HermesEndpoint(host: host, port: port, credential: token);

  /// Parses the URL a user actually has in hand, e.g. what a reverse proxy or
  /// tunnel service hands out:
  ///
  ///     https://example.com:30190/ppc418zqxi5zop92xdsmf2to
  ///
  /// Everything after the authority is kept as [pathPrefix] and prepended to
  /// every route, because a proxy that mounts Hermes under a subpath expects
  /// `/<prefix>/api/ws`, not `/api/ws`.
  factory HermesEndpoint.parse(String url, {required String credential}) {
    var text = url.trim();
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.parse(text);
    final secure = uri.scheme == 'https' || uri.scheme == 'wss';
    return HermesEndpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : (secure ? 443 : 80),
      credential: credential,
      secure: secure,
      pathPrefix: uri.path,
    );
  }

  final String host;
  final int port;

  /// Mount point when Hermes sits behind a reverse proxy under a subpath.
  /// Empty when it is served at the root.
  final String pathPrefix;

  /// Session token in [GatewayAuthMode.loopbackToken], single-use ticket in
  /// [GatewayAuthMode.gatedTicket].
  final String credential;

  final GatewayAuthMode authMode;
  final bool secure;

  String get _wsScheme => secure ? 'wss' : 'ws';
  String get _httpScheme => secure ? 'https' : 'http';

  /// Normalised prefix: leading slash, no trailing slash, empty when absent.
  String get _prefix {
    var p = pathPrefix.trim();
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    if (p.isEmpty || p == '/') return '';
    return p.startsWith('/') ? p : '/$p';
  }

  /// Builds a route under the proxy mount point.
  String routePath(String route) => '$_prefix$route';

  /// The control-plane WebSocket URL, with the credential as the query
  /// parameter the server expects for this mode.
  Uri get gatewayWsUri =>
      Uri.parse('$_wsScheme://$host:$port${routePath('/api/ws')}').replace(
        queryParameters: {
          switch (authMode) {
            GatewayAuthMode.loopbackToken => 'token',
            GatewayAuthMode.gatedTicket => 'ticket',
          }: credential,
        },
      );

  /// Unauthenticated on a loopback bind. The only way to tell the three
  /// WebSocket rejection causes apart — see [GatewayDiagnostics].
  Uri get statusUri =>
      Uri.parse('$_httpScheme://$host:$port${routePath('/api/status')}');

  /// File download URL for managed files and image attachments on the gateway.
  Uri fileDownloadUri(String path) {
    var p = path.trim();
    if (p.startsWith('@image:')) {
      p = p.substring('@image:'.length).trim();
    } else if (p.startsWith('@file:')) {
      p = p.substring('@file:'.length).trim();
    }
    if (p.startsWith('file://')) {
      p = p.substring('file://'.length);
    }
    return Uri.parse(
      '$_httpScheme://$host:$port${routePath('/api/files/download')}',
    ).replace(
      queryParameters: {
        'path': p,
        switch (authMode) {
          GatewayAuthMode.loopbackToken => 'token',
          GatewayAuthMode.gatedTicket => 'ticket',
        }: credential,
      },
    );
  }

  /// A ticket is single-use with a 30 second TTL, so it cannot be reused across
  /// reconnects. Callers must mint a fresh one before each attempt.
  bool get credentialIsSingleUse => authMode == GatewayAuthMode.gatedTicket;

  HermesEndpoint withCredential(String credential) => HermesEndpoint(
        host: host,
        port: port,
        credential: credential,
        authMode: authMode,
        secure: secure,
        pathPrefix: pathPrefix,
      );

  /// Never includes the credential — this is safe to log.
  @override
  String toString() =>
      'HermesEndpoint($_wsScheme://$host:$port$_prefix, ${authMode.name})';

  @override
  bool operator ==(Object other) =>
      other is HermesEndpoint &&
      other.host == host &&
      other.port == port &&
      other.credential == credential &&
      other.authMode == authMode &&
      other.secure == secure &&
      other.pathPrefix == pathPrefix;

  @override
  int get hashCode =>
      Object.hash(host, port, credential, authMode, secure, pathPrefix);
}
