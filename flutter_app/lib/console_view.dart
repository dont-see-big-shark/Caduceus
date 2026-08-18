import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

import 'agents_panel.dart';
import 'design/components.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'checkpoints_panel.dart';
import 'fleet_panel.dart';
import 'journey_panel.dart';
import 'memory_panel.dart';
import 'processes_panel.dart';
import 'server_panel.dart';
import 'shared_memory_panel.dart';
import 'skills_panel.dart';
import 'widgets/console_composer.dart';
import 'widgets/console_header.dart';
import 'design/press.dart';
import 'widgets/command_palette.dart';
import 'widgets/console_menu.dart';
import 'widgets/model_list.dart';
import 'widgets/model_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/panel_frame.dart';
import 'widgets/transcript_links.dart';
import 'widgets/turn_timeline.dart';
import 'haptics.dart';
import 'capture.dart';
import 'l10n/app_localizations.dart';
import 'transcript_blobs.dart';
import 'workspace.dart';

/// One session's transcript, tools, and approvals.
class ConsoleView extends StatefulWidget {
  const ConsoleView({
    required this.workspace,
    this.peers = MemoryPeers.none,
    required this.console,
    this.compactChrome = false,
    this.media,
    this.voice,
    this.onReconnectWithAdmin,
    this.topBar,
    this.belowBar,
    this.onOpenPanels,
    super.key,
  });

  final Workspace workspace;

  /// Already-open tabs the memory bridge can ask without a handshake.
  final MemoryPeers peers;

  /// Reopens this tab asking the gateway for operator.admin. Provided by the
  /// shell for OpenClaw tabs, so the model chip's admin explanation can offer
  /// a one-tap fix instead of sending the user to the connection list.
  final Future<bool> Function()? onReconnectWithAdmin;
  final SessionConsole console;

  /// Passed through to the composer. Only a test supplies these; the composer
  /// reaches for the real camera and recogniser when they are absent.
  final MediaCapture? media;
  final VoiceInput? voice;

  /// Draw the phone's top bar here — drawer button, title, session menu — in
  /// one row instead of a navigation bar with a second band under it. Those
  /// two together spent 120 points of a 852-point screen restating the same
  /// session.
  final bool compactChrome;

  /// The agent-chip strip, rendered at the top of the phone screen (highest
  /// hierarchy: agent server > session > conversation). Only the compact shell
  /// passes this.
  final Widget? topBar;

  /// Legacy alias for [topBar].
  final Widget? belowBar;

  /// Opens the design's panel sheet (the Capabilities Hub) from the phone's
  /// top bar. Null on desktop, where the panel rail has its own button.
  final VoidCallback? onOpenPanels;

