import 'package:flutter/material.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

import 'l10n/app_localizations.dart';
import 'widgets/panel_frame.dart';

/// Subagents, spawn limits, saved spawn trees, and account-wide usage.
class AgentsPanel extends StatefulWidget {
  const AgentsPanel({
    required this.gateway,
    this.embedded = false,
    required this.liveSessionId,
    super.key,
  });

  final HermesGateway gateway;
  final String liveSessionId;

  /// Render inside a parent surface (right panel rail) instead of a
  /// dialog/sheet. See [Panel.embedded].
  final bool embedded;

  @override
  State<AgentsPanel> createState() => _AgentsPanelState();
}

class _AgentsPanelState extends State<AgentsPanel> {
  Map<String, dynamic>? _delegation;
  Map<String, dynamic>? _insights;
  List<Map<String, dynamic>>? _trees;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        widget.gateway.delegationStatus(),
        widget.gateway.insights(),
        widget.gateway.spawnTrees(widget.liveSessionId),
      ]);
      if (!mounted) return;
      setState(() {
        _delegation = results[0] as Map<String, dynamic>;
        _insights = results[1] as Map<String, dynamic>;
        _trees = results[2] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.userFacingMessage);
      }
    }
  }

  Future<void> _setPaused(bool paused) async {
    try {
      await widget.gateway.delegationPause(paused: paused);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.userFacingMessage);
      }
    }
  }

  Future<void> _interrupt(Object agent) async {
    final id = agent is Map
        ? (agent['id'] ?? agent['subagent_id'] ?? agent['name'])?.toString()
        : agent.toString();
    if (id == null || id.isEmpty) return;
    try {
      await widget.gateway.subagentInterrupt(id);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.userFacingMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final active = (_delegation?['active'] as List?) ?? const [];
    final paused = _delegation?['paused'] == true;
    return Panel(
      embedded: widget.embedded,
      title: Row(
        children: [
          Expanded(child: Text(l10n?.agents ?? 'Agents')),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: l10n?.reload ?? 'Reload',
          ),
        ],
      ),
      content: PanelFrame(
        child: _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            : _delegation == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  _section(theme, l10n?.delegation ?? 'Delegation'),
                  ListTile(
                    dense: true,
                    title: Text(
                      active.isEmpty
                          ? (l10n?.noSubagentsRunning ?? 'No subagents running')
                          : '${active.length} ${l10n?.subagentsRunning ?? 'subagent(s) running'}',
                    ),
                    subtitle: Text(
                      'depth limit ${_delegation!['max_spawn_depth'] ?? '?'} · '
                      'max concurrent '
                      '${_delegation!['max_concurrent_children'] ?? '?'}'
                      '${_delegation!['paused'] == true ? ' · spawning paused' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  SwitchListTile(
                    dense: true,
                    value: !paused,
                    onChanged: (on) => _setPaused(!on),
                    title: Text(
                      l10n?.allowNewSubagents ?? 'Allow new subagents',
                    ),
                    subtitle: Text(
                      paused
                          ? (l10n?.spawningPaused ??
                                'Spawning is paused — running children continue')
                          : (l10n?.agentMaySpawnChildren ??
                                'The agent may spawn children'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  for (final agent in active)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.account_tree, size: 16),
                      title: Text(
                        '$agent',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip:
                            l10n?.interruptThisSubagent ??
                            'Interrupt this subagent',
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        onPressed: () => _interrupt(agent),
                      ),
                    ),
                  _section(theme, l10n?.savedSpawnTrees ?? 'Saved spawn trees'),
                  if (_trees == null || _trees!.isEmpty)
                    ListTile(
                      dense: true,
                      title: Text(
                        l10n?.noneForThisSession ?? 'None for this session',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  else
                    for (final tree in _trees!)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.hub_outlined, size: 16),
                        title: Text(
                          tree['name']?.toString() ??
                              tree['path']?.toString() ??
                              '?',
                        ),
                        subtitle: Text(
                          '${tree['subagents'] ?? tree['count'] ?? '?'} subagents',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  _section(theme, l10n?.recentActivity ?? 'Recent activity'),
                  ListTile(
                    dense: true,
                    title: Text(
                      '${_insights?['sessions'] ?? '?'} sessions · '
                      '${_insights?['messages'] ?? '?'} messages',
                    ),
                    subtitle: Text(
                      'last ${_insights?['days'] ?? 30} days, across every '
                      'session on this server',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _section(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(title, style: theme.textTheme.labelSmall),
  );
}
