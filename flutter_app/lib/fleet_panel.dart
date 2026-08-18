import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import 'backend_pool.dart';
import 'connection_store.dart';
import 'design/components.dart';
import 'design/glass.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'widgets/panel_frame.dart';
import 'workspace.dart';

/// The fleet — every agent, and the edges between them.
///
/// `AGENT_GRAPH.md`'s relationship layer. The memory and skills bridges
/// answer "what does one agent have" one cluster at a time; this panel
/// projects the same data back into a view organised by *agent*, so one
/// screen says of every saved server: who is connected, what it knows, what
/// it can do, what it alone has, what it is missing — and offers the push
/// that closes the gap where the target can receive one.
///
/// On a phone the panel is a bottom sheet, so the three depths (roster →
/// agent detail → one item) navigate inside the sheet rather than stacking
/// routes on top of it — a route over a sheet is how a phone gets a stack of
/// sheets that each need pulling down.
class FleetPanel extends StatefulWidget {
  const FleetPanel({
    required this.workspace,
    this.peers = MemoryPeers.none,
    this.embedded = false,
    this.store,
    super.key,
  });

  final Workspace workspace;

  /// Already-open tabs the bridges can ask without a handshake.
  final MemoryPeers peers;

  /// Saved-server store. Injectable for tests; the real store by default.
  final ConnectionStore? store;

  /// Render inside a parent surface (right panel rail) instead of a
  /// dialog/sheet. See [Panel.embedded].
  final bool embedded;

  @override
  State<FleetPanel> createState() => _FleetPanelState();
}

/// The order the memory sections appear in, matching the memory panel.
const _kindLabels = <MemoryKind, String>{
  MemoryKind.persona: 'Who it thinks we are',
  MemoryKind.fact: 'What it knows',
  MemoryKind.preference: 'How you like to work',
  MemoryKind.project: 'What you are working on',
  MemoryKind.skill: 'What it has learned to do',
};

class _FleetPanelState extends State<FleetPanel> {
  AgentGraph? _graph;
  String? _error;
  String? _notice;
  bool _loading = true;
  bool _reaching = false;
  bool _pushing = false;

  // The panel's own navigation. A phone sheet must not stack routes, so the
  // three depths live in state and the title's back button unwinds them.
  String? _agentId;
  MemoryCluster? _memoryItem;
  SkillCluster? _skillItem;

  Workspace get _ws => widget.workspace;

  bool get _inCrossView => _memoryItem != null || _skillItem != null;

  bool get _inAgentDetail => _agentId != null && !_inCrossView;

