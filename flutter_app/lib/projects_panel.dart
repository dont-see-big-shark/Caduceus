import 'package:flutter/material.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

import 'l10n/app_localizations.dart';
import 'widgets/panel_frame.dart';

/// Sessions grouped by the project they belong to.
class ProjectsPanel extends StatefulWidget {
  const ProjectsPanel({
    this.embedded = false,
    required this.gateway,
    required this.onOpenSession,
    super.key,
  });

  final HermesGateway gateway;
  final void Function(String sessionId) onOpenSession;

  final bool embedded;

  @override
  State<ProjectsPanel> createState() => _ProjectsPanelState();
}

class _ProjectsPanelState extends State<ProjectsPanel> {
  List<Map<String, dynamic>>? _projects;
  final Map<String, List<Map<String, dynamic>>> _sessions = {};
  String? _expanded;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final tree = await widget.gateway.projectsTree();
      if (!mounted) return;
      setState(
        () => _projects = ((tree['projects'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is GatewayRpcException ? e.message : '$e');
      }
    }
  }

  Future<void> _expand(String id) async {
    if (_expanded == id) {
      setState(() => _expanded = null);
      return;
    }
    setState(() => _expanded = id);
    if (_sessions.containsKey(id)) return;
    try {
      final result = await widget.gateway.projectSessions(id);
      if (!mounted) return;
      setState(
        () => _sessions[id] = ((result['sessions'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is GatewayRpcException ? e.message : '$e');
      }
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
          Expanded(child: Text(l10n?.projects ?? 'Projects')),
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
            : _projects == null
            ? const Center(child: CircularProgressIndicator())
            : _projects!.isEmpty
            ? Center(
                child: Text(
                  l10n?.noProjects ??
                      'No projects — sessions are not grouped on this '
                          'server',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              )
            : ListView(
                children: [
                  for (final project in _projects!) ..._project(project, theme),
                ],
              ),
      ),
      // The glass-card header already carries the close ×; a bottom Close
      // would duplicate it, so there is no action bar in either form.
    );
  }

  List<Widget> _project(Map<String, dynamic> project, ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final id = (project['id'] ?? project['project_id'] ?? '').toString();
    final open = _expanded == id;
    final rows = _sessions[id];
    return [
      ListTile(
        dense: true,
        leading: Icon(open ? Icons.folder_open : Icons.folder, size: 18),
        title: Text(project['name']?.toString() ?? id),
        subtitle: Text(
          [
            if (project['path'] != null) '${project['path']}',
            if (project['session_count'] != null)
              '${project['session_count']} sessions',
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        onTap: id.isEmpty ? null : () => _expand(id),
      ),
      if (open)
        if (rows == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 4, 16, 8),
            child: Text(
              l10n?.noSessionsInProject ?? 'No sessions',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          for (final session in rows)
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.chat_bubble_outline, size: 14),
                title: Text(
                  (session['title'] ?? session['id'] ?? '?').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${session['message_count'] ?? '?'} messages',
                  style: theme.textTheme.bodySmall,
                ),
                onTap: () {
                  final sessionId = session['id']?.toString();
                  if (sessionId == null) return;
                  Navigator.of(context).pop();
                  widget.onOpenSession(sessionId);
                },
              ),
            ),
    ];
  }
}
