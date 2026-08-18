import 'package:flutter/material.dart';

import '../design/glass.dart';
import '../design/press.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// One row in a [MenuCard].
class MenuItem {
  const MenuItem({
    required this.label,
    this.icon,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.divider = false,
    this.hint,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;

  /// Renders a hairline separator instead of a row.
  final bool divider;

  /// A mono shortcut hint on the right (`⌘K` style).
  final String? hint;
}

/// The shared [MenuAnchor] style for every anchored glass menu: no Material
/// chrome of its own — [MenuCard] draws the glass, so the anchor's default
/// surface, elevation and padding are all switched off.
const anchoredMenuStyle = MenuStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.transparent),
  elevation: WidgetStatePropertyAll(0),
  padding: WidgetStatePropertyAll(EdgeInsets.zero),
  shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
);

/// The design's menu — a compact glass card anchored to the control that
/// opened it, the shape `desktop.html` draws for `more-menu` / `attach-pop` /
/// `model-pop`: ~220 px wide, tight rows, a hairline divider, no full-window
/// surface. Opened with `MenuAnchor` / `showMenu` anchoring, never as a centred
/// dialog.
class MenuCard extends StatelessWidget {
  const MenuCard({
    required this.items,
    this.width = 220,
    this.title,
    this.border = false,
    super.key,
  });

  final List<MenuItem> items;

  /// Matches the design's 220–236 px menus.
  final double width;

  /// Optional mono uppercase heading (`model-pop`'s `.mp-title`).
  final String? title;

  /// Whether to draw the hairline border. Defaults to false for borderless glass.
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GlassPanel(
        level: Glass.thick,
        radius: BorderRadius.circular(16),
        border: border,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: 380),
          child: SingleChildScrollView(
            primary: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title case final title?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 5),
                    child: Text(
                      title.toUpperCase(),
                      style: mono(context, size: 10, opacity: InkLevel.faint),
                    ),
                  ),
                for (final item in items)
                  if (item.divider)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 5,
                      ),
                      child: Divider(height: 1, color: context.ink.hairline),
                    )
                  else
                    _MenuRow(item: item),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Anchors a [MenuCard] to the control that opened it — the design's pop-in
/// menu (`more-menu` / `attach-pop`), never a centred full-window surface.
Future<T?> showMenuAnchor<T>(
  BuildContext context, {
  required GlobalKey anchor,
  required Widget menu,
  Offset offset = const Offset(0, 8),
  double menuWidth = 232,
}) {
  final box = anchor.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return Future.value(null);
  final origin = box.localToGlobal(Offset.zero);
  final size = MediaQuery.sizeOf(context);
  // A negative offset opens the menu *above* the control (`attach-pop` in the
  // design); otherwise it drops below it. Either way the card stays inside
  // the window — never a full-screen surface.
  final above = offset.dy < 0;
  // The anchor is not always on the left. On a phone the attach control sits
  // beside send on the right edge, so a menu dropped at `origin.dx` would
  // extend past the right of the screen. Clamp its left edge with a small
  // gutter; the menu is a fixed-width glass card, so `menuWidth` is enough to
  // keep it fully visible without measuring it first.
  var left = origin.dx;
  final maxLeft = size.width - menuWidth - 8;
  if (maxLeft < 0) {
    left = 0;
  } else if (left > maxLeft) {
    left = maxLeft;
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.exit,
    pageBuilder: (context, _, _) => Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          left: left,
          top: above ? null : origin.dy + offset.dy,
          bottom: above ? size.height - origin.dy + offset.dy : null,
          child: menu,
        ),
      ],
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Pressable(
      onTap: item.enabled ? item.onTap : null,
      child: AnimatedContainer(
        duration: Motion.standard,
        curve: Motion.standardCurve,
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: item.selected
              ? Palette.brass.withValues(alpha: .10)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            if (item.icon case final icon?) ...[
              Icon(
                icon,
                size: 15,
                color: item.selected
                    ? Palette.brass
                    : item.enabled
                    ? ink.secondary
                    : ink.faint,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: item.enabled ? ink.primary : ink.faint,
                ),
              ),
            ),
            if (item.hint case final hint?)
              Text(
                hint,
                style: mono(context, size: 10, opacity: InkLevel.faint),
              ),
          ],
        ),
      ),
    );
  }
}
