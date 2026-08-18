import 'package:flutter/material.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

import 'design/theme.dart';
import 'l10n/app_localizations.dart';
import 'widgets/panel_frame.dart';

/// Filesystem checkpoints the agent took before editing.
class CheckpointsPanel extends StatefulWidget {
  const CheckpointsPanel({
    required this.gateway,
    required this.liveSessionId,
    super.key,
  });

  final HermesGateway gateway;
  final String liveSessionId;

  @override
  State<CheckpointsPanel> createState() => _CheckpointsPanelState();
}

class _CheckpointsPanelState extends State<CheckpointsPanel> {
  List<Checkpoint>? _checkpoints;
  String? _error;
  String? _selected;
  String? _diff;
  bool _loadingDiff = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await widget.gateway.rollbackList(widget.liveSessionId);
      if (mounted) setState(() => _checkpoints = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.userFacingMessage);
    }
  }

  Future<void> _showDiff(Checkpoint c) async {
    setState(() {
      _selected = c.hash;
      _loadingDiff = true;
      _diff = null;
    });
    try {
      final r = await widget.gateway.rollbackDiff(
        sessionId: widget.liveSessionId,
        hash: c.hash,
      );
      final stat = r['stat']?.toString() ?? '';
      final diff = r['diff']?.toString() ?? '';
      if (mounted) {
        setState(() {
          _diff = [
            if (stat.isNotEmpty) stat,
            if (diff.isNotEmpty) diff,
            if (diff.length >= 4000) '\n… truncated by the server at 4 KB',
            if (stat.isEmpty && diff.isEmpty) 'No changes recorded.',
          ].join('\n');
          _loadingDiff = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _diff = e.userFacingMessage;
          _loadingDiff = false;
        });
      }
    }
  }

  Future<void> _restore(Checkpoint c) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text(l10n?.restoreCheckpointTitle ?? 'Restore checkpoint?'),
        content: Text(
          l10n?.restoreCheckpointMessage(c.timestamp, c.shortHash) ??
              'Files on the server are rewritten to their state at '
                  '${c.timestamp} (${c.shortHash}). Changes made since are lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n?.restoreThisCheckpoint ?? 'Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.gateway.rollbackRestore(
        sessionId: widget.liveSessionId,
        hash: c.hash,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.restored(c.shortHash) ?? 'Restored ${c.shortHash}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.userFacingMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Panel(
      title: Row(
        children: [
          Expanded(child: Text(l10n?.checkpoints ?? 'Checkpoints')),
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
            : _checkpoints == null
            ? const Center(child: CircularProgressIndicator())
            : _checkpoints!.isEmpty
            ? Center(
                child: Text(
                  l10n?.noCheckpoints ??
                      'No checkpoints — the agent has not edited files '
                          'in this session, or checkpointing is off.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              )
            : Row(
                children: [
                  SizedBox(width: 260, child: _list(theme)),
                  const VerticalDivider(width: 1),
                  Expanded(child: _diffPane(theme)),
                ],
              ),
      ),
    );
  }

  Widget _list(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return ListView.separated(
      itemCount: _checkpoints!.length,
      separatorBuilder: (context, _) =>
          Divider(height: 1, color: context.ink.hairline),
      itemBuilder: (context, i) {
        final c = _checkpoints![i];
        return ListTile(
          dense: true,
          selected: c.hash == _selected,
          title: Text(
            c.message.isEmpty ? c.shortHash : c.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${c.shortHash} · ${c.timestamp}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: IconButton(
            tooltip: l10n?.restoreThisCheckpoint ?? 'Restore this checkpoint',
            icon: const Icon(Icons.restore, size: 18),
            onPressed: () => _restore(c),
          ),
          onTap: () => _showDiff(c),
        );
      },
    );
  }

  Widget _diffPane(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    if (_loadingDiff) return const Center(child: CircularProgressIndicator());
    if (_diff == null) {
      return Center(
        child: Text(
          l10n?.selectCheckpointToSeeDiff ??
              'Select a checkpoint to see what it changed',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        _diff!,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }
}
