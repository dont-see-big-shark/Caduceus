import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'l10n/app_localizations.dart';
import 'widgets/panel_frame.dart';
import 'workspace.dart';

/// Scheduled agent runs.
class JobsPanel extends StatefulWidget {
  const JobsPanel({required this.workspace, this.embedded = false, super.key});

  final Workspace workspace;

  /// Render inside a parent surface (right panel rail) instead of a
  /// dialog/sheet. See [Panel.embedded].
  final bool embedded;

  @override
  State<JobsPanel> createState() => _JobsPanelState();
}

class _JobsPanelState extends State<JobsPanel> {
  List<AgentJob>? _jobs;

  Workspace get _ws => widget.workspace;

  /// Whether this client may schedule anything, as opposed to merely read the
  /// schedule. Two permissions, and on one backend two different scopes.
  bool get _canEdit => _ws.supports(Capability.cronEditing);
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final jobs = await _ws.jobs();
      if (mounted) setState(() => _jobs = jobs);
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    }
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final name = TextEditingController();
    final schedule = TextEditingController(text: '0 9 * * *');
    final prompt = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text(l10n?.newScheduledJob ?? 'New scheduled job'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n?.jobName ?? 'Name',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: schedule,
                decoration: InputDecoration(
                  labelText: l10n?.schedule ?? 'Schedule',
                  helperText:
                      l10n?.scheduleHelper ??
                      'cron expression, e.g. 0 9 * * * for 09:00 daily',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: prompt,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: l10n?.promptToRun ?? 'Prompt to run',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n?.create ?? 'Create'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (name.text.trim().isEmpty || prompt.text.trim().isEmpty) return;
    try {
      await _ws.createJob(
        name: name.text.trim(),
        schedule: schedule.text.trim(),
        prompt: prompt.text.trim(),
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _ws.describeFailure(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Panel(
      embedded: widget.embedded,
      title: Row(
        children: [
          Expanded(child: Text(l10n?.scheduledJobs ?? 'Scheduled jobs')),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: l10n?.reload ?? 'Reload',
          ),
          // Absent where scheduling needs a scope this device was not
          // granted — on OpenClaw every cron mutation is `operator.admin`
          // while listing them is `operator.read`, so a client that can see
          // the schedule cannot necessarily add to it.
          if (_canEdit)
            IconButton(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded, size: 18),
              tooltip: l10n?.newJob ?? 'New job',
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
            : _jobs == null
            ? const Center(child: CircularProgressIndicator())
            : _jobs!.isEmpty
            ? Center(
                child: Text(
                  l10n?.noScheduledJobs ?? 'No scheduled jobs',
                  style: theme.textTheme.bodySmall,
                ),
              )
            : ListView.separated(
                itemCount: _jobs!.length,
                separatorBuilder: (context, _) =>
                    Divider(height: 1, color: context.ink.hairline),
                itemBuilder: (context, i) {
                  final job = _jobs![i];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      job.enabled
                          ? Icons.schedule_rounded
                          : Icons.pause_circle_outline,
                      size: 18,
                    ),
                    title: Text(job.name),
                    subtitle: Text(
                      [
                        job.schedule,
                        job.prompt,
                        // How the last one went, where the backend says. A
                        // schedule that has been failing every morning is the
                        // thing worth knowing on this screen.
                        if (job.lastRunStatus.isNotEmpty)
                          'last: ${job.lastRunStatus}',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
