import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'design/tokens.dart';
import 'widgets/panel_frame.dart';
import 'workspace.dart';

/// What both agents can do, side by side.
///
/// The skills bridge — `SKILLS_BRIDGE.md` v1. Every skill either connected
/// agent has, in one list: which agent has it, whether it is usable and why
/// not, and the SKILL.md itself where readable. Deliberately read-only: a
/// skill gets in through a registry install or a file on the server, neither
/// of which this client can do from here, so a write control would be a
/// button that fails.
class SkillsPanel extends StatefulWidget {
  const SkillsPanel({
    required this.workspace,
    this.embedded = false,
    this.peers = MemoryPeers.none,
    super.key,
  });

  final Workspace workspace;

  /// Already-open tabs the bridge can ask without a handshake.
  final MemoryPeers peers;

  /// Render inside a parent surface (right panel rail) instead of a
  /// dialog/sheet. See [Panel.embedded].
  final bool embedded;

  @override
  State<SkillsPanel> createState() => _SkillsPanelState();
}

class _SkillsPanelState extends State<SkillsPanel> {
  SkillLibraryView? _view;
  String? _error;
  String? _expanded;

  /// Show only what one agent has and another does not.
  bool _onlyDivergent = false;

  /// True while the other saved servers are being opened.
  bool _reaching = false;

  Workspace get _ws => widget.workspace;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reachOut = false}) async {
    setState(() {
      _error = null;
      _reaching = reachOut;
    });
    try {
      final view = await _ws.skillView(reachOut: reachOut, peers: widget.peers);
      if (mounted) setState(() => _view = view);
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    } finally {
      if (mounted) setState(() => _reaching = false);
    }
  }

  List<SkillCluster> get _shown {
    final view = _view;
    if (view == null) return const [];
    return _onlyDivergent ? view.divergent : view.clusters;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      embedded: widget.embedded,
      title: Row(
        children: [
          const Expanded(child: Text('Skills')),
          if (_reaching)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          TextButton(
            onPressed: _reaching ? null : () => _load(reachOut: true),
            child: const Text('Ask every agent'),
          ),
          IconButton(
            onPressed: _reaching ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: 'Reload',
          ),
        ],
      ),
      content: PanelFrame(
        child: switch ((_error, _view)) {
          (final String message, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
          (_, null) => const Center(child: CircularProgressIndicator()),
          (_, final SkillLibraryView view) when view.isEmpty => _EmptySkills(
            backendName: _ws.backend.displayName,
          ),
          (_, final SkillLibraryView view) => _body(theme, view),
        },
      ),
    );
  }

  Widget _body(ThemeData theme, SkillLibraryView view) => Column(
    children: [
      _Sources(backends: view.liveBackendIds),
      if (view.unreachable.isNotEmpty) _Unreachable(view: view),
      if (view.divergent.isNotEmpty)
        _DivergenceBar(
          count: view.divergent.length,
          only: _onlyDivergent,
          onToggle: () => setState(() => _onlyDivergent = !_onlyDivergent),
        ),
      Expanded(
        child: _shown.isEmpty
            ? Center(
                child: Text(
                  'Both agents can do the same things.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final cluster in _shown)
                    _ClusterTile(
                      cluster: cluster,
                      connected: view.backends,
                      open: _expanded == cluster.key,
                      onToggle: () => setState(
                        () => _expanded = _expanded == cluster.key
                            ? null
                            : cluster.key,
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}

/// No skills — which is a finding, not a failure.
class _EmptySkills extends StatelessWidget {
  const _EmptySkills({required this.backendName});

  final String backendName;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 32, color: context.ink.faint),
          const SizedBox(height: 14),
          Text(
            '$backendName has no skills to show.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.ink.secondary),
          ),
          const SizedBox(height: 8),
          Text(
            'A skill is a SKILL.md the agent can load. Hermes learns them; '
            'OpenClaw reads them from its workspace.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

/// Which agents this view is built from. All live — a skill library has no
/// snapshot half, so there is no age to label.
class _Sources extends StatelessWidget {
  const _Sources({required this.backends});

  final Set<String> backends;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final backend in backends)
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              Icons.cloud_done_outlined,
              size: 14,
              color: context.ink.tertiary,
            ),
            label: Text(
              '$backend · live',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    ),
  );
}

/// Servers that were asked and could not answer.
class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.view});

  final SkillLibraryView view;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.cloud_off_rounded, size: 15, color: Palette.coral),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Could not reach ${view.unreachable.keys.join(", ")} — the '
            'comparison below leaves them out. '
            '${view.unreachable.values.first}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

/// How many skills one agent has and another does not.
class _DivergenceBar extends StatelessWidget {
  const _DivergenceBar({
    required this.count,
    required this.only,
    required this.onToggle,
  });

  final int count;
  final bool only;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
    child: Row(
      children: [
        Icon(Icons.call_split_rounded, size: 15, color: context.ink.tertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$count ${count == 1 ? 'skill is' : 'skills are'} known to one '
            'agent and not the other',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton(
          onPressed: onToggle,
          child: Text(only ? 'Show all' : 'Show only these'),
        ),
      ],
    ),
  );
}

/// One skill, and which agents have it.
class _ClusterTile extends StatelessWidget {
  const _ClusterTile({
    required this.cluster,
    required this.connected,
    required this.open,
    required this.onToggle,
  });

  final SkillCluster cluster;
  final Set<String> connected;
  final bool open;
  final VoidCallback onToggle;

  bool get _hasContent => cluster.entries.any((e) => e.content != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = cluster.best;
    final missing = cluster.missingFrom(connected);
    final showChevron =
        _hasContent || cluster.isShared || best.description.length > 120;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: Icon(
            Icons.auto_awesome_outlined,
            size: 18,
            color: missing.isEmpty ? context.ink.tertiary : Palette.brass,
          ),
          title: Text(best.title),
          subtitle: Text(
            [
              if (missing.isEmpty)
                'both: ${cluster.backends.join(", ")}'
              else
                '${cluster.backends.join(", ")} · not in ${missing.join(", ")}',
              if (best.description.isNotEmpty) best.description,
            ].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          trailing: showChevron
              ? Icon(
                  open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                )
              : null,
          onTap: onToggle,
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in cluster.entries) ...[
                  Row(
                    children: [
                      Text(entry.backendId, style: theme.textTheme.labelSmall),
                      const SizedBox(width: 8),
                      if (!entry.eligible)
                        Text(
                          'off · ${entry.detail}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Palette.coral,
                          ),
                        ),
                      if (entry.filePath case final String path)
                        Expanded(
                          child: Text(
                            path,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (entry.content case final String content)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          content,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      'No content readable from this client.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.ink.faint,
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