  AgentNode? get _agent => _graph?.node(_agentId ?? '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reaches out on every open and every refresh.
  ///
  /// Unlike the memory panel, whose default read is the connected server, the
  /// fleet *is* the reach-out — its whole point is the other servers. The
  /// cost (a handshake each, and on OpenClaw a pairing check) is what the
  /// person is here to pay.
  Future<void> _load() async {
    setState(() {
      _error = null;
      _notice = null;
      _loading = true;
      _reaching = true;
    });
    try {
      final saved = await (widget.store ?? ConnectionStore()).list();
      final memory = await _ws.memoryView(reachOut: true, peers: widget.peers);
      final skills = await _ws.skillView(reachOut: true, peers: widget.peers);
      final graph = buildAgentGraph(
        savedLabels: {for (final c in saved) c.backendId: c.displayLabel},
        currentBackendId: _ws.backend.id,
        currentBackendLabel: _ws.backend.displayName,
        backendLabels: {
          for (final entry in widget.peers.backends.entries)
            entry.key: entry.value.displayName,
        },
        memory: memory.clusters,
        skills: skills.clusters,
        liveBackends: {...memory.liveBackendIds, ...skills.liveBackendIds},
        unreachable: {...memory.unreachable, ...skills.unreachable},
      );
      if (!mounted) return;
      setState(() {
        _graph = graph;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _ws.describeFailure(e);
          _loading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _reaching = false);
    }
  }

  void _openAgent(String backendId) => setState(() {
    _agentId = backendId;
    _memoryItem = null;
    _skillItem = null;
  });

  void _openMemory(MemoryCluster cluster) => setState(() {
    _memoryItem = cluster;
    _skillItem = null;
  });

  void _openSkill(SkillCluster cluster) => setState(() {
    _skillItem = cluster;
    _memoryItem = null;
  });

  void _back() {
    if (_memoryItem != null || _skillItem != null) {
      setState(() {
        _memoryItem = null;
        _skillItem = null;
      });
    } else if (_agentId != null) {
      setState(() => _agentId = null);
    }
  }

  String _labelFor(String backendId) {
    final node = _graph?.node(backendId);
    if (node != null) return node.label;
    if (backendId == _ws.backend.id) return _ws.backend.displayName;
    return backendId;
  }

  /// The backend when it is already in hand — the connected one or a tab.
  AgentBackend? _backendFor(String backendId) {
    if (backendId == _ws.backend.id) return _ws.backend;
    return widget.peers.backends[backendId];
  }

  /// Whether an already-connected target can take a new memory at all.
  bool _canReceive(String backendId) {
    final backend = _backendFor(backendId);
    if (backend == null) return false;
    return backend.supports(Capability.memoryWrite) &&
        backend.supportedMemoryOps.contains(MemoryOp.add);
  }

  Future<MemoryWriteResult?> _applyTo(
    String targetId,
    List<MemoryChange> changes,
  ) async {
    if (targetId == _ws.backend.id) {
      // The full workspace path: ledger record, persona backup, re-read.
      return _ws.applyMemory(changes);
    }
    final tab = widget.peers.backends[targetId];
    if (tab != null) {
      // Already open — no handshake, and the write goes straight to it.
      return tab.applyMemory(changes);
    }
    // Saved but not open: pay the handshake once, write, and close. A push
    // is a deliberate act, so a temporary connection is the honest price.
    final pool = BackendPool();
    try {
      await pool.connectAll(
        except: {?_ws.connectionId, ...widget.peers.openConnectionIds},
      );
      final target = pool.usable
          .where((p) => p.connection.backendId == targetId)
          .firstOrNull;
      if (target == null) return null;
      return await target.backend!.applyMemory(changes);
    } finally {
      await pool.dispose();
    }
  }

  /// Pushes one memory cluster to [targetId].
  ///
  /// The same path the memory panel's push takes — `MemoryOp.add` on the
  /// cluster's best entry, per-change refusals reported inline — with the
  /// target chosen from the relationship instead of being "the agent I am
  /// looking at".
  Future<void> _pushMemory(MemoryCluster cluster, String targetId) async {
    final targetLabel = _labelFor(targetId);
    final connected = _backendFor(targetId);
    if (connected != null && !_canReceive(targetId)) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Panel(
          title: Text('$targetLabel cannot take this memory'),
          content: const Text(
            'This server has no way to add a memory from this client. '
            'Hermes has no learning.add; OpenClaw needs operator.admin.',
          ),
        ),
      );
      return;
    }

    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text('Teach $targetLabel this memory?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This is written into a block this app owns in the '
                  "agent's memory file. Nothing you or the agent wrote "
                  'outside that block is touched.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Text(
                  '+ ${cluster.best.label}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Teach it'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    setState(() {
      _pushing = true;
      _notice = null;
    });
    try {
      final result = await _applyTo(targetId, [
        MemoryChange(MemoryOp.add, cluster.best),
      ]);
      if (!mounted) return;
      if (result == null) {
        setState(
          () => _notice = 'Could not reach $targetLabel to push this memory.',
        );
      } else if (result.refused.isNotEmpty) {
        // Every refusal is reported, inline rather than silently. A push
        // that half-worked is how a person comes to believe an agent knows
        // something it does not.
        setState(
          () => _notice = result.refused
              .map((o) => '${o.change.entry.label}: ${o.detail}')
              .join('\n'),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _notice = _ws.describeFailure(e));
    } finally {
      if (mounted) setState(() => _pushing = false);
      await _load();
    }
  }

  /// How a skill would reach [targetId], in words.
  ///
  /// Skills are registry installs, not content pushes, and publishing is a
  /// human act — `SKILLS_BRIDGE.md` §7. The graph says what a skill is and
  /// how it would get there; it does not offer a button that can only be
  /// refused.
  String _skillGuidance(String targetId) {
    switch (targetId) {
      case SavedConnection.hermes:
        return 'Hermes installs from the skills.sh / GitHub registry — '
            'publish it there first (skills.manage install).';
      case SavedConnection.openclaw:
        return 'OpenClaw installs from ClawHub with operator.admin, or from '
            'a SKILL.md placed in workspace/skills/ on the NAS.';
      default:
        return 'This skill reaches $targetId through its registry.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      embedded: widget.embedded,
      title: Row(
        children: [
          if (_inCrossView || _inAgentDetail)
            IconButton(
              onPressed: _back,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
            ),
          const Expanded(child: Text('Fleet')),
          if (_reaching)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            onPressed: _reaching ? null : _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: 'Reload',
          ),
        ],
      ),
      content: PanelFrame(
        child: switch ((_error, _loading, _graph)) {
          (final String message, _, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
          (_, true, _) => const Center(child: CircularProgressIndicator()),
          (_, _, null) => const Center(child: CircularProgressIndicator()),
          (_, _, final AgentGraph graph) => switch ((
            _inCrossView,
            _inAgentDetail,
          )) {
            (true, _) => _ItemCrossView(
              state: this,
              graph: graph,
              memoryItem: _memoryItem,
              skillItem: _skillItem,
            ),
            (false, true) => _AgentDetailView(
              state: this,
              graph: graph,
              node: _agent!,
            ),
            _ => _RosterView(state: this, graph: graph),
          },
        },
      ),
    );
  }
}

/// The first depth: one card per agent, and the edge between them.
class _RosterView extends StatelessWidget {
  const _RosterView({required this.state, required this.graph});

  final _FleetPanelState state;
  final AgentGraph graph;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PresenceChips(nodes: graph.nodes),
        if (graph.unreachable.isNotEmpty)
          _UnreachableBanner(unreachable: graph.unreachable),
        if (state._notice != null) _NoticeBanner(notice: state._notice!),
        if (graph.links.isNotEmpty)
          _LinkCard(link: graph.links.first, nodes: graph.nodes),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // Two cards side by side only where there is room to read both.
              // A phone is never there; a Mac panel usually is.
              final wide = box.maxWidth >= 560;
              final cards = [
                for (final node in graph.nodes)
                  _AgentCard(
                    node: node,
                    onTap: () => state._openAgent(node.backendId),
                  ),
              ];
              if (wide && cards.length > 1) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cards.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: i == 0 ? 16 : 6,
                            right: i == cards.length - 1 ? 16 : 6,
                            bottom: 12,
                          ),
                          child: cards[i],
                        ),
                      ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                children: cards,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One agent: presence, what it holds, what it alone has, what it is missing.
class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.node, required this.onTap});

  final AgentNode node;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presence = _presenceFor(node.presence);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        level: Glass.regular,
        radius: Radii.mediumAll,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: Radii.mediumAll,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusDot(
                        color: presence.color,
                        pulsing: presence.pulsing,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          node.label,
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (node.isLone)
                        Tooltip(
                          message: 'Holds something no other agent does',
                          child: Icon(
                            Icons.waves_rounded,
                            size: 15,
                            color: Palette.brass,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    presence.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: presence.color,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${node.memoryEntryCount} memories · '
                    '${node.skillCount} skills',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (node.uniqueMemory > 0 || node.uniqueSkills > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'only here · ${node.uniqueMemory} memories · '
                        '${node.uniqueSkills} skills',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Palette.brassLight,
                        ),
                      ),
                    ),
                  if (node.missingMemoryCount > 0 ||
                      node.missingSkillsCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'missing · ${node.missingMemoryCount} memories · '
                        '${node.missingSkillsCount} skills',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Palette.coralText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The edge between a pair: how much they agree, and what only each side has.
class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link, required this.nodes});

  final AgentLink link;
  final List<AgentNode> nodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = nodes.firstWhere(
      (n) => n.backendId == link.a,
      orElse: () => nodes.first,
    );
    final b = nodes.firstWhere(
      (n) => n.backendId == link.b,
      orElse: () => nodes.first,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: GlassPanel(
        level: Glass.thin,
        radius: Radii.mediumAll,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${a.label} ↔ ${b.label}',
                    style: theme.textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.hub_outlined, size: 15, color: context.ink.tertiary),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${link.sharedMemory} facts shared · '
              '${link.sharedSkills} skills shared',
              style: theme.textTheme.bodySmall,
            ),
            if (link.aOnlyMemory > 0 || link.aOnlySkills > 0)
              Text(
                'only ${a.label}: ${link.aOnlyMemory} memories · '
                '${link.aOnlySkills} skills',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.ink.secondary,
                ),
              ),
            if (link.bOnlyMemory > 0 || link.bOnlySkills > 0)
              Text(
                'only ${b.label}: ${link.bOnlyMemory} memories · '
                '${link.bOnlySkills} skills',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.ink.secondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The second depth: one agent's knows / can-do / missing.
class _AgentDetailView extends StatelessWidget {
  const _AgentDetailView({
    required this.state,
    required this.graph,
    required this.node,
  });

  final _FleetPanelState state;
  final AgentGraph graph;
  final AgentNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presence = _presenceFor(node.presence);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Row(
          children: [
            StatusDot(color: presence.color, pulsing: presence.pulsing),
            const SizedBox(width: 8),
            Expanded(
              child: Text(node.label, style: theme.textTheme.titleMedium),
            ),
            if (node.isLone)
              Icon(Icons.waves_rounded, size: 16, color: Palette.brass),
          ],
        ),
        Text(
          presence.label,
          style: theme.textTheme.labelSmall?.copyWith(color: presence.color),
        ),
        const SizedBox(height: 8),
        Text(
          '${node.memoryEntryCount} memories · ${node.skillCount} skills · '
          '${node.uniqueMemory} only here · ${node.uniqueSkills} skills only '
          'here',
          style: theme.textTheme.bodySmall?.copyWith(
            color: context.ink.secondary,
          ),
        ),
        if (state._notice != null) ...[
          const SizedBox(height: 6),
          _NoticeBanner(notice: state._notice!),
        ],
        if (node.missingMemory.isNotEmpty || node.missingSkills.isNotEmpty) ...[
          _SectionHeader(
            'Missing',
            count: node.missingMemoryCount + node.missingSkillsCount,
          ),
          for (final cluster in node.missingMemory)
            _MissingMemoryTile(state: state, cluster: cluster, node: node),
          for (final cluster in node.missingSkills)
            _MissingSkillTile(state: state, cluster: cluster, node: node),
        ],
        if (node.memory.isNotEmpty) ...[
          _SectionHeader('Knows', count: node.memory.length),
          for (final kind in _kindLabels.keys)
            if (node.memory.any((c) => c.best.kind == kind)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
                child: Text(
                  _kindLabels[kind]!.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              for (final cluster in node.memory.where(
                (c) => c.best.kind == kind,
              ))
                _ExpandableMemoryTile(cluster: cluster),
            ],
        ],
        if (node.skills.isNotEmpty) ...[
          _SectionHeader('Can do', count: node.skills.length),
          for (final cluster in node.skills)
            _ExpandableSkillTile(cluster: cluster, connected: {node.backendId}),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
    child: Text(
      '$title · $count',
      style: Theme.of(context).textTheme.titleSmall,
    ),
  );
}

/// A memory another agent has and this one does not, with the push.
class _MissingMemoryTile extends StatelessWidget {
  const _MissingMemoryTile({
    required this.state,
    required this.cluster,
    required this.node,
  });

  final _FleetPanelState state;
  final MemoryCluster cluster;
  final AgentNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = cluster.backends.join(', ');
    final canPush =
        state._canReceive(node.backendId) ||
        state._backendFor(node.backendId) == null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.add_box_outlined, size: 18, color: Palette.brass),
      title: Text(
        cluster.best.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('known to $who', style: theme.textTheme.bodySmall),
      trailing: canPush
          ? TextButton(
              onPressed: state._pushing
                  ? null
                  : () => state._pushMemory(cluster, node.backendId),
              child: Text(
                state._pushing ? 'Pushing…' : 'Teach',
                style: theme.textTheme.labelMedium,
              ),
            )
          : null,
      onTap: () => state._openMemory(cluster),
    );
  }
}

