/// The material: sheets of glass floating over the page.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// A sheet of glass.
///
/// The iron rule from the spec, worth repeating where it will be read:
/// **long-form text never sits on glass.** Glass carries controls — rows,
/// toolbars, inputs, menus. The moment content is meant to be *read*, it
/// belongs on an opaque [Palette.slate] panel. Ignoring this is the single
/// most common way a liquid-glass design turns illegible.
///
/// Four things together make the material read as glass, and dropping any one
/// of them makes it read as a translucent rectangle:
///  1. a *blurred backdrop*, so what is behind bends;
///  2. a *top-to-bottom tint gradient*, so the sheet catches light unevenly;
///  3. a *1 px inset highlight along the top edge*, the lit rim;
///  4. a hairline border, so the sheet has an edge at all.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.level = Glass.regular,
    this.radius = Radii.largeAll,
    this.padding = EdgeInsets.zero,
    this.thickness = 1,
    this.clip = true,
    this.border = true,
    this.tint,
    super.key,
  });

  /// A pill — the shape of the composer, buttons and status chips.
  const GlassPanel.pill({
    required this.child,
    this.level = Glass.regular,
    this.padding = EdgeInsets.zero,
    this.thickness = 1,
    this.border = true,
    this.tint,
    super.key,
  }) : radius = Radii.pillAll,
       clip = true;

  final Widget child;
  final Glass level;
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;
  final bool clip;
  final bool border;

  /// Scales the blur and the tint together, 0 → 1.
  ///
  /// This is what "厚度过渡" is made of: a popover opens by the glass getting
  /// *thicker*, not by fading in. Drive it from an animation and the sheet
  /// appears to come forward out of the page.
  final double thickness;

  /// Overrides the sheet's colour — used by the brass-tinted user bubble.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<bool>(
      valueListenable: Materials.degraded,
      builder: (context, degraded, _) {
        final t = thickness.clamp(0.0, 1.0);
        final borderColor = border ? _border(dark, t) : null;

        // No blur, no gradient: a solid panel and one hairline. Every size,
        // radius, duration and curve around it is unchanged, so the app feels
        // the same and only looks cheaper.
        if (degraded) {
          return _frame(
            decoration: BoxDecoration(
              color: dark
                  ? Palette.slate.withValues(alpha: .92)
                  : Colors.white.withValues(alpha: .96),
              borderRadius: radius,
              border: borderColor != null
                  ? Border.all(color: borderColor)
                  : null,
            ),
            child: child,
          );
        }

        final content = Stack(
          children: [
            _frame(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  // The source's 160°, not the 135° a topLeft→bottomRight diagonal
                  // gives. CSS measures clockwise from "to top", so 160° is mostly
                  // *downward* with a slight rightward lean — light falling on a
                  // sheet from above, rather than from a corner. On a wide panel
                  // the diagonal put the bright end in the corner and left the
                  // whole top edge flat.
                  begin: const Alignment(-.34, -.94),
                  end: const Alignment(.34, .94),
                  colors: glassTint(
                    level,
                    dark: dark,
                    tint: tint,
                    thickness: t,
                  ),
                ),
                borderRadius: radius,
                border: borderColor != null
                    ? Border.all(color: borderColor)
                    : null,
                boxShadow: level.shadow == 0 || t < .5
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .45 * t),
                          blurRadius: level.shadow * t,
                          offset: Offset(0, level.shadow * .4 * t),
                        ),
                      ],
              ),
              child: child,
            ),
            // The lit rim. Positioned inside the clip so it follows the
            // corner radius, and faded at both ends because a hard 1 px
            // line running into a 22 px corner looks like a seam.
            Positioned(
              top: 0,
              left: radius.topLeft.x,
              right: radius.topRight.x,
              height: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        // Dark only. A white rim on a white sheet over a
                        // light page is invisible — the edge is carried by
                        // the border there instead, which is the reverse of
                        // how it works in the dark.
                        Colors.white.withValues(
                          alpha: dark ? level.highlight * t : 0,
                        ),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

        if (!clip) return content;

        // A sheet inside another sheet does not blur again.
        //
        // Nesting `BackdropFilter` was both the expensive mistake and the
        // ugly one: the inner filter blurs what the outer one has *already*
        // blurred, so the aurora underneath turns to flat grey haze and the
        // material stops reading as glass. The design's budget is two blurred
        // layers on screen; a drawer containing a search pill, a button and
        // eight rows was spending eleven.
        //
        // The tint, the border and the lit rim still draw — that is what makes
        // the inner sheet visible as a distinct surface. It simply sits on the
        // backdrop the parent already bent.
        if (_GlassDepth.isNested(context)) return content;

        return _GlassDepth(
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: glassFilter(level, t, dark),
              child: content,
            ),
          ),
        );
      },
    );
  }

  /// A tinted sheet's edge is drawn in its own colour — that rim is most of
  /// what identifies it at a glance.
  Color _border(bool dark, double t) => switch (tint) {
    final Color c => c.withValues(alpha: level.border * (dark ? 1.6 : 2.4) * t),
    null =>
      dark
          ? Colors.white.withValues(alpha: level.border * t)
          // Carries the whole edge on a light ground, where the lit rim does
          // nothing: at half strength the composer had no discernible boundary
          // and read as a grey smear rather than a panel.
          : Palette.slate.withValues(alpha: level.border * t),
  };

  Widget _frame({required Decoration decoration, required Widget child}) =>
      DecoratedBox(
        decoration: decoration,
        child: Padding(padding: padding, child: child),
      );
}