  @override
  State<ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends State<ConsoleView> {
  final GlobalKey<ConsoleComposerState> _composerKey = GlobalKey();
  final ValueNotifier<List<CompletionItem>> _completionsNotifier =
      ValueNotifier(const []);

  /// Guards against a second picker while the first is still open. Without it
  /// a slow load invites repeated taps and stacks dialogs.
  bool _pickingModel = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_followGrowingChrome);
  }

  @override
  void didUpdateWidget(ConsoleView old) {
    super.didUpdateWidget(old);
    if (old.console != widget.console) {
      old.console.removeListener(_followGrowingChrome);
      _c.addListener(_followGrowingChrome);
    }
  }

  /// The turn's reasoning and tool rows live inside the transcript list but
  /// are not part of its document, so they grow without the renderer noticing.
  /// During a long think with no answer text yet, that left the newest
  /// reasoning written off the bottom of the screen — 0 px of scroll against
  /// 2,110 px of content, in the test that pins this.
  void _followGrowingChrome() => _c.markdown.requestFollow();

  @override
  void dispose() {
    _c.removeListener(_followGrowingChrome);
    _completionsNotifier.dispose();
    super.dispose();
  }

  SessionConsole get _c => widget.console;

  /// One record, two places: the phone's top bar and the desktop header show
  /// the same menu, and building it twice is how they drift apart.
  ConsoleActions get _actions => ConsoleActions(
    streaming: _c.streaming,
    supports: widget.workspace.supports,
    onSetCwd: _setCwd,
    onUndo: _undo,
    onShowCheckpoints: _showCheckpoints,
    onShowProcesses: _showProcesses,
    onShowAgents: _showAgents,
    onShowJourney: _showJourney,
    onShowMemory: _showMemory,
    onShowServer: _showServer,
    onShowSkills: _showSkills,
    onShowFleet: _showFleet,
    onShowSharedMemory: _showSharedMemory,
    onFindInConversation: _findInConversation,
    onCopyTranscript: _copyTranscript,
    onBranch: _branch,
    onShowStats: _showStats,
  );

  /// The phone's top bar: drawer, title, session menu — one row.
  ///
  /// The "…" lived in a band below the navigation bar, which meant two
  /// stacked strips both describing the same session. It belongs up here with
  /// everything else that acts on the session.
  Widget _compactBar(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final agentTabs = widget.topBar ?? widget.belowBar;
    // The design's topbar carries a one-line status under the title
    // ("正在运行 · glm-5-2-260617"), so the phone bar is a touch taller than
    // the plain 52 pt it used to be.
    return SafeArea(
      top: agentTabs == null,
      bottom: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              const SizedBox(width: 4),
              _BarChip(
                icon: Icons.menu_rounded,
                tooltip: l10n?.sessions ?? 'Sessions',
                onTap: () {
                  Haptics.tap();
                  Scaffold.of(context).openDrawer();
                },
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _c,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _c.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // The design's `.topbar .t span`: a lit dot, the run
                      // state, then the model — machine text in mono, exactly
                      // like the desktop header's sub row.
                      Text.rich(
                        TextSpan(
                          children: [
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _c.streaming
                                      ? Palette.azure
                                      : Palette.jade,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (_c.streaming
                                                  ? Palette.azure
                                                  : Palette.jade)
                                              .withValues(alpha: .5),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            TextSpan(
                              text:
                                  '${_c.streaming ? (l10n?.running ?? 'Running') : (l10n?.idle ?? 'Idle')}'
                                  '${_c.model.trim().isEmpty ? '' : ' · ${_c.model.trim()}'}',
                              style:
                                  mono(
                                    context,
                                    size: 11,
                                    opacity: _c.streaming
                                        ? InkLevel.primary
                                        : InkLevel.tertiary,
                                  ).copyWith(
                                    color: _c.streaming ? Palette.azure : null,
                                  ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              // The design's `more-pop` is an anchored menu, not a full-window
              // palette; the same ConsoleMenu as the desktop header keeps one
              // control vocabulary across both surfaces.
              ConsoleMenu(actions: _actions, tapTargetSize: 44),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  void _stopTurn() {
    Haptics.warn();
    widget.workspace.interrupt(_c.persistedId);
  }

  Future<bool> _answerPrompt(AgentPrompt prompt, String value) =>
      widget.workspace.respondToPrompt(_c.persistedId, prompt, value);

  Future<void> _handleSend(
    String text, {
    List<Attachment> attachments = const [],
  }) async {
    // A slash command is for the client, not the agent, so it has nowhere to
    // put a file. Attachments ride only on an ordinary message.
    if (text.startsWith('/') && attachments.isEmpty) {
      await widget.workspace.dispatchCommand(_c.persistedId, text);
    } else {
      await widget.workspace.send(
        _c.persistedId,
        text,
        queued: _c.streaming,
        attachments: attachments,
      );
    }
    _c.markdown.scrollToBottom();
  }

  Future<void> _handleSteer(String text) async {
    await widget.workspace.steer(_c.persistedId, text);
    _c.markdown.scrollToBottom();
  }

  Future<void> _handleRedirect(String text) async {
    await widget.workspace.redirect(_c.persistedId, text);
    _c.markdown.scrollToBottom();
  }

  Future<void> _setCwd() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _c.cwd);
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => Panel(
        title: Text(l10n?.workingDirectoryTitle ?? 'Working directory'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n?.workingDirectoryDesc ??
                  'A path on the server running the agent, not on this Mac. '
                      'Attachments and @-references resolve against it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(isDense: true),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n?.set ?? 'Set'),
          ),
        ],
      ),
    );
    if (chosen == null || chosen.trim().isEmpty) return;
    await widget.workspace.setCwd(_c.persistedId, chosen.trim());
  }

  Future<void> _undo() async {
    final l10n = AppLocalizations.of(context);
    final removed = await widget.workspace.undo(_c.persistedId);
    if (!mounted || removed == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed == 0
              ? (l10n?.nothingToUndo ?? 'Nothing to undo')
              : (l10n?.removedMessages(removed) ??
                    'Removed $removed message(s)'),
        ),
      ),
    );
  }

  /// Opens any of the console's panel overlays through one entry point, so
  /// they all share the same shape.
  Future<void> _openPanel(WidgetBuilder builder) =>
      showPanel<void>(context, builder);

  Future<void> _showCheckpoints() => _openPanel(
    (_) => CheckpointsPanel(
      gateway: widget.workspace.gateway,
      liveSessionId: _c.liveId,
    ),
  );

  Future<void> _showJourney() =>
      _openPanel((_) => JourneyPanel(gateway: widget.workspace.gateway));

  Future<void> _showMemory() => _openPanel(
    (_) => MemoryPanel(workspace: widget.workspace, peers: widget.peers),
  );

  Future<void> _showAgents() => _openPanel(
    (_) => AgentsPanel(
      gateway: widget.workspace.gateway,
      liveSessionId: _c.liveId,
    ),
  );

  Future<void> _findInConversation() =>
      showPanel<void>(context, (_) => _FindSheet(controller: _c.markdown));

  Future<void> _copyTranscript() async {
    final l10n = AppLocalizations.of(context);
    final text = _c.markdown.text;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n?.copiedCharacters(text.length) ??
              'Copied ${text.length} characters',
        ),
      ),
    );
  }

  Future<void> _showSkills() => _openPanel(
    (_) => SkillsPanel(workspace: widget.workspace, peers: widget.peers),
  );

  Future<void> _showFleet() => _openPanel(
    (_) => FleetPanel(workspace: widget.workspace, peers: widget.peers),
  );

  Future<void> _showSharedMemory() => _openPanel(
    (_) => SharedMemoryPanel(workspace: widget.workspace, peers: widget.peers),
  );

  Future<void> _showServer() => _openPanel(
    (_) => ServerPanel(workspace: widget.workspace, sessionId: _c.persistedId),
  );

  Future<void> _showProcesses() => _openPanel(
    (_) =>
        ProcessesPanel(workspace: widget.workspace, sessionId: _c.persistedId),
  );

  Future<void> _branch() async {
    final l10n = AppLocalizations.of(context);
    final id = await widget.workspace.branch(_c.persistedId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          id == null
              ? (l10n?.branchFailed ?? 'Branch failed')
              : (l10n?.branchedTo(id) ?? 'Branched to $id'),
        ),
      ),
    );
    if (id != null) await widget.workspace.open(id);
  }

  Future<void> _showStats() async {
    final l10n = AppLocalizations.of(context);
    final usage = await widget.workspace.sessionStats(_c.persistedId);
    if (usage == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Panel(
        title: Text(l10n?.sessionUsage ?? 'Session usage'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (usage.hasContext) ...[
                  ContextMeter(
                    used: usage.contextUsed,
                    total: usage.contextMax,
                  ),
                  const SizedBox(height: 18),
                  Divider(height: 1, color: context.ink.hairline),
                  const SizedBox(height: 14),
                ],
                if (usage.totalTokens > 0)
                  _UsageFact('Tokens', '${usage.totalTokens}'),
                if (usage.inputTokens > 0)
                  _UsageFact('In', '${usage.inputTokens}'),
                if (usage.outputTokens > 0)
                  _UsageFact('Out', '${usage.outputTokens}'),
                if (usage.costUsd > 0)
                  _UsageFact('Cost', '\$${usage.costUsd.toStringAsFixed(4)}'),
                for (final (label, value) in usage.details)
                  _UsageFact(label, value),
                if (usage.isEmpty)
                  Text(
                    l10n?.thisServerReportsNothing ??
                        'This server reports nothing about this session yet.',
                    style: TextStyle(color: context.ink.tertiary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the model picker.
  ///
  /// The dialog appears first and loads inside itself. `model.options` takes
  /// 3-7 seconds against a real server and does not speed up on repeat, so
  /// awaiting it before showing anything left a dead button for several
  /// seconds — and people tapped again, stacking dialogs and concurrent calls.
  Future<void> _pickModel() async {
    if (_pickingModel) return;
    // OpenClaw gates switching a *running* session's model behind
    // operator.admin (sessions.patch). Without it the picker would list the
    // agent's allowed models and fail on the tap, so say why first — the
    // fix is the connect screen's Request administrator control, and a new
    // session can still be born on any allowed model.
    if (!widget.workspace.supports(Capability.modelSwitching)) {
      final reconnect = widget.onReconnectWithAdmin;
      final wanted = await showDialog<bool>(
        context: context,
        builder: (context) => Panel(
          title: Text('Switching this session\'s model needs administrator'),
          content: Text(
            '${widget.workspace.backend.displayName} only lets an operator '
            'change a running session\'s model (like the official client, '
            'whose connection has administrator). One tap reconnects this '
            'server asking for it — then switching works here. New sessions '
            'can already start on any allowed model.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            if (reconnect != null)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Request administrator & reconnect'),
              ),
          ],
        ),
      );
      if (wanted == true && reconnect != null) {
        await reconnect();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Reconnected with administrator — tap the model again to '
                'switch.',
              ),
            ),
          );
        }
      }
      return;
    }
    _pickingModel = true;
    try {
      // Two pickers, because they are two surfaces rather than degrees of
      // one. Hermes organises models by provider and can be given an API key;
      // OpenClaw hands back a flat catalog of what it already has credentials
      // for. Showing the provider dialog to the second would ask about keys it
      // has no concept of.
      final chosen = widget.workspace.supports(Capability.modelProviders)
          ? await showPanel<ModelSheetResult>(
              context,
              (_) => ModelSheet(
                workspace: widget.workspace,
                sessionId: _c.persistedId,
              ),
            )
          : await showModelList(
              context,
              workspace: widget.workspace,
              sessionId: _c.persistedId,
              current: _c.model,
            );
      if (chosen == null || !mounted) return;

      switch (chosen) {
        case ConnectProvider(:final slug):
          await _connectProvider(slug);
        case DisconnectProvider(:final slug):
          await _disconnectProvider(slug);
        case PickModel(:final model, :final providerSlug):
          if (model == _c.model) return;
          await widget.workspace.setModel(
            _c.persistedId,
            model,
            provider: providerSlug,
          );
      }
    } finally {
      _pickingModel = false;
    }
  }

  Future<void> _connectProvider(String slug) async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (context) => Panel(
        title: Text('Connect $slug'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The key is sent to your server and stored there. Caduceus does '
              'not keep a copy.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'API key',
                isDense: true,
              ),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (key == null || key.trim().isEmpty) return;
    final ok = await widget.workspace.connectProvider(
      _c.persistedId,
      slug,
      key.trim(),
    );
    controller.clear();
    if (ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connected $slug')));
    }
  }

  Future<void> _disconnectProvider(String slug) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text('Disconnect $slug?'),
        content: const Text(
          'The stored credentials are removed from the server. Sessions '
          'using this provider will stop working until it is reconnected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.workspace.disconnectProvider(_c.persistedId, slug);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TranscriptBlobScope(
      // Wraps the whole console so transcript images — which are references
      // into this session's store, not inline bytes — resolve wherever they
      // are rendered, including inside the Markdown view's own tree.
      store: _c.blobs,
      child: CallbackShortcuts(
        // ⌘K 是这一版的核心交互. Bound at the console rather than the workspace so
        // it reaches the actions of the session you are actually looking at.
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              showCommandPalette(context, sessionCommands(_actions)),
        },
        child: LayoutBuilder(
          builder: (context, box) {
            final agentTabs = widget.topBar ?? widget.belowBar;
            return Column(
              children: [
                // The design's chipstrip: agent tabs sit at the very top (highest
                // hierarchy: server/agent > session > transcript). Desktop keeps
                // its strip in the shell, so this slot is only filled on a
                // phone / compact layout.
                if (widget.compactChrome && agentTabs != null) agentTabs,
                if (widget.compactChrome) _compactBar(theme),
                if (!widget.compactChrome)
                  ConsoleHeader(
                    console: _c,
                    workspace: widget.workspace,
                    actions: _actions,
                    onSetCwd: _setCwd,
                    onUndo: _undo,
                    onShowCheckpoints: _showCheckpoints,
                    onShowProcesses: _showProcesses,
                    onShowAgents: _showAgents,
                    onShowJourney: _showJourney,
                    onShowServer: _showServer,
                    onFindInConversation: _findInConversation,
                    onCopyTranscript: _copyTranscript,
                    onBranch: _branch,
                    onShowStats: _showStats,
                    availableHeight: box.maxHeight,
                  ),
                Expanded(
                  key: const ValueKey('middle'),
                  // Tapping the conversation puts the keyboard away. Dragging
                  // already does (both scrollables opt into onDrag), but a tap is
                  // what people try first, and translucent means the children —
                  // links, disclosure rows, approval buttons — still get theirs.
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      // Also closes the command palette. It used to clear only on
                      // the next keystroke, so tapping away left it open.
                      FocusScope.of(context).unfocus();
                      _completionsNotifier.value = const [];
                    },
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final chromeMax = box.maxHeight * 0.5;
                        final paletteMax = box.maxHeight * 0.35;
                        return Column(
                          children: [
                            ListenableBuilder(
                              listenable: _c,
                              builder: (context, _) {
                                if (_c.lastError == null) {
                                  return const SizedBox.shrink();
                                }
                                return Container(
                                  key: const ValueKey('error'),
                                  width: double.infinity,
                                  color: theme.colorScheme.errorContainer,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    _c.lastError!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                );
                              },
                            ),
                            ListenableBuilder(
                              listenable: _c,
                              builder: (context, _) {
                                if (!_c.unattended &&
                                    _c.configWarning == null) {
                                  return const SizedBox.shrink();
                                }
                                // Both come from session.info. "Nothing will ask
                                // before acting" is not a status-line detail, and a
                                // server that says its own configuration is broken
                                // should not be the last to know.
                                return Container(
                                  key: const ValueKey('session-warning'),
                                  width: double.infinity,
                                  color: theme.colorScheme.tertiaryContainer,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.report_gmailerrorred,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          [
                                            if (_c.unattended)
                                              'This session runs tools without asking'
                                                  '${_c.approvalMode.isEmpty ? '' : ' (${_c.approvalMode})'}.',
                                            if (_c.configWarning != null)
                                              _c.configWarning!,
                                          ].join('  ·  '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            ListenableBuilder(
                              listenable: _c,
                              builder: (context, _) {
                                // Only what must stay reachable: a question the
                                // agent is blocked on, and an approval gate. The
                                // turn's thinking lives in the transcript now,
                                // where it happened.
                                final hasChrome =
                                    // Questions are no longer here — they render
                                    // in the turn that asked them. Approvals stay:
                                    // they gate the whole session, not one turn.
                                    _c.approvals.isNotEmpty;
                                if (!hasChrome) return const SizedBox.shrink();
                                return ConstrainedBox(
                                  key: const ValueKey('chrome'),
                                  constraints: BoxConstraints(
                                    maxHeight: chromeMax,
                                  ),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        for (final approval in _c.approvals)
                                          _approvalBanner(approval, theme),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            // 铁律：正文永远不放在玻璃上.
                            //
                            // Everything else here floats; the conversation does
                            // not. On the simulator the aurora was drifting behind
                            // a table of results — coloured light moving under the
                            // text you are trying to read. This opaque plane is
                            // what all the glass is *over*, and without it the
                            // design has nothing to refract and nothing legible.
                            Expanded(
                              key: const ValueKey('transcript'),
                              child: ColoredBox(
                                // The conversation plane is deep-space black,
                                // not slate: the long-form messages on it are
                                // slate, and a whole slate field read as a
                                // blue-grey page instead of a black one.
                                color: theme.brightness == Brightness.dark
                                    ? Palette.voidBlack
                                    : Colors.white,
                                child: ListenableBuilder(
                                  listenable: _c,
                                  builder: (context, _) {
                                    if (!_c.historyLoaded) {
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          color: Palette.brass,
                                        ),
                                      );
                                    }
                                    // Each turn renders under its own question. The
                                    // last one also renders before the tail, because
                                    // its prompt has not settled into a block yet
                                    // while the answer is still being written.
                                    final turns = _c.turns;
                                    final byAnchor = {
                                      for (final turn in turns)
                                        if (turn.anchorBlock >= 0)
                                          turn.anchorBlock: turn,
                                    };
                                    final current = turns.isEmpty
                                        ? null
                                        : turns.last;
                                    return StreamingMarkdownView(
                                      controller: _c.markdown,
                                      styleSheet: transcriptMarkdown(context),
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        6,
                                        16,
                                        16,
                                      ),
                                      // A question becomes a bubble on the trailing
                                      // side. The transcript is one document, so a
                                      // marker in the text is the only thing that
                                      // distinguishes it — see message_bubble.dart.
                                      onTapLink: (text, href, title) =>
                                          openTranscriptLink(
                                            context,
                                            href,
                                            title: title,
                                          ),
                                      blockDecorator: (index, data, child) =>
                                          isUserBlock(data)
                                          // 气泡从输入条位置向上生长入场 — it
                                          // grows out of the corner the composer
                                          // is in, and only the first time it is
                                          // built.
                                          ? GrowFromComposer(
                                              index: index,
                                              revealed: _c.revealedBubbles,
                                              child: UserBubble(
                                                text: userBlockText(data),
                                              ),
                                            )
                                          : child,
                                      afterBlock: (index) {
                                        final turn = byAnchor[index];
                                        if (turn == null) return null;
                                        return TurnTimeline(
                                          key: ValueKey('turn-$index'),
                                          console: _c,
                                          turn: turn,
                                          isCurrent: identical(turn, current),
                                          onAnswerPrompt: _answerPrompt,
                                          onStop: _stopTurn,
                                        );
                                      },
                                      // Only while a turn is running: a caret left
                                      // blinking under a finished answer says the
                                      // opposite of what it means.
                                      afterTail: _c.streaming
                                          ? const StreamCaret()
                                          : null,
                                      beforeTail:
                                          current == null ||
                                              current.anchorBlock >= 0
                                          ? null
                                          : TurnTimeline(
                                              key: const ValueKey('turn-tail'),
                                              console: _c,
                                              turn: current,
                                              isCurrent: true,
                                              onAnswerPrompt: _answerPrompt,
                                              onStop: _stopTurn,
                                            ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            ValueListenableBuilder<List<CompletionItem>>(
                              valueListenable: _completionsNotifier,
                              builder: (context, completions, _) {
                                if (completions.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return CompletionOverlay(
                                  completions: completions,
                                  maxHeight: paletteMax,
                                  onSelect: (item) => _composerKey.currentState
                                      ?.applyCompletion(item),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                // No divider. The composer is a floating sheet now; a hard rule
                // above it drew a white line across the screen and made the two
                // read as one welded panel instead of glass over content.
                const SizedBox(key: ValueKey('divider'), height: 0),
                ConsoleComposer(
                  key: _composerKey,
                  console: _c,
                  workspace: widget.workspace,
                  media: widget.media,
                  voice: widget.voice,
                  completionsNotifier: _completionsNotifier,
                  onSend: _handleSend,
                  onSteer: _handleSteer,
                  onRedirect: _handleRedirect,
                  // Always tappable; _pickModel decides inside. On OpenClaw
                  // without operator.admin the picker cannot write a running
                  // session, and the tap explains why and what to do rather
                  // than being a dead control.
                  onPickModel: _pickModel,
                  onStop: _stopTurn,
                  availableHeight: box.maxHeight,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Button copy for one of the server's choice values.
  ///
  /// Presentation, not translation: the values come from the server and are
  /// sent back verbatim, and anything unrecognised is shown as it arrived
  /// rather than guessed at.
  static String _choiceLabel(String choice) => switch (choice) {
    'once' => 'Allow once',
    'session' => 'Allow this session',
    'always' => 'Always allow',
    'deny' => 'Deny',
    _ => choice,
  };

  /// The refusal, which is styled quieter than the ways of saying yes.
  static bool _isDeny(String choice) => choice == 'deny';

  Widget _approvalBanner(AgentPrompt prompt, ThemeData theme) {
    return Container(
      key: ValueKey('approval-${prompt.subject}-${prompt.question}'),
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt.escalated
                ? 'Smart mode denied this — override?'
                : 'Approval required'
                      '${prompt.subject.isEmpty ? '' : ' · '}'
                      '${prompt.subject}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (prompt.question.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              prompt.question,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final choice in prompt.choices)
                if (_isDeny(choice))
                  TextButton(
                    onPressed: () => widget.workspace.respondToApproval(
                      _c.persistedId,
                      prompt,
                      choice,
                    ),
                    child: Text(_choiceLabel(choice)),
                  )
                else
                  FilledButton(
                    onPressed: () => widget.workspace.respondToApproval(
                      _c.persistedId,
                      prompt,
                      choice,
                    ),
                    child: Text(_choiceLabel(choice)),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FindSheet extends StatefulWidget {
  const _FindSheet({required this.controller});
  final StreamingMarkdownController controller;

  @override
  State<_FindSheet> createState() => _FindSheetState();
}

class _FindSheetState extends State<_FindSheet> {
  final _query = TextEditingController();
  List<(int, String, int)> _hits = const [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search(String raw) {
    final needle = raw.trim();
    if (needle.isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    final pattern = RegExp(RegExp.escape(needle), caseSensitive: false);
    final hits = <(int, String, int)>[];
    final blocks = widget.controller.blocks;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final match = pattern.firstMatch(block);
      if (match == null) continue;
      final at = match.start;
      final start = (at - 40).clamp(0, block.length);
      final end = (at + needle.length + 60).clamp(0, block.length);
      final snippet = block.substring(start, end).replaceAll('\n', ' ');
      hits.add((
        i,
        '${start > 0 ? '…' : ''}$snippet${end < block.length ? '…' : ''}',
        at,
      ));
    }
    setState(() => _hits = hits);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      title: const Text('Find in conversation'),
      content: PanelFrame(
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: _search,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _query.text.trim().isEmpty
                    ? '${widget.controller.blocks.length} blocks'
                    : '${_hits.length} match${_hits.length == 1 ? '' : 'es'}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.separated(
                itemCount: _hits.length,
                separatorBuilder: (context, _) =>
                    Divider(height: 1, color: context.ink.hairline),
                itemBuilder: (context, i) {
                  final (block, snippet, at) = _hits[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.controller.scrollToBlock(
                        block,
                        characterOffset: at,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round chip in the phone's top bar.
///
/// The two buttons up here used to disagree with each other: the drawer was a
/// bare [IconButton] with no chrome at all and the menu was a circle with an
/// outline and no fill, so one looked pressed-in and the other looked like a
/// hole. They frame the title symmetrically, so they have to be the same
/// object — a filled circle of the same glass everything else on this screen
/// is made of.
class _BarChip extends StatelessWidget {
  const _BarChip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Pressable(
      onTap: onTap,
      semanticLabel: tooltip,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              // Filled, not outlined. A subtle squircle on a dark ground.
              color: context.ink.base.withValues(alpha: .07),
              border: Border.all(color: context.ink.hairline),
            ),
            child: Icon(icon, size: 19, color: context.ink.secondary),
          ),
        ),
      ),
    ),
  );
}

/// One label/value line in the usage dialog.
///
/// A row rather than a `Text` of pretty-printed JSON, which is what this was:
/// the number people open the dialog for was twelve lines down a dump, in a
/// dialog whose whole purpose is to answer it.
class _UsageFact extends StatelessWidget {
  const _UsageFact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.ink.tertiary, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        SelectableText(
          value,
          style: mono(context, size: 12, opacity: InkLevel.secondary),
        ),
      ],
    ),
  );
}