/// A skill another agent has and this one does not — read + guidance.
class _MissingSkillTile extends StatelessWidget {
  const _MissingSkillTile({
    required this.state,
    required this.cluster,
    required this.node,
  });

  final _FleetPanelState state;
  final SkillCluster cluster;
  final AgentNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.auto_awesome_outlined,
        size: 18,
        color: Palette.brass,
      ),
      title: Text(
        cluster.best.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'known to ${cluster.backends.join(", ")} · '
        '${state._skillGuidance(node.backendId)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      onTap: () => state._openSkill(cluster),
    );
  }
}

/// A memory this agent has, expandable to its full text.
class _ExpandableMemoryTile extends StatefulWidget {
  const _ExpandableMemoryTile({required this.cluster});

  final MemoryCluster cluster;

  @override
  State<_ExpandableMemoryTile> createState() => _ExpandableMemoryTileState();
}

class _ExpandableMemoryTileState extends State<_ExpandableMemoryTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cluster = widget.cluster;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            cluster.best.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            cluster.isShared
                ? 'also in ${cluster.backends.join(", ")}'
                : 'only here',
            style: theme.textTheme.bodySmall,
          ),
          trailing: Icon(
            _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 18,
          ),
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
            child: SelectableText(
              cluster.best.text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.ink.secondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// A skill this agent has, expandable to eligibility and content.
class _ExpandableSkillTile extends StatefulWidget {
  const _ExpandableSkillTile({required this.cluster, required this.connected});

  final SkillCluster cluster;
  final Set<String> connected;

  @override
  State<_ExpandableSkillTile> createState() => _ExpandableSkillTileState();
}

class _ExpandableSkillTileState extends State<_ExpandableSkillTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cluster = widget.cluster;
    final best = cluster.best;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(best.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            best.description.isEmpty
                ? (cluster.isShared
                      ? 'also in ${cluster.backends.join(", ")}'
                      : 'only here')
                : best.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          trailing: Icon(
            _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 18,
          ),
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in cluster.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          entry.backendId,
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(width: 8),
                        if (!entry.eligible)
                          Expanded(
                            child: Text(
                              'off · ${entry.detail}',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Palette.coralText,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (best.content case final String content)
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
              ],
            ),
          ),
      ],
    );
  }
}

