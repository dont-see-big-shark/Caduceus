/// The parts every settings screen is built from.
///
/// The design draws settings as a list of *groups*, each a tinted glyph tile,
/// a label, the value it currently holds, and a chevron into a second level.
/// The value on the row is the point: 审批 · 仅写操作 answers the question
/// without opening anything, and a settings screen you rarely have to open is
/// a better one.
library;

import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/glass.dart';
import '../design/press.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// A row that leads somewhere.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.tint,
    required this.label,
    this.value,
    this.onTap,
    this.trailing,
    this.selected = false,
    super.key,
  });

  final IconData icon;

  /// The glyph tile's colour. The design gives each group its own so the list
  /// is scannable by colour before it is read — the one place in this app
  /// where colour carries identity rather than state.
  final Color tint;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// On a Mac the master list keeps the open group marked.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          _GlyphTile(icon: icon, tint: tint),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          if (value case final value?) ...[
            const SizedBox(width: 10),
            // Flexible, not fixed: a model id is long, the label is short, and
            // at a raised text size one of them has to give way. It is this
            // one — the label says what the row is.
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: context.ink.tertiary),
              ),
            ),
          ],
          if (trailing case final trailing?) ...[
            const SizedBox(width: 8),
            trailing,
          ] else if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: context.ink.faint,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return Pressable(
      onTap: onTap,
      semanticLabel: value == null ? label : '$label, $value',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: Radii.mediumAll,
          color: selected
              ? context.ink.base.withValues(alpha: .07)
              : Colors.transparent,
        ),
        child: body,
      ),
    );
  }
}

/// The rounded-square behind a settings glyph.
class _GlyphTile extends StatelessWidget {
  const _GlyphTile({required this.icon, required this.tint});

  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      borderRadius: Radii.smallAll,
      color: tint.withValues(alpha: .16),
      border: Border.all(color: tint.withValues(alpha: .28)),
    ),
    child: Icon(
      icon,
      size: 16,
      color: statusInk(
        tint,
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
    ),
  );
}

/// The design's `page-title`: the page name and its one-line job, at the top
/// of every settings page.
class SettingsPageHeader extends StatelessWidget {
  const SettingsPageHeader({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 720) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          if (subtitle case final subtitle?) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.ink.tertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A titled block of rows on one sheet of glass.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 9),
          child: Eyebrow(title),
        ),
        GlassPanel(
          level: Glass.thin,
          radius: Radii.largeAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: children),
          ),
        ),
      ],
    ),
  );
}

/// The top strip of a settings screen — one row, matching the console's.
///
/// Not an [AppBar]: Material draws a filled surface with its own elevation
/// tint, which on this design is an opaque grey band in front of the aurora.
class SettingsBar extends StatelessWidget {
  const SettingsBar({
    required this.title,
    this.crumb,
    this.onBack,
    this.trailing,
    super.key,
  });

  final String title;

  /// The 设置 › 审批 breadcrumb. Shown only where there is room for it.
  final String? crumb;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: Row(
      children: [
        if (onBack != null)
          Tooltip(
            message: 'Back',
            child: Pressable(
              onTap: onBack,
              semanticLabel: 'Back',
              child: SizedBox(
                width: 52,
                height: 52,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 17,
                  color: context.ink.secondary,
                ),
              ),
            ),
          )
        else
          const SizedBox(width: 14),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (crumb case final crumb?) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: context.ink.faint,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    crumb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: context.ink.tertiary),
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
        const SizedBox(width: 10),
      ],
    ),
  );
}

/// One choice out of a few, as the design draws it: a full-width row with a
/// tick, not a radio button.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
    this.icon = Icons.check_rounded,
    this.tint = Palette.jade,
    super.key,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback? onTap;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    semanticLabel: '$label. $description',
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Radii.mediumAll,
        color: selected
            ? context.ink.base.withValues(alpha: .07)
            : Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GlyphTile(icon: icon, tint: tint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: context.ink.tertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Reserved whether or not it is ticked, so choosing does not
            // reflow the row it is on.
            SizedBox(
              width: 18,
              child: selected
                  ? Icon(Icons.check_rounded, size: 18, color: Palette.brass)
                  : null,
            ),
          ],
        ),
      ),
    ),
  );
}

/// A plain read-only line, for what the server reports and this client cannot
/// change.
class FactRow extends StatelessWidget {
  const FactRow({
    required this.label,
    required this.value,
    this.machine = false,
    this.trailing,
    super.key,
  });

  final String label;
  final String value;
  final bool machine;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: machine
                    ? mono(context, size: 11, opacity: InkLevel.tertiary)
                    : TextStyle(fontSize: 12, color: context.ink.tertiary),
              ),
            ],
          ),
        ),
        if (trailing case final trailing?) ...[
          const SizedBox(width: 12),
          trailing,
        ],
      ],
    ),
  );
}
