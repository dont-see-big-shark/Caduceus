import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'l10n/app_localizations.dart';
import 'widgets/panel_frame.dart';
import 'workspace.dart';

/// What the agent started and left running.
class ProcessesPanel extends StatefulWidget {
  const ProcessesPanel({
    required this.workspace,
    this.embedded = false,
    required this.sessionId,
    super.key,
  });

  final Workspace workspace;
  final String sessionId;

  /// Render inside a parent surface (right panel rail) instead of a
  /// dialog/sheet. See [Panel.embedded].
  final bool embedded;

  @override
  State<ProcessesPanel> createState() => _ProcessesPanelState();
}

class _ProcessesPanelState extends State<ProcessesPanel> {
  List<AgentTask>? _tasks;
  String? _error;
  String? _expanded;

  Workspace get _ws => widget.workspace;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final tasks = await _ws.tasks(widget.sessionId);
      if (mounted) setState(() => _tasks = tasks);
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    }
  }

  Future<void> _stop(AgentTask task) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text(l10n?.stopThisTitle ?? 'Stop this?'),
        content: Text(task.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n?.stop ?? 'Stop'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _ws.stopTask(widget.sessionId, task.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    }
  }

  Future<void> _stopAll() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text(l10n?.stopAllProcessesTitle ?? 'Stop all processes?'),
        content: Text(
          l10n?.stopAllProcessesMessage ??
              'Every background process on the server is killed, including ones '
                  'started by other sessions and not listed here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n?.stopAll ?? 'Stop all'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _ws.stopAllTasks();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    }
  }

  static String _age(DateTime? since) {
    if (since == null) return '';
    final seconds = DateTime.now().difference(since).inSeconds;
    if (seconds < 0) return '';
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Panel(
      embedded: widget.embedded,
      title: Row(
        children: [
          Expanded(
            child: Text(l10n?.backgroundProcesses ?? 'Background processes'),
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: l10n?.reload ?? 'Reload',
          ),
          if (_ws.supports(Capability.serverMaintenance) &&
              (_tasks?.any((t) => t.canStop) ?? false))
            TextButton(
              onPressed: _stopAll,
              child: Text(
                l10n?.stopAll ?? 'Stop all',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      content: PanelFrame(
        child: switch ((_error, _tasks)) {
          (final String message, _) => Center(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          (_, null) => const Center(child: CircularProgressIndicator()),
          (_, final List<AgentTask> tasks) when tasks.isEmpty => Center(
            child: Text(
              l10n?.nothingRunning ?? 'Nothing running',
              style: theme.textTheme.bodySmall,
            ),
          ),
          (_, final List<AgentTask> tasks) => ListView.separated(
            itemCount: tasks.length,
            separatorBuilder: (context, _) =>
                Divider(height: 1, color: context.ink.hairline),
            itemBuilder: (context, i) => _tile(tasks[i], theme),
          ),
        },
      ),
    );
  }

  Widget _tile(AgentTask task, ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final open = _expanded == task.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: Icon(
            task.canStop
                ? Icons.play_circle_outline
                : Icons.check_circle_outline,
            size: 18,
            color: task.canStop ? theme.colorScheme.primary : null,
          ),
          title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              task.status,
              _age(task.startedAt),
              task.detail,
            ].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (task.outputTail.isNotEmpty)
                IconButton(
                  tooltip: open
                      ? (l10n?.hideOutput ?? 'Hide output')
                      : (l10n?.showOutput ?? 'Show output'),
                  icon: Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _expanded = open ? null : task.id),
                ),
              if (task.canStop)
                IconButton(
                  tooltip: l10n?.stop ?? 'Stop',
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  onPressed: () => _stop(task),
                ),
            ],
          ),
        ),
        if (open)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 200),
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: .4,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                task.outputTail,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }
}