/// The third depth: one item, and which agents have it.
class _ItemCrossView extends StatelessWidget {
  const _ItemCrossView({
    required this.state,
    required this.graph,
    required this.memoryItem,
    required this.skillItem,
  });

  final _FleetPanelState state;
  final AgentGraph graph;
  final MemoryCluster? memoryItem;
  final SkillCluster? skillItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = {for (final n in graph.nodes) n.backendId};
    final holders = memoryItem?.backends ?? skillItem!.backends;
    final missing = memoryItem?.missingFrom(all) ?? skillItem!.missingFrom(all);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          memoryItem?.best.label ?? skillItem!.best.title,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        if (memoryItem case final MemoryCluster memory)
          Text(
            memory.best.text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.ink.secondary,
            ),
          )
        else if (skillItem!.best.description.isNotEmpty)
          Text(
            skillItem!.best.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.ink.secondary,
            ),
          ),
        const SizedBox(height: 14),
        _WhoChip(
          icon: Icons.check_circle_outline_rounded,
          iconColor: Palette.jade,
          label: 'Has it',
          ids: holders,
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 8),
          _WhoChip(
            icon: Icons.remove_circle_outline_rounded,
            iconColor: Palette.coral,
            label: 'Does not have it',
            ids: missing,
          ),
        ],
        for (final id in missing)
          if (graph.unreachable.containsKey(id))
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 24),
              child: Text(
                '${graph.node(id)?.label ?? id} could not be asked '
                '(${graph.unreachable[id]})',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.ink.faint,
                ),
              ),
            ),
        if (memoryItem != null)
          for (final id in missing)
            if (!graph.unreachable.containsKey(id))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: state._canReceive(id)
                    ? FilledButton(
                        onPressed: state._pushing
                            ? null
                            : () => state._pushMemory(memoryItem!, id),
                        child: Text(
                          state._pushing
                              ? 'Pushing…'
                              : 'Teach ${graph.node(id)?.label ?? id}',
                        ),
                      )
                    : Text(
                        '${graph.node(id)?.label ?? id} cannot take this '
                        'memory from the client.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.ink.faint,
                        ),
                      ),
              )
            else
              for (final id in missing)
                if (!graph.unreachable.containsKey(id))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      state._skillGuidance(id),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.ink.secondary,
                      ),
                    ),
                  ),
      ],
    );
  }
}

