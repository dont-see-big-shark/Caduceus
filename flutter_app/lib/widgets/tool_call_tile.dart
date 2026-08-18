import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/glass.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../workspace.dart';
import 'message_bubble.dart';

/// One tool invocation, as it appears in a turn's timeline.
///
/// The surrounding `ConsoleToolStrip` that used to live here is gone: it
/// listed every tool call of the turn in one pane, beside a separate pane of
/// reasoning, which threw away the order the two happened in. `TurnTimeline`
/// renders both in sequence and reuses this tile for the tool half.
class ToolCallTile extends StatelessWidget {
  const ToolCallTile({required this.call, super.key});
  final ToolCall call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The query, when there is one. `context` reads "Searching the web for X"
    // while it runs; once args arrive the query itself is the useful line, and
    // the hit count says whether the search found anything.
    final query = call.query;
    final subtitle =
        query ??
        (call.context.isNotEmpty
            ? call.context
            : (call.args?.values.join(' ') ?? ''));
    final hits = call.webResults.length;

    // 运行中光点呼吸，完成瞬间变绿. A spinner says only "waiting"; a lamp that
    // settles says which of the two states it ended in, and costs no width.
    final dotColor = !call.done
        ? Palette.brass
        : call.failed
        ? Palette.coral
        : Palette.jade;

    return GlassPanel(
      level: Glass.thin,
      radius: Radii.mediumAll,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ExpansionTile(
        dense: true,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        iconColor: context.ink.faint,
        collapsedIconColor: context.ink.faint,
        leading: Semantics(
          label: call.done ? (call.failed ? 'failed' : 'succeeded') : 'running',
          child: SizedBox(
            width: 18,
            height: 18,
            child: Center(
              child: StatusDot(color: dotColor, pulsing: !call.done),
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                call.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: context.ink.primary),
              ),
            ),
            if (hits > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '$hits result${hits == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 11, color: context.ink.faint),
                ),
              ),
            const Spacer(),
            // Elapsed time is a machine fact, so it is mono and right-aligned
            // — a column of times you can compare down the timeline.
            if (call.done)
              Text(
                '${call.durationSeconds.toStringAsFixed(1)}s',
                style: mono(context, size: 11, opacity: InkLevel.faint),
              ),
          ],
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, size: 11, opacity: InkLevel.tertiary),
                ),
              ),
        children: [
          // Search hits first: what a search *found* is the point of it, and
          // reading only result.output threw all of this away.
          for (final hit in call.webResults)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    hit.title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hit.url.isNotEmpty)
                    Text(
                      hit.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (hit.snippet.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hit.snippet,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (call.output != null && call.output!.isNotEmpty) ...[
            if (_isImageString(call.output!))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ChatImageView(src: call.output!),
              )
            else
              _OutputPane(text: call.output!, theme: theme),
          ],
          if (call.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                call.error!,
                style: TextStyle(color: dangerInk(context)),
              ),
            ),
        ],
      ),
    );
  }

  static bool _isImageString(String s) {
    final clean = s.trim().toLowerCase().split('?').first.split('#').first;
    return clean.startsWith('data:image/') ||
        clean.endsWith('.png') ||
        clean.endsWith('.jpg') ||
        clean.endsWith('.jpeg') ||
        clean.endsWith('.gif') ||
        clean.endsWith('.webp') ||
        clean.endsWith('.svg') ||
        clean.endsWith('.bmp');
  }
}

/// Tool output, capped and scrollable with a mouse, plain and tall on touch.
///
/// A capped scroll pane nested inside the timeline's own scroll view is a trap
/// on a phone: a drag that lands on the output scrolls the output rather than
/// the conversation, with nothing to say which one is about to move. Long
/// output on touch is truncated instead, with the tail kept — the end of a
/// command's output is the part worth reading.
class _OutputPane extends StatelessWidget {
  const _OutputPane({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  static const _touchLimit = 1200;

  @override
  Widget build(BuildContext context) {
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final style = mono(context, size: 11, opacity: InkLevel.secondary);

    // Opaque, not glass: this is output to be *read*, and the rule is that
    // reading matter lands on slate.
    return SlatePanel(
      radius: Radii.smallAll,
      opacity: .55,
      padding: const EdgeInsets.all(10),
      child: SizedBox(
        width: double.infinity,
        child: touch
            ? SelectableText(
                text.length <= _touchLimit
                    ? text
                    : '…${text.substring(text.length - _touchLimit)}',
                style: style,
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: SelectableText(text, style: style),
                ),
              ),
      ),
    );
  }
}
