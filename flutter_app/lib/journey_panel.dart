import 'package:flutter/material.dart';
import 'package:hermes_protocol/hermes_protocol.dart';

import 'design/theme.dart';
import 'l10n/app_localizations.dart';
import 'widgets/panel_frame.dart';

/// What the agent has learned, over time.
class JourneyPanel extends StatefulWidget {
  const JourneyPanel({required this.gateway, super.key});
  final HermesGateway gateway;

  @override
  State<JourneyPanel> createState() => _JourneyPanelState();
}

class _JourneyPanelState extends State<JourneyPanel> {
  LearningJourney? _journey;
  String? _error;
  LearningBucket? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final journey = await widget.gateway.learningJourney();
      if (!mounted) return;
      setState(() {
        _journey = journey;
        _selected =
            journey.buckets
                .where((b) => b.date == _selected?.date)
                .firstOrNull ??
            (journey.buckets.isEmpty ? null : journey.buckets.last);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is GatewayRpcException ? e.message : '$e');
      }
    }
  }

  static Color? _parse(String hex) {
    if (hex.length != 7 || !hex.startsWith('#')) return null;
    final value = int.tryParse(hex.substring(1), radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  Future<void> _openNode(LearningNode node) async {
    final l10n = AppLocalizations.of(context);
    Map<String, dynamic> detail;
    try {
      detail = await widget.gateway.learningDetail(node.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is GatewayRpcException ? e.message : '$e');
      return;
    }
    if (!mounted) return;

    if (detail['ok'] == false) {
      final message =
          detail['message']?.toString() ??
          (l10n?.thisEntryNoLongerAvailable ??
              'This entry is no longer available.');
      await showDialog<void>(
        context: context,
        builder: (context) =>
            Panel(title: Text(node.label), content: Text(message)),
      );
      return;
    }

    final body = (detail['content'] ?? detail['body'] ?? '').toString();
    final controller = TextEditingController(text: body);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => Panel(
        title: Text(node.label),
        content: PanelFrame(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  node.meta,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 10),
              if (body.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    l10n?.thisEntryHasNoContentYet ??
                        'This entry has no content yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('delete'),
            child: Text(
              node.isSkill
                  ? (l10n?.archive ?? 'Archive')
                  : (l10n?.delete ?? 'Delete'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: Text(l10n?.save ?? 'Save'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'save') {
      try {
        await widget.gateway.learningEdit(node.id, controller.text);
      } catch (e) {
        if (mounted) {
          setState(() => _error = e is GatewayRpcException ? e.message : '$e');
        }
        return;
      }
      await _load();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Panel(
        title: Text(
          node.isSkill
              ? (l10n?.archiveSkillTitle ?? 'Archive skill?')
              : (l10n?.deleteMemoryTitle ?? 'Delete memory?'),
        ),
        content: Text(
          node.isSkill
              ? (l10n?.archiveSkillContent(node.label) ??
                    '"${node.label}" is archived on the server and can be restored there.')
              : (l10n?.deleteMemoryContent(node.label) ??
                    '"${node.label}" is removed from the agent\'s memory. This cannot be undone.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              node.isSkill
                  ? (l10n?.archive ?? 'Archive')
                  : (l10n?.delete ?? 'Delete'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.gateway.learningDelete(node.id);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is GatewayRpcException ? e.message : '$e');
      }
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Panel(
      title: Row(
        children: [
          Expanded(child: Text(l10n?.learningJourney ?? 'Learning journey')),
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
            : _journey == null
            ? const Center(child: CircularProgressIndicator())
            : _journey!.buckets.isEmpty
            ? Center(
                child: Text(
                  'Nothing learned yet',
                  style: theme.textTheme.bodySmall,
                ),
              )
            : Column(
                children: [
                  _summary(theme),
                  const SizedBox(height: 8),
                  _timeline(theme),
                  const Divider(height: 20),
                  Expanded(child: _nodes(theme)),
                ],
              ),
      ),
    );
  }

  Widget _summary(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final line in _journey!.summary)
        Text(line, style: theme.textTheme.bodySmall),
      const SizedBox(height: 6),
      Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final category in _journey!.categories)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _parse(category.color) ?? theme.disabledColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(category.label, style: theme.textTheme.bodySmall),
              ],
            ),
        ],
      ),
    ],
  );

  /// Day columns, height proportional to what was learned that day.
  Widget _timeline(ThemeData theme) {
    final busiest = _journey!.buckets.fold<int>(
      1,
      (m, b) => b.total > m ? b.total : m,
    );
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _journey!.buckets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final bucket = _journey!.buckets[i];
          final selected = bucket.date == _selected?.date;
          return InkWell(
            onTap: () => setState(() => _selected = bucket),
            child: SizedBox(
              width: 34,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${bucket.total}', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Container(
                    height: (56 * bucket.total / busiest).clamp(3.0, 56.0),
                    width: selected ? 20 : 14,
                    decoration: BoxDecoration(
                      color: _parse(bucket.color) ?? theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(3),
                      border: selected
                          ? Border.all(color: theme.colorScheme.onSurface)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bucket.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _nodes(ThemeData theme) {
    final bucket = _selected;
    if (bucket == null || bucket.nodes.isEmpty) {
      return Center(
        child: Text('Pick a day', style: theme.textTheme.bodySmall),
      );
    }
    return ListView.separated(
      itemCount: bucket.nodes.length,
      separatorBuilder: (context, _) =>
          Divider(height: 1, color: context.ink.hairline),
      itemBuilder: (context, i) {
        final node = bucket.nodes[i];
        return ListTile(
          dense: true,
          leading: Icon(
            node.isSkill ? Icons.auto_awesome : Icons.psychology_outlined,
            size: 16,
          ),
          title: Text(node.label),
          subtitle: Text(node.meta, style: theme.textTheme.bodySmall),
          trailing: const Icon(Icons.chevron_right, size: 16),
          onTap: () => _openNode(node),
        );
      },
    );
  }
}
