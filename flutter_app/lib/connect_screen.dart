import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes_protocol/hermes_protocol.dart';
import 'package:openclaw_protocol/openclaw_protocol.dart';

import 'backends/claw_backend.dart';
import 'backends/claw_identity.dart';
import 'backends/hermes_backend.dart';
import 'connection_store.dart';
import 'design/components.dart';
import 'design/glass.dart';
import 'design/press.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'l10n/app_localizations.dart';
import 'agent_tabs.dart';
import 'startup_presets.dart';
import 'workspace.dart';
import 'workspace_screen.dart';

/// Pick a saved server, or add one.
///
/// Connects the backend itself and hands the live result to whoever asked.
/// It has to be this way round: the OpenClaw pairing gate is part of
/// connecting, and this is the screen that shows it — so a caller cannot just
/// take the credentials and connect elsewhere.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    this.onConnected,
    this.asTab = false,
    this.autoReconnect = true,
    this.alreadyOpen = const {},
    this.onFocusExisting,
    super.key,
  });

  /// Connection ids that already have a tab.
  ///
  /// Shown as open rather than offered again: reconnecting one would be a
  /// second socket to a server this app is already talking to, and on
  /// OpenClaw a second device pairing needing a second human approval.
  final Set<String> alreadyOpen;

  /// Called instead of connecting when an already-open server is tapped.
  ///
  /// Tapping it should do the obvious thing — go to that agent — rather than
  /// be inert. The shell focuses the tab and closes this screen.
  final void Function(String connectionId)? onFocusExisting;

  /// Reconnect to the last-used server on open.
  ///
  /// False when the shell hosts this screen: the shell has already decided
  /// which tabs to reopen, and a second mechanism doing the same would open
  /// one server twice — on OpenClaw, a second device pairing.
  final bool autoReconnect;

  /// Called with the live agent instead of pushing a workspace.
  ///
  /// Used when this screen *is* the app — nothing open yet — so the shell can
  /// take the first tab without a navigator round trip.
  final void Function(ConnectedAgent)? onConnected;

  /// Pop with the live agent rather than pushing a workspace.
  ///
  /// Used when the shell pushed this screen to add a second agent. The two
  /// modes exist because the same screen is both the app's front door and its
  /// "new tab" sheet, and only the caller knows which.
  final bool asTab;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _store = ConnectionStore();
  final _url = TextEditingController();
  final _label = TextEditingController();
  final _token = TextEditingController();

  List<SavedConnection> _saved = const [];
  bool _busy = false;

  /// 不做页面级 loading — the Connect button is the progress container, so it
  /// needs to know which of the three states it is in rather than a bare
  /// "busy" flag. A saved-server row being tapped drives it too: that is the
  /// same act of connecting, started from a different control.
  Morph _morph = Morph.idle;
  bool _adding = false;
  bool _bootstrapped = false;

  /// Which agent the add-form is describing. Hermes first because it is what
  /// every existing saved server is.
  String _backendId = SavedConnection.hermes;

  /// Whether a *new* OpenClaw connection asks for operator.admin.
  bool _requestAdmin = false;

  /// Which connect entry is showing. Manual is the only implemented path —
  /// the Hermes gateway has no pairing or discovery API (DESIGN.md states
  /// so), so QR / 6-digit / mDNS are the design's mocks, labelled 示例.
  _ConnectEntry _entry = _ConnectEntry.manual;

  /// The device waiting to be approved, once a connection has asked.
  String? _pendingDeviceId;
  GatewayDiagnosis? _diagnosis;
  String? _workspaceError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // initState can run again (hot restart, route re-insertion) and a second
    // auto-connect would race the first, opening two gateways.
    if (_bootstrapped) return;
    _bootstrapped = true;

    // A mobile build can carry the desktop's already-paired OpenClaw as a
    // pre-seeded saved connection, so it is one tap away with no setup. Runs
    // before the list is read so the row is already there.
    await _seedPresets();

    final saved = await _store.list();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _adding = saved.isEmpty;
      if (startupPresets.connectionUrl.isNotEmpty) {
        _url.text = startupPresets.connectionUrl;
      }
      if (startupPresets.connectionToken.isNotEmpty) {
        _token.text = startupPresets.connectionToken;
      }
      _backendId =
          startupPresets.connectionBackendId == SavedConnection.openclaw
          ? SavedConnection.openclaw
          : SavedConnection.hermes;
    });

    // An explicit preset outranks history. It is a deliberate instruction for
    // a reproducible run, and a run that silently goes to whatever server was
    // used last is not reproducible — which is the one thing the preset is
    // for.
    if (startupPresets.hasConnection) {
      await _connect(
        startupPresets.connectionUrl,
        startupPresets.connectionToken,
        label: 'Preset',
        backendId: _backendId,
      );
      return;
    }

    // Otherwise reconnect to the last server without asking, so launching the
    // app lands in the workspace rather than a form.
    if (!widget.autoReconnect) return;
    final lastId = await _store.lastUsedId();
    if (lastId != null) {
      final match = saved.where((c) => c.id == lastId);
      if (match.isNotEmpty) {
        final lookup = await _store.readToken(lastId);
        if (lookup.token case final token? when mounted) {
          await _connect(
            match.first.url,
            token,
            id: lastId,
            backendId: match.first.backendId,
          );
          return;
        }
        // Reconnecting without asking is the happy path, not the only one.
        // Falling through silently left the form blank with no hint that a
        // reconnect had been attempted at all.
        if (mounted) _askForTokenAgain(match.first, lookup.reason);
      }
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _seedPresets() => seedStartupPresets(_store);

  Future<void> _connect(
    String url,
    String token, {
    String? id,
    String? label,
    String backendId = SavedConnection.hermes,
    bool requestAdmin = false,
  }) async {
    setState(() {
      _busy = true;
      _morph = Morph.working;
      _diagnosis = null;
      _workspaceError = null;
      _pendingDeviceId = null;
    });

    // The saved id has to exist before the connection does, because an
    // OpenClaw device key is per server and the key is part of connecting.
    // Saving after a successful connect — which is the Hermes order — would
    // mean a new key on every attempt, and a device approved once would need
    // approving again on the next try.
    final entry = await _store.save(
      id: id,
      label: label ?? _label.text.trim(),
      url: url,
      token: token,
      backendId: backendId,
      requestAdmin: requestAdmin,
    );

    final AgentBackend backend;
    HermesGateway? gateway;
    // Set when the live agent is passed to a caller that now owns it, so the
    // cleanup below stops being cleanup and starts being sabotage.
    var handedOver = false;
    HermesEndpoint? endpoint;
    try {
      if (backendId == SavedConnection.openclaw) {
        backend = await _clawBackend(
          entry.id,
          url,
          token,
          requestAdmin: requestAdmin,
        );
      } else {
        endpoint = HermesEndpoint.parse(url, credential: token);
        gateway = HermesGateway(endpoint);
        backend = HermesBackend(gateway, profile: entry.profile);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _workspaceError = '$e';
          _busy = false;
          _morph = Morph.idle;
        });
      }
      return;
    }

    // Only the connect itself is diagnosed as a connection problem. Anything
    // that fails later is a different fault and must not be reported as a bad
    // credential — an earlier version wrapped the whole workspace lifetime in
    // this catch and told the user their token was rejected when it was not.
    try {
      await backend.connect();
    } catch (e) {
      await backend.dispose();
      // A diagnosis is Hermes' — it probes the same endpoint over HTTP to tell
      // a refused credential from a closed tunnel, and there is no OpenClaw
      // equivalent. Its own errors already say which of the three gates
      // stopped them, which is what the diagnosis exists to work out.
      final diagnosis = endpoint == null
          ? null
          : await GatewayDiagnostics().diagnose(endpoint, cause: e);
      if (mounted) {
        setState(() {
          _diagnosis = diagnosis;
          if (diagnosis == null) _workspaceError = _connectMessage(e);
          _busy = false;
          _morph = Morph.idle;
        });
      }
      return;
    }

    // Connected is not the same as usable. A device that has authenticated
    // correctly but is not yet approved gets no further, and saying so — with
    // the id an operator needs — is the only thing that moves it forward.
    if (backend.connectionState.needsApproval) {
      final deviceId = await ClawIdentityStore().deviceIdFor(entry.id);
      await backend.dispose();
      if (mounted) {
        setState(() {
          _pendingDeviceId = deviceId;
          _busy = false;
          _morph = Morph.idle;
        });
      }
      return;
    }

    try {
      await _store.setLastUsed(entry.id);
      if (!mounted) return;

      // The tick, before the screen changes. 勾号弹入并把圆撑回胶囊 — this is
      // the one confirmation the connect flow gets, and pushing the workspace
      // the instant the socket opens skips straight past it. 350 ms is short
      // enough not to be a wait and long enough to be seen.
      setState(() => _morph = Morph.done);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;

      final workspace = Workspace.forBackend(backend, gateway: gateway)
        // Which saved server this is, so the memory bridge can adopt this
        // connection rather than opening a second socket to the same host —
        // which on OpenClaw would be a second device pairing.
        ..connectionId = entry.id;

      final opened = ConnectedAgent(
        connection: entry,
        workspace: workspace,
        backend: backend,
      );

      // Handing the agent over, rather than owning its screen. Whoever asked
      // now owns the workspace *and* the backend — which is why neither is
      // disposed on the way out of this method any more. Disposing them here
      // is what made a second connection impossible: the only way to open one
      // was to come back through this screen, and coming back closed the
      // first.
      if (widget.asTab) {
        handedOver = true;
        Navigator.of(context).pop(opened);
        return;
      }
      if (widget.onConnected != null) {
        handedOver = true;
        widget.onConnected!(opened);
        return;
      }

      try {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WorkspaceScreen(workspace: workspace),
          ),
        );
      } finally {
        workspace.dispose();
      }
      // Backing out is deliberate: do not auto-reconnect on next launch.
      await _store.clearLastUsed();
    } catch (e) {
      if (mounted) setState(() => _workspaceError = '$e');
    } finally {
      // Only if it is still ours. This unconditional dispose is the line that
      // made a second connection impossible: the only route to one was back
      // through this screen, and coming back closed the first agent.
      if (!handedOver) await backend.dispose();
      if (mounted) {
        setState(() {
          _busy = false;
          _morph = Morph.idle;
        });
        _store.list().then((v) {
          if (mounted) setState(() => _saved = v);
        });
      }
    }
  }

  Future<void> _forget(SavedConnection c) async {
    await _store.remove(c.id);
    final saved = await _store.list();
    if (mounted) {
      setState(() {
        _saved = saved;
        _adding = saved.isEmpty;
      });
    }
  }

  /// Flips whether [c] asks the gateway for operator.admin.
  ///
  /// Persisted immediately; it takes effect on the next connection, so a
  /// server that is already open needs reconnecting to pick it up.
  Future<void> _toggleRequestAdmin(SavedConnection c) async {
    final next = !c.requestAdmin;
    await _store.save(
      id: c.id,
      label: c.label,
      url: c.url,
      token: '',
      backendId: c.backendId,
      requestAdmin: next,
      profile: c.profile,
    );
    if (!mounted) return;
    setState(() {
      final index = _saved.indexWhere((x) => x.id == c.id);
      if (index >= 0) {
        _saved = [..._saved]..[index] = c.copyWith(requestAdmin: next);
      }
    });
    if (widget.alreadyOpen.contains(c.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Administrator ${next ? 'requested' : 'off'} — reconnect '
            '${c.displayLabel} for it to take effect.',
          ),
        ),
      );
    }
  }

  /// An OpenClaw backend for a saved server, with that server's own key.
  ///
  /// The identity is per saved connection, so approving this device on one
  /// gateway says nothing about any other, and forgetting a server takes its
  /// key with it.
  Future<AgentBackend> _clawBackend(
    String connectionId,
    String url,
    String token, {
    bool requestAdmin = false,
  }) async {
    final identity = await ClawIdentityStore().identityFor(connectionId);
    return ClawBackend(
      ClawGateway(
        ClawEndpoint(url: Uri.parse(url), token: token),
        identity: identity,
        // Least privilege unless the person asked for writes. adminScopes
        // lets the shared memory base write MEMORY.md; on this gateway the
        // auth token is already the administrator credential, so a request
        // for admin is granted — but the client must still ask.
        scopes: requestAdmin ? ClawGateway.adminScopes : ClawGateway.chatScopes,
      ),
    );
  }

  /// What to show when a connect failed and there is no diagnosis to run.
  static String _connectMessage(Object error) => switch (error) {
    AgentException(:final detail) when detail.isNotEmpty => detail,
    _ => '$error',
  };

  Future<void> _connectSaved(SavedConnection c) async {
    // Already a tab: go to it rather than opening a second connection.
    if (widget.alreadyOpen.contains(c.id)) {
      widget.onFocusExisting?.call(c.id);
      return;
    }
    final lookup = await _store.readToken(c.id);
    final token = lookup.token;
    if (token == null) {
      _askForTokenAgain(c, lookup.reason);
      return;
    }
    await _connect(
      c.url,
      token,
      id: c.id,
      backendId: c.backendId,
      requestAdmin: c.requestAdmin,
    );
  }

  /// Opens the form for a server whose token could not be read, filled in.
  ///
  /// This used to be `setState(() => _adding = true)` and nothing else, which
  /// produced the exact bug reported: a screen listing two saved servers above
  /// an empty form, with no indication that anything had been tried. Three
  /// separate things were wrong with it.
  ///
  /// The form was **blank** when the name, URL and backend were all already
  /// known — they are on screen in the row that was just tapped — so the user
  /// was asked to retype what the app was showing them.
  ///
  /// It was **silent**, so a Keychain that refused looked identical to a tap
  /// that missed.
  ///
  /// And the backend picker stayed on whatever it was, so tapping an OpenClaw
  /// row could open a form describing Hermes.
  void _askForTokenAgain(SavedConnection c, String? reason) {
    setState(() {
      _adding = true;
      _label.text = c.label;
      _url.text = c.url;
      _backendId = c.backendId;
      _token.clear();
      _workspaceError =
          reason ??
          'No token is saved for ${c.displayLabel}. Paste it again to '
              'reconnect — the server and its name are already filled in.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Pushed as a route (the bottom nav's 连接), the screen wears the
    // design's connect-view topbar — back + 连接新后端 + 发现 · 配对 · 诊断 —
    // and drops the brand landing, which only belongs on the front door.
    // The root instance (nothing open yet) keeps the brand header.
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      body: SafeArea(
        child: canPop
            ? Column(
                children: [
                  _ConnectTopBar(
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: _body(l10n, brand: false),
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _body(l10n, brand: true),
                ),
              ),
      ),
    );
  }

  Widget _body(AppLocalizations? l10n, {required bool brand}) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(28),
      children: [
        if (brand) ...[
          Row(
            children: [
              ClipRRect(
                borderRadius: Radii.mediumAll,
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: .92),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) =>
                        const SizedBox(width: 48, height: 48),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  'Caduceus',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: serifDisplay(context, size: 40),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l10n?.connectToHermesDesc ??
                'Connect to a Hermes control plane. Tunnel over SSH or '
                    'Tailscale so it stays bound to loopback — then a session '
                    'token is all it needs.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.ink.secondary),
          ),
          const SizedBox(height: 26),
        ],
        if (_saved.isNotEmpty) ...[
          for (final (i, c) in _saved.indexed)
            Staggered(
              index: i,
              child: _SavedRow(
                connection: c,
                open: widget.alreadyOpen.contains(c.id),
                busy: _busy,
                onConnect: () => _connectSaved(c),
                onForget: () => _forget(c),
                onToggleRequestAdmin: c.isOpenClaw
                    ? () => _toggleRequestAdmin(c)
                    : null,
              ),
            ),
          const SizedBox(height: 10),
          if (!_adding)
            Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                onTap: () => setState(() => _adding = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: context.ink.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n?.addAnotherServer ?? 'Add another server',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.ink.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (_adding) _addForm(l10n),
        if (_workspaceError != null)
          _Trouble(
            summary:
                l10n?.sessionEndedWithError ??
                'The session ended with an error',
            detail: _workspaceError!,
          ),
        if (_diagnosis != null)
          _Trouble(summary: _diagnosis!.summary, detail: _diagnosis!.remedy),
        if (_pendingDeviceId != null)
          _AwaitingApproval(deviceId: _pendingDeviceId!),
      ],
    );
  }

  Widget _addForm(AppLocalizations? l10n) {
    return Column(
      children: [
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Segmented(
            labels: const ['Hermes', 'OpenClaw'],
            index: _backendId == SavedConnection.openclaw ? 1 : 0,
            onChanged: (i) => setState(
              () => _backendId = i == 1
                  ? SavedConnection.openclaw
                  : SavedConnection.hermes,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Segmented(
            labels: const ['Manual', 'QR', '6-digit', 'Discover'],
            index: _entry.index,
            onChanged: (i) => setState(() => _entry = _ConnectEntry.values[i]),
          ),
        ),
        if (_entry != _ConnectEntry.manual) ...[
          const SizedBox(height: 12),
          _MockEntry(
            entry: _entry,
            onUseManual: () {
              setState(() => _entry = _ConnectEntry.manual);
            },
          ),
        ] else ...[
          const SizedBox(height: 16),
          _Field(
            controller: _label,
            label: l10n?.nameOptional ?? 'Name (optional)',
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _url,
            label: l10n?.serverUrl ?? 'Server URL',
            help: 'https://host:port/optional-proxy-path',
            machine: true,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _token,
            label: _isClaw
                ? (l10n?.gatewayToken ?? 'Gateway token')
                : (l10n?.sessionToken ?? 'Session token'),
            help: _isClaw
                ? 'gateway.auth.token · stored in the Keychain'
                : 'HERMES_DASHBOARD_SESSION_TOKEN · stored in the Keychain',
            obscure: true,
            machine: true,
            onSubmitted: _submitForm,
          ),
          if (_isClaw) ...[
            const SizedBox(height: 12),
            Text(
              l10n?.openClawDeviceNote ??
                  'OpenClaw admits a new device only once an operator approves it, '
                      'so the first connection stops to wait. This app keeps one key '
                      'per server, so it is approved once and not again.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.ink.secondary),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              value: _requestAdmin,
              onChanged: (v) => setState(() => _requestAdmin = v),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Request administrator'),
              subtitle: Text(
                'operator.admin — lets the shared memory base write MEMORY.md '
                'and install skills. Least privilege is the default; turn this '
                'on only when you need writes.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.ink.secondary),
              ),
            ),
          ],
          const SizedBox(height: 22),
          Align(
            child: MorphButton(
              label: l10n?.connect ?? 'Connect',
              state: _morph,
              onPressed: _submitForm,
            ),
          ),
        ],
      ],
    );
  }

  bool get _isClaw => _backendId == SavedConnection.openclaw;

  void _submitForm() {
    final url = _url.text.trim();
    final token = _token.text.trim();
    if (url.isEmpty || token.isEmpty) return;
    _connect(url, token, backendId: _backendId, requestAdmin: _requestAdmin);
  }
}

/// A field on glass.
///
/// The label sits *above* rather than floating inside: a Material floating
/// label animates a second piece of text over a translucent sheet, and on
/// glass that is two moving layers where one would do.
/// The design's connect-view topbar: back, centered title + subtitle, and a
/// balancing spacer on the right so the title is truly centred.
class _ConnectTopBar extends StatelessWidget {
  const _ConnectTopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          _BarChip(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: onBack,
            tooltip: l10n?.back ?? 'Back',
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  l10n?.connectNewBackend ?? '连接新后端',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  l10n?.connectNewBackendSubtitle ?? '发现 · 配对 · 诊断',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, size: 11, opacity: InkLevel.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _BarChip extends StatelessWidget {
  const _BarChip({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: context.ink.secondary),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.help,
    this.obscure = false,
    this.machine = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? help;
  final bool obscure;

  /// A URL or a token — something the machine wrote, so it is set in mono
  /// where every character can be told apart.
  final bool machine;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7),
          child: Eyebrow(label),
        ),
        GlassPanel(
          level: Glass.regular,
          radius: Radii.mediumAll,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            style: machine
                ? mono(context, size: 13, opacity: InkLevel.primary)
                : Theme.of(context).textTheme.bodyMedium,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
            onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
          ),
        ),
        if (help != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 7),
            child: Text(
              help!,
              style: mono(context, size: 11, opacity: InkLevel.faint),
            ),
          ),
      ],
    );
  }
}