/// One row of "who has it / who does not", as labelled chips.
class _WhoChip extends StatelessWidget {
  const _WhoChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.ids,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Set<String> ids;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(icon, size: 15, color: iconColor),
        Text(label, style: theme.textTheme.labelMedium),
        for (final id in ids)
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(id, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// Every node's presence, as chips — the fleet's vital signs.
class _PresenceChips extends StatelessWidget {
  const _PresenceChips({required this.nodes});

  final List<AgentNode> nodes;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final node in nodes)
          Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(
              Icons.cloud_done_outlined,
              size: 14,
              color: _presenceFor(node.presence).color,
            ),
            label: Text(
              '${node.label} · ${_presenceFor(node.presence).label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    ),
  );
}

/// Servers that were asked and could not answer, in the bridges' words.
class _UnreachableBanner extends StatelessWidget {
  const _UnreachableBanner({required this.unreachable});

  final Map<String, String> unreachable;

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
            'Could not reach ${unreachable.keys.join(", ")} — the fleet '
            'below leaves them out. ${unreachable.values.first}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

/// A write refusal, shown inline rather than blanking the panel.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.notice});

  final String notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: Palette.coral),
          const SizedBox(width: 8),
          Expanded(child: Text(notice, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

({Color color, bool pulsing, String label}) _presenceFor(
  AgentPresence presence,
) {
  switch (presence) {
    case AgentPresence.live:
      return (color: Palette.jade, pulsing: true, label: 'live');
    case AgentPresence.unreachable:
      return (color: Palette.coral, pulsing: false, label: 'unreachable');
    case AgentPresence.saved:
      return (color: Colors.grey, pulsing: false, label: 'offline');
  }
}
