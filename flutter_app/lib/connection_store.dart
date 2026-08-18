import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backends/claw_identity.dart';

/// A saved server, minus its credential.
@immutable
class SavedConnection {
  const SavedConnection({
    required this.id,
    required this.label,
    required this.url,
    this.backendId = hermes,
    this.requestAdmin = false,
    this.profile = 'default',
  });

  /// Backend ids, matching [AgentBackend.id].
  static const hermes = 'hermes';
  static const openclaw = 'openclaw';

  factory SavedConnection.fromJson(Map<String, dynamic> json) =>
      SavedConnection(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        url: json['url'] as String? ?? '',
        // Absent means a record written before the field existed. Those are
        // not all Hermes — this app connected to an OpenClaw gateway before
        // the picker did — so the URL decides, and only for those records.
        // Migrating on read rather than rewriting the store keeps a downgrade
        // harmless: an older build reading a newer record ignores the field it
        // does not know.
        backendId:
            json['backend'] as String? ?? backendForUrl(json['url'] as String?),
        requestAdmin: json['requestAdmin'] == true,
        profile: json['profile'] as String? ?? 'default',
      );

  final String id;
  final String label;
  final String url;

  /// Which agent is at the other end. See [AgentBackend.id].
  final String backendId;

  /// Whether this connection asks the gateway for `operator.admin`.
  ///
  /// Least privilege by default: a chat client needs read, write and
  /// approvals, nothing more. `operator.admin` satisfies every other scope
  /// and lets the client rewrite gateway configuration and write memory
  /// (`agents.files.set`) — which the shared knowledge base needs. Opt-in via
  /// the connect screen's *Request administrator* control; it takes effect on
  /// the next connection.
  final bool requestAdmin;

  /// The Hermes profile whose sessions this connection displays.
  final String profile;

  bool get isOpenClaw => backendId == openclaw;

  /// Which backend a URL with no recorded one probably belongs to.
  ///
  /// A guess, and the only honest one available: Hermes is reached over HTTP —
  /// its own connect field asks for `https://host:port/path` and a URL with no
  /// scheme is read as `https://` — while an OpenClaw gateway is a WebSocket
  /// at the root. `HermesEndpoint.parse` does accept `wss://`, so a Hermes
  /// server saved that way is guessed wrong.
  ///
  /// Which is why the row says which backend it will use: a wrong guess is
  /// then visible before it is pressed rather than after, and reconnecting
  /// once records the answer for good.
  static String backendForUrl(String? url) {
    final scheme = Uri.tryParse(url?.trim() ?? '')?.scheme.toLowerCase();
    return scheme == 'ws' || scheme == 'wss' ? openclaw : hermes;
  }

  /// What to call this backend on screen.
  String get backendLabel => switch (backendId) {
    openclaw => 'OpenClaw',
    hermes => 'Hermes',
    _ => backendId,
  };

  SavedConnection copyWith({bool? requestAdmin, String? profile}) =>
      SavedConnection(
        id: id,
        label: label,
        url: url,
        backendId: backendId,
        requestAdmin: requestAdmin ?? this.requestAdmin,
        profile: profile ?? this.profile,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'url': url,
    'backend': backendId,
    if (requestAdmin) 'requestAdmin': true,
    if (profile.trim().isNotEmpty && profile.trim() != 'default')
      'profile': profile.trim(),
  };

  String get displayLabel {
    if (label.trim().isNotEmpty) return label.trim();
    final uri = Uri.tryParse(url);
    return uri == null ? url : '${uri.host}:${uri.port}';
  }
}

/// Persists connections across launches.
///
/// The token is the whole security boundary — it grants `prompt.submit`,
/// `cli.exec` and `approval.respond` on the user's machine. So it lives in the
/// macOS Keychain and nowhere else; only the non-secret URL and label go to
/// SharedPreferences, which is a plaintext plist.
class ConnectionStore {
  ConnectionStore({FlutterSecureStorage? secure, this.prefs})
    : _secure =
          secure ?? const FlutterSecureStorage(mOptions: macKeychainOptions);

  /// The data-protection keychain (the plugin default) requires a
  /// `keychain-access-groups` entitlement, which only resolves under a real
  /// signing team — a locally-signed build fails every read and write with
  /// `errSecMissingEntitlement` (-34018). The legacy file-based keychain needs
  /// no entitlement and is still per-app and encrypted at rest.
  ///
  /// **`usesDataProtectionKeychain: false` is the line that does that**, and
  /// it was missing: this comment described the intent while the options set
  /// only `accessibility`, leaving the plugin's `true` default in place. The
  /// symptom is precise and misleading — the server list survives a restart
  /// because it lives in SharedPreferences, and only the token read fails, so
  /// the app shows saved servers it cannot log in to.
  ///
  /// A signed distribution build should flip this back to the data-protection
  /// keychain and add the entitlement.
  @visibleForTesting
  static const macKeychainOptions = MacOsOptions(
    accessibility: KeychainAccessibility.first_unlock,
    usesDataProtectionKeychain: false,
  );

  static const _listKey = 'connections.v1';
  static const _lastKey = 'connections.last';
  static const _tokenPrefix = 'caduceus.token.';
  static const _openTabsKey = 'connections.openTabs';
  static const _activeTabKey = 'connections.activeTab';