/// A saved server.
class _SavedRow extends StatelessWidget {
  const _SavedRow({
    this.open = false,
    required this.connection,
    required this.busy,
    required this.onConnect,
    required this.onForget,
    this.onToggleRequestAdmin,
  });

  final SavedConnection connection;

  /// This server already has a tab. Tapping goes to it rather than opening a
  /// second connection to the same host.
  final bool open;

  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onForget;

  /// Flips [SavedConnection.requestAdmin]. Null for Hermes, which has no
  /// such scope.
  final VoidCallback? onToggleRequestAdmin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Pressable(
      onTap: busy ? null : onConnect,
      scale: .98,
      semanticLabel: open
          ? 'Go to ${connection.displayLabel}, already open'
          : 'Connect to ${connection.displayLabel}',
      child: GlassPanel(
        level: Glass.thin,
        radius: Radii.mediumAll,
        padding: const EdgeInsets.fromLTRB(16, 13, 8, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          connection.displayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      // Says why tapping this switches instead of connecting.
                      // Without it, a row that behaves differently from its
                      // neighbours looks like a bug.
                      if (open) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Palette.jade.withValues(alpha: .18),
                            borderRadius: Radii.pillAll,
                          ),
                          child: Text(
                            'Open',
                            style: mono(
                              context,
                              size: 10,
                              opacity: InkLevel.secondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Which agent this row will connect to. Shown because
                      // for a record saved before the field existed it is
                      // inferred from the URL, and a wrong inference should
                      // be visible before it is pressed rather than after.
                      Text(
                        connection.backendLabel,
                        style: mono(context, size: 11, opacity: InkLevel.faint),
                      ),
                      Text(
                        '  ·  ',
                        style: mono(context, size: 11, opacity: InkLevel.faint),
                      ),
                      Flexible(
                        child: Text(
                          connection.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(
                            context,
                            size: 11,
                            opacity: InkLevel.faint,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (onToggleRequestAdmin != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Administrator',
                          style: mono(
                            context,
                            size: 11,
                            opacity: InkLevel.secondary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          connection.requestAdmin ? 'on' : 'off',
                          style: mono(
                            context,
                            size: 11,
                            opacity: connection.requestAdmin
                                ? InkLevel.secondary
                                : InkLevel.faint,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Switch(
                          value: connection.requestAdmin,
                          onChanged: busy
                              ? null
                              : (_) => onToggleRequestAdmin!(),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Tooltip(
              message:
                  AppLocalizations.of(context)?.forgetThisServer ??
                  'Forget this server',
              child: Pressable(
                onTap: busy ? null : onForget,
                semanticLabel: 'Forget ${connection.displayLabel}',
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: context.ink.faint,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Something went wrong, and what to do about it.
class _Trouble extends StatelessWidget {
  const _Trouble({required this.summary, required this.detail});

  final String summary;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: Radii.mediumAll,
        color: Palette.coral.withValues(alpha: .08),
        border: Border.all(color: Palette.coral.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: dangerInk(context),
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            detail,
            style: TextStyle(
              fontSize: 13,
              height: 1.7,
              color: context.ink.secondary,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Not an error — a wait, on somebody else.
class _AwaitingApproval extends StatelessWidget {
  const _AwaitingApproval({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: GlassPanel(
        level: Glass.regular,
        radius: Radii.mediumAll,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusPill(
                  label: l10n?.waitingToBeApproved ?? 'Waiting to be approved',
                  color: Palette.brass,
                  pulsing: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n?.openClawApprovalNote ??
                  'The gateway accepted the token and the handshake. It admits a '
                      'new device only once an operator approves it, so approve this '
                      'device and connect again.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.ink.secondary),
            ),
            const SizedBox(height: 12),
            SelectableText(
              deviceId,
              style: mono(context, size: 11, opacity: InkLevel.primary),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: GlassButton(
                label: l10n?.copyDeviceId ?? 'Copy device id',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: deviceId)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four connect entries the design draws: Manual / QR / 6-digit / mDNS.
enum _ConnectEntry { manual, qr, pair, discover }

/// The design's QR / pair-code / discovery panes.
///
/// These are **mocks, explicitly labelled 示例**: the Hermes gateway exposes
/// no pairing or discovery API, so only manual entry is real. Each pane says
/// so and offers the way back to the form that works, rather than pretending
/// to pair.
class _MockEntry extends StatelessWidget {
  const _MockEntry({required this.entry, required this.onUseManual});

  final _ConnectEntry entry;
  final VoidCallback onUseManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, body) = switch (entry) {
      _ConnectEntry.qr => (
        Icons.qr_code_2_rounded,
        'Scan a pairing QR',
        'Point the camera at the server\'s pairing code. The gateway has no '
            'QR pairing API yet, so this entry is a design mock — 示例.',
      ),
      _ConnectEntry.pair => (
        Icons.pin_outlined,
        'Enter a 6-digit pair code',
        'The six-digit code shown on the server. No pairing API exists on the '
            'gateway yet, so this entry is a design mock — 示例.',
      ),
      _ConnectEntry.discover => (
        Icons.wifi_tethering_rounded,
        'Discover servers on this network',
        'mDNS discovery is not served by the gateway. This entry is a design '
            'mock — 示例.',
      ),
      _ConnectEntry.manual => (Icons.keyboard_outlined, '', ''),
    };
    return GlassPanel(
      level: Glass.thin,
      radius: Radii.mediumAll,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Palette.brass),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.ink.secondary,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onUseManual,
            child: const Text('Use manual entry instead'),
          ),
        ],
      ),
    );
  }
}
