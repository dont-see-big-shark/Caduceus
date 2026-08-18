import 'package:flutter/material.dart';

import '../design/press.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// One row in a Settings-style master nav.
class MasterNavItem {
  const MasterNavItem({
    required this.icon,
    required this.label,
    this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;

  /// Shown as `label · count`, the way Capabilities shows `Skills · 9`.
  final String? count;
  final bool selected;
  final VoidCallback onTap;
}

/// The left-hand nav of a Settings-style master–detail card: a faint mono
/// group header and pressable rows. This is the exact chrome the Settings
/// page's own nav uses, so any overlay built on it reads as the same surface.
class MasterNav extends StatelessWidget {
  const MasterNav({required this.header, required this.items, super.key});

  final String header;
  final List<MasterNavItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
          child: Text(
            header.toUpperCase(),
            style: mono(context, size: 10, opacity: InkLevel.faint),
          ),
        ),
        for (final item in items) MasterNavRow(item: item),
      ],
    );
  }
}

/// One pressable nav row, shared by every master–detail surface.
class MasterNavRow extends StatelessWidget {
  const MasterNavRow({required this.item, super.key});

  final MasterNavItem item;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: item.label,
    child: Pressable(
      onTap: item.onTap,
      semanticLabel: item.label,
      child: AnimatedContainer(
        duration: Motion.standard,
        curve: Motion.standardCurve,
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: Radii.smallAll,
          color: item.selected
              ? context.ink.base.withValues(alpha: .10)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 15,
              color: item.selected ? Palette.brass : context.ink.tertiary,
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                item.count == null
                    ? item.label
                    : '${item.label} · ${item.count}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: item.selected
                      ? context.ink.primary
                      : context.ink.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