  final FlutterSecureStorage _secure;
  SharedPreferences? prefs;

  Future<SharedPreferences> get _p async =>
      prefs ??= await SharedPreferences.getInstance();

  Future<List<SavedConnection>> list() async {
    final raw = (await _p).getString(_listKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(SavedConnection.fromJson)
          .toList();
    } on FormatException {
      return const [];
    }
  }

  /// The saved token, and why there isn't one when there isn't.
  ///
  /// Three outcomes, and a caller that cannot tell them apart shows the user
  /// a blank form for all three. `null` token with a `null` reason means the
  /// server was saved without one; a reason means the Keychain refused, which
  /// is a platform problem the user can act on and a very different message.
  ///
  /// Never throws. A Keychain failure on one server must not take down the
  /// launch path that reads it, which is what an escaping PlatformException
  /// did — it aborted the whole bootstrap before any server was listed.
  Future<({String? token, String? reason})> readToken(String id) async {
    try {
      final value = await _secure.read(key: '$_tokenPrefix$id');
      // An empty Keychain value is the same as none: a connection built on it
      // reaches the gateway with no credential at all, which on OpenClaw
      // shows up as `unauthorized: gateway token missing` after a round trip.
      // Normalise it here so every caller goes through the re-enter-token
      // path instead of silently connecting with auth=none.
      if (value == null || value.isEmpty) {
        return (token: null, reason: null);
      }
      return (token: value, reason: null);
    } catch (e) {
      return (token: null, reason: _keychainReason(e));
    }
  }

  /// A Keychain failure in words a person can act on.
  ///
  /// `errSecMissingEntitlement` is the one this app actually hits, and its
  /// raw form (`-34018`) tells the user nothing at all.
  static String _keychainReason(Object error) {
    final text = '$error';
    if (text.contains('-34018') || text.contains('MissingEntitlement')) {
      return 'macOS refused the Keychain (-34018). This build is not signed '
          'with a team that has the keychain entitlement.';
    }
    if (text.contains('-25308') || text.contains('InteractionNotAllowed')) {
      return 'The Keychain is locked. Unlock it and try again.';
    }
    return 'The Keychain could not be read: $text';
  }

  Future<String?> tokenFor(String id) async => (await readToken(id)).token;

  /// Stores (or updates) a connection. [token] goes to the Keychain.
  Future<SavedConnection> save({
    String? id,
    required String label,
    required String url,
    required String token,
    String backendId = SavedConnection.hermes,
    bool requestAdmin = false,
    String profile = 'default',
  }) async {
    final connections = List<SavedConnection>.from(await list());
    // Identify by URL so reconnecting to a known server updates rather than
    // accumulating duplicates.
    final resolvedId =
        id ??
        connections.where((c) => c.url == url).map((c) => c.id).followedBy([
          DateTime.now().microsecondsSinceEpoch.toString(),
        ]).first;

    final entry = SavedConnection(
      id: resolvedId,
      label: label,
      url: url,
      backendId: backendId,
      requestAdmin: requestAdmin,
      profile: profile.trim().isEmpty ? 'default' : profile.trim(),
    );
    connections.removeWhere((c) => c.id == resolvedId);
    connections.insert(0, entry);

    await (await _p).setString(
      _listKey,
      jsonEncode(connections.map((c) => c.toJson()).toList()),
    );
    await _secure.write(key: '$_tokenPrefix$resolvedId', value: token);
    return entry;
  }

  Future<void> remove(String id) async {
    final connections = await list();
    await (await _p).setString(
      _listKey,
      jsonEncode(
        connections.where((c) => c.id != id).map((c) => c.toJson()).toList(),
      ),
    );
    // Delete the credentials too — leaving an orphan in the Keychain outlives
    // any UI that could remove it. Both of them: the gateway token, and the
    // OpenClaw device key, which is a *private key* and so the worse orphan of
    // the two. Here rather than at the call site because "remember to also
    // forget the key" is precisely the instruction that gets forgotten.
    await _secure.delete(key: '$_tokenPrefix$id');
    await ClawIdentityStore(secure: _secure).forget(id);
  }

  /// Which servers had a tab open, and which was in front.
  ///
  /// Replaces [lastUsedId] as the thing consulted at launch. The two would
  /// otherwise both fire — the shell restoring its tabs *and* the connect
  /// screen reconnecting the last one — and open the same server twice, which
  /// on OpenClaw is a second device pairing.
  ///
  /// [lastUsedId] is kept because it is still the honest answer for a launch
  /// with no tabs recorded: someone upgrading from a build that had no tabs
  /// should land where they left off, not at a form.
  Future<({List<String> ids, int active})> openTabs() async {
    final prefs = await _p;
    return (
      ids: prefs.getStringList(_openTabsKey) ?? const <String>[],
      active: prefs.getInt(_activeTabKey) ?? 0,
    );
  }

  Future<void> setOpenTabs(List<String> ids, int active) async {
    final prefs = await _p;
    await prefs.setStringList(_openTabsKey, ids);
    await prefs.setInt(_activeTabKey, active);
  }

  Future<String?> lastUsedId() async => (await _p).getString(_lastKey);

  Future<void> setLastUsed(String id) async =>
      (await _p).setString(_lastKey, id);

  Future<void> clearLastUsed() async => (await _p).remove(_lastKey);
}
