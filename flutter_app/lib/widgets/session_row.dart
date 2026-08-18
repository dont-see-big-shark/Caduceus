/// One session, in a list — shared by the phone's drawer and the Mac sidebar.
library;

import 'package:flutter/material.dart';
import 'package:agent_core/agent_core.dart';

import '../design/components.dart';
import '../design/glass.dart';
import '../design/press.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// A session row.
///
/// 选中态不是高亮色块，是一块更厚的玻璃浮起来 — selection is expressed by the
/// *material*, not by colour. A tinted rectangle is the usual way and it fights
/// the aurora underneath; a thicker sheet with a brighter rim reads as the row
/// lifting toward you, and works identically in light and dark.
class SessionRow extends StatefulWidget {
  const SessionRow({
    required this.session,
    required this.selected,
    required this.unread,
    required this.onTap,
    this.onLongPress,
    this.live = false,
    this.model = '',
    super.key,
  });

  final AgentSession session;
  final bool selected;
  final bool unread;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// A turn is running in this session right now.
  final bool live;

  /// The model this session is on, when it has been opened and the server has
  /// said. Blank for one that has never been opened.
  final String model;

  @override
  State<SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<SessionRow> {
  bool _hovered = false;

  AgentSession get session => widget.session;
  bool get selected => widget.selected;
  bool get unread => widget.unread;
  bool get live => widget.live;

  /// The message count, when the backend actually knows one.
  String _countPrefix() =>
      session.messageCount > 0 ? '${session.messageCount} · ' : '';

  String _meta() {
    if (live) return 'running';
    return widget.model.isEmpty ? 'idle' : widget.model;
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = live
        ? Palette.azure
        : (widget.model.isNotEmpty
              ? Palette.jade
              : context.ink.base.withValues(alpha: .3));

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Semantics(
                label: live ? 'running' : (unread ? 'unread' : ''),
                child: AnimatedScale(
                  scale: _hovered ? 1.25 : 1,
                  duration: const Duration(milliseconds: 80),
                  curve: Motion.standardCurve,
                  child: StatusDot(color: dotColor, pulsing: live, size: 7),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? context.ink.primary
                        : context.ink.secondary,
                  ),
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Palette.jade.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Palette.jade.withValues(alpha: .40),
                    ),
                  ),
                  child: Text(
                    '${session.messageCount > 0 ? session.messageCount : 2}',
                    style: mono(context, size: 10).copyWith(
                      color: Palette.jade,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 15),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _countPrefix() + _meta(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(context, size: 11, opacity: InkLevel.faint),
                  ),
                ),
                if (session.updatedAt != null)
                  Text(
                    relativeAge(session.updatedAt!),
                    style: mono(context, size: 11, opacity: InkLevel.faint),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      // 悬停：行背景 120ms 内变亮. Only a pointer can hover, so this costs a
      // touch device nothing — and on a Mac a list that does not answer the
      // pointer feels like a picture of a list.
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: Pressable(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          haptic: false,
          scale: .98,
          semanticLabel: session.label,
          child: selected
              ? GlassPanel(
                  level: Glass.regular,
                  radius: Radii.mediumAll,
                  child: row,
                )
              // Not a GlassPanel: an unselected row must not open its own
              // backdrop-blur layer. A list of twenty rows would be twenty
              // blurs, which is the single most expensive mistake available in
              // this design. Flat tint only — the sheet under the list is what
              // is already blurring the aurora.
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Motion.standardCurve,
                  decoration: BoxDecoration(
                    borderRadius: Radii.mediumAll,
                    color: context.ink.base.withValues(
                      alpha: _hovered ? .09 : .04,
                    ),
                  ),
                  child: row,
                ),
        ),
      ),
    );
  }
}

/// `2m`, `3h`, `1d` — the design's right-hand column.
///
/// Deliberately coarse: the exact minute a session started is never the
/// question being asked of this column, which is only ever "recent, or not".
String relativeAge(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${(d.inDays / 7).floor()}w';
}