/// The two ends of a sheet's tint gradient — top-left, then bottom-right.
///
/// A named function rather than arithmetic buried in a build method, because
/// this is *the* rule the material rests on and it needs to be assertable
/// without spelunking a widget tree: **a sheet is always lighter than what is
/// behind it.** That is what catching light means, and it holds in both modes.
///
/// Tinting with slate on a light ground was the mistake, and it was structural
/// rather than cosmetic: every sheet came out darker than the page, so the
/// composer read as a hole punched in the paper rather than a panel floating
/// over it. On a light ground the sheet is white — just much more of it,
/// because white on near-white has far less room to work with than white on
/// near-black.
///
/// Four corrections, each for its own reason:
///
///  * a **colour** tint carries further than a white one — white at 15% over
///    dark reads instantly, brass at 15% reads as grey. The design's own brass
///    bubble is 22% → 10%;
///  * a coloured sheet needs more of itself again on a **light** ground: brass
///    at 33% over white is a warm grey, which is what the bubble came out as;
///  * a white sheet needs far more of itself to separate from a light page;
///  * and it needs a **floor**. Over near-black a 15% → 5% ramp still reads as
///    one sheet, because both ends are far brighter than the page. Over a light
///    page the thin end lets the page straight through and the panel fades into
///    a grey smear halfway down. The gradient survives; it stops at a point
///    where the panel is still a panel.
List<Color> glassTint(
  Glass level, {
  required bool dark,
  Color? tint,
  double thickness = 1,
}) {
  final t = thickness.clamp(0.0, 1.0);
  final base = tint ?? Colors.white;
  double alpha(double stop) {
    if (tint != null) return (stop * (dark ? 1.5 : 2.6) * t).clamp(0.0, 1.0);
    if (dark) return stop * t;
    return (stop * 5.5 * t).clamp(.62 * t, 1.0);
  }

  return [
    base.withValues(alpha: alpha(level.tintTop)),
    base.withValues(alpha: alpha(level.tintBottom)),
  ];
}

/// Marks the subtree below a sheet that has already blurred its backdrop.
class _GlassDepth extends InheritedWidget {
  const _GlassDepth({required super.child});

  static bool isNested(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassDepth>() != null;

  @override
  bool updateShouldNotify(_GlassDepth old) => false;
}

/// Blur *and* saturation, which is the pair that makes a backdrop look like
/// glass rather than frosted plastic.
///
/// Saturating what shows through is why the aurora reads as colour behind the
/// sheet instead of as grey haze — the blur alone washes it out.
ui.ImageFilter glassFilter(
  Glass level, [
  double thickness = 1,
  bool dark = true,
]) {
  final t = thickness.clamp(0.0, 1.0);
  final sigma = level.blur * t;
  final blur = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
  if (t < .01) return blur;
  // Saturation is a dark-mode instrument. Over near-black it is what keeps
  // the aurora reading as *colour behind glass* rather than grey haze; over a
  // light page it pushes that colour up through the sheet and the panel comes
  // out looking dirty instead of frosted.
  final target = dark ? level.saturate : 1 + (level.saturate - 1) * .25;
  final s = 1 + (target - 1) * t;
  return ui.ImageFilter.compose(outer: _saturate(s), inner: blur);
}

/// The standard luminance-preserving saturation matrix.
ColorFilter _saturate(double s) {
  const lr = .2126, lg = .7152, lb = .0722;
  final ir = (1 - s) * lr, ig = (1 - s) * lg, ib = (1 - s) * lb;
  return ColorFilter.matrix(<double>[
    ir + s, ig, ib, 0, 0, //
    ir, ig + s, ib, 0, 0, //
    ir, ig, ib + s, 0, 0, //
    0, 0, 0, 1, 0,
  ]);
}

/// An opaque panel — where text goes.
///
/// The counterpart to [GlassPanel], and just as much a part of the system:
/// the design is *glass over content*, so there has to be something for the
/// glass to be over.
class SlatePanel extends StatelessWidget {
  const SlatePanel({
    required this.child,
    this.radius = Radii.largeAll,
    this.padding = EdgeInsets.zero,
    this.opacity = .82,
    super.key,
  });

  final Widget child;
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Pure white in light mode. The content plane has to be *brighter*
        // than the aurora-lit page, or the structure the whole design rests on
        // — glass floating over content — has no content to float over: snow
        // on a snow-coloured background is one flat field.
        color: dark
            ? Palette.slate.withValues(alpha: opacity)
            : Colors.white.withValues(alpha: opacity),
        borderRadius: radius,
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: .10)
              : Palette.slate.withValues(alpha: .08),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
