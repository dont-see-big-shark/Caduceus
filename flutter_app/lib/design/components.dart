/// 部件 — the parts, built from the material.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../haptics.dart';
import '../l10n/app_localizations.dart';
import 'glass.dart';
import 'press.dart';
import 'theme.dart';
import 'tokens.dart';

/// The one solid brass control on a screen.
///
/// 一屏最多一个 — the whole palette rests on brass being rare. A second one on
/// the same screen halves the meaning of both, so treat a request for one as
/// a sign that the screen has two primary actions and needs a decision, not
/// another button.
class BrassButton extends StatelessWidget {
  const BrassButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
    this.sheen = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool compact;
  final bool sheen;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final body = AnimatedContainer(
      duration: Motion.emphasized,
      curve: Motion.emphasizedCurve,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 24,
        vertical: compact ? 9 : 12,
      ),
      decoration: BoxDecoration(
        borderRadius: Radii.pillAll,
        gradient: brassSheen,
        border: Border.all(color: Colors.white.withValues(alpha: .5)),
        boxShadow: [
          BoxShadow(
            color: Palette.brass.withValues(alpha: .28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: AnimatedSize(
        duration: Motion.emphasized,
        curve: Motion.emphasizedCurve,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Palette.slate),
              const SizedBox(width: 8),
            ],
            // Flexible with dynamic text rendering so label fits smoothly.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Palette.slate,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Pressable(
        onTap: onPressed,
        semanticLabel: label,
        child: ClipRRect(
          borderRadius: Radii.pillAll,
          child: Sheen(enabled: sheen && enabled, child: body),
        ),
      ),
    );
  }
}

/// What a [MorphButton] is doing.
enum Morph { idle, working, done }

/// 提交形变 — the button *is* the progress container.
///
/// 宽度收成圆形 320ms，转子跑完后勾号弹入并把圆撑回胶囊，全程同一个 widget，
/// 不做页面级 loading. The alternative — a button that greys out and a spinner
/// somewhere else on the page — splits one event across two places and leaves
/// the thing you pressed looking broken while it works.
///
/// The pill width is measured from the label rather than guessed, so the
/// collapse lands on a true circle at any text size.
class MorphButton extends StatelessWidget {
  const MorphButton({
    required this.label,
    required this.onPressed,
    this.state = Morph.idle,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Morph state;

  static const _diameter = 52.0;

  double _pillWidth(BuildContext context) {
    final style = const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ).copyWith(fontFamily: Fonts.sans, fontFamilyFallback: Fonts.sansFallback);
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Use ceilToDouble and extra safety padding (+52) so text is never truncated to "Conn..."
    return math.max(_diameter, painter.width.ceilToDouble() + 52);
  }

  @override
  Widget build(BuildContext context) {
    final busy = state == Morph.working;
    final enabled = onPressed != null && state == Morph.idle;

    return Opacity(
      opacity: onPressed == null && state == Morph.idle ? .45 : 1,
      child: Pressable(
        onTap: enabled ? onPressed : null,
        semanticLabel: switch (state) {
          Morph.idle => label,
          Morph.working => '$label — working',
          Morph.done => '$label — done',
        },
        child: AnimatedContainer(
          duration: Motion.emphasized,
          curve: Motion.emphasizedCurve,
          width: busy ? _diameter : _pillWidth(context),
          height: _diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: Radii.pillAll,
            gradient: brassSheen,
            border: Border.all(color: Colors.white.withValues(alpha: .5)),
            boxShadow: [
              BoxShadow(
                color: Palette.brass.withValues(alpha: .28),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: Motion.standard,
            switchInCurve: Motion.standardCurve,
            // 勾号弹入 — the tick arrives with a bit of overshoot, which is
            // what makes it read as landing rather than fading up.
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: child.key == const ValueKey(Morph.done)
                  ? CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    )
                  : animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: switch (state) {
              Morph.working => const SizedBox(
                key: ValueKey(Morph.working),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Palette.slate,
                ),
              ),
              Morph.done => const Icon(
                Icons.check_rounded,
                key: ValueKey(Morph.done),
                color: Palette.slate,
              ),
              Morph.idle => Padding(
                key: const ValueKey(Morph.idle),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Palette.slate,
                  ),
                ),
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// Secondary action: a pill of regular glass.
class GlassButton extends StatelessWidget {
  const GlassButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.danger = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Danger is coral *outline*, never a coral fill — a filled destructive
  /// button competes with the brass primary for the eye.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? dangerInk(context) : context.ink.primary;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: tint),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: tint,
            ),
          ),
        ],
      ),
    );

    return Pressable(
      onTap: onPressed,
      semanticLabel: label,
      child: danger
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: Radii.pillAll,
                color: Palette.coral.withValues(alpha: .10),
                border: Border.all(color: Palette.coral.withValues(alpha: .35)),
              ),
              child: body,
            )
          : GlassPanel.pill(child: body),
    );
  }
}

/// The tracked-out uppercase label over a group.
///
/// Uppercase is not decoration here: at 11 px with 0.18em tracking, mixed case
/// reads as *body text set strangely*. The pair only works together, so this
/// widget owns both and there is no way to take one without the other.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall);
}

/// Connection state, as a lit dot behind glass.
///
/// 光点用发光而不是闪烁 — a blinking dot is an alarm. A glowing one that
/// breathes is a lamp, which is what a healthy connection should look like.
class StatusDot extends StatelessWidget {
  const StatusDot({
    required this.color,
    this.pulsing = false,
    this.size = 7,
    super.key,
  });

  final Color color;
  final bool pulsing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 10, spreadRadius: .5)],
      ),
    );
    return pulsing ? _Breathing(child: dot) : dot;
  }
}

class _Breathing extends StatefulWidget {
  const _Breathing({required this.child});

  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    Materials.ambientPaused.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final wanted = ambientAllowed(context);
    if (wanted == _c.isAnimating) return;
    if (wanted) {
      _c.repeat(reverse: true);
    } else {
      // Rests lit, not at the bottom of the breath. The dot's *colour* is
      // what carries the state; a dot frozen at .45 reads as a state that
      // has been greyed out, which is a different claim entirely.
      _c
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    Materials.ambientPaused.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(
      begin: .45,
      end: 1,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

/// The readable form of coral, for destructive labels.
///
/// [Palette.coralText] is coral lightened so it reads on slate — 8.9:1 there,
/// and **2.2:1 on white**, which is a delete button nobody can read. Same
/// mistake as the status pill: a colour tuned against one ground and then used
/// on both.
Color dangerInk(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Palette.coralText
    : Color.lerp(Palette.coral, Palette.slate, .35)!;

/// The readable form of a status colour, on a pill tinted with that colour.
///
/// The pill is tinted at 12%, not filled, so its background is very close to
/// the page behind it — and the label has to move *away* from that page, not
/// away from black. Lightening toward white is right in the dark and ruinous
/// in the light: a jade pill on a light ground measured 1.1:1, which is a
/// label nobody can read reporting a connection nobody can see.
Color statusInk(Color colour, {required bool dark}) =>
    Color.lerp(colour, dark ? Colors.white : Palette.slate, dark ? .45 : .72)!;

/// 已连接 / 重连中 / 离线 — dot, label, and a tinted pill.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.color,
    this.pulsing = false,
    super.key,
  });

  final String label;
  final Color color;
  final bool pulsing;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Motion.emphasized,
    curve: Motion.emphasizedCurve,
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
    decoration: BoxDecoration(
      borderRadius: Radii.pillAll,
      color: color.withValues(alpha: .12),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: AnimatedSize(
      duration: Motion.emphasized,
      curve: Motion.emphasizedCurve,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(color: color, pulsing: pulsing),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: statusInk(
                  color,
                  dark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Context usage — the one place a two-colour aurora gradient is a fill.
class ContextMeter extends StatelessWidget {
  const ContextMeter({
    required this.used,
    required this.total,
    this.label = '上下文',
    super.key,
  });

  final int used;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    // Coral past 85%: at that point the next long turn is the one that gets
    // compressed, and the user can still choose to branch instead.
    final tight = fraction > .85;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: context.ink.secondary),
            ),
            Text(
              '${_thousands(used)} / ${_thousands(total)}',
              style: mono(context, size: 12),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: Radii.pillAll,
          child: SizedBox(
            height: 5,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: context.ink.base.withValues(alpha: .1),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: AnimatedContainer(
                    duration: Motion.standard,
                    curve: Motion.standardCurve,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: tight
                            ? const [Palette.brass, Palette.coral]
                            : const [Palette.azure, Palette.violet],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _thousands(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
      out.write(s[i]);
    }
    return out.toString();
  }
}

/// A segmented control with a smooth sliding pill indicator.
class Segmented extends StatelessWidget {
  const Segmented({
    required this.labels,
    required this.index,
    required this.onChanged,
    super.key,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, box) {
        final n = labels.length;
        final w = box.maxWidth / n;
        return Container(
          height: 38,
          decoration: BoxDecoration(
            borderRadius: Radii.pillAll,
            color: dark
                ? Colors.white.withValues(alpha: .06)
                : Colors.black.withValues(alpha: .04),
            border: Border.all(
              color: context.ink.hairline.withValues(alpha: dark ? 0.35 : 0.18),
            ),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: Radii.pillAll,
                      color: dark
                          ? Colors.white.withValues(alpha: .15)
                          : Colors.white,
                      border: Border.all(
                        color: dark
                            ? Colors.white.withValues(alpha: .18)
                            : Colors.black.withValues(alpha: .04),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: dark ? .25 : .08,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: Pressable(
                        haptic: false,
                        onTap: () {
                          if (i == index) return;
                          Haptics.select();
                          onChanged(i);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            style: TextStyle(
                              fontFamily: Fonts.sans,
                              fontFamilyFallback: Fonts.sansFallback,
                              fontSize: 13,
                              fontWeight: i == index
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: i == index
                                  ? context.ink.primary
                                  : context.ink.tertiary,
                            ),
                            child: Text(labels[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Remembers which rows have already arrived.
///
/// Put one above a *scrolling* list. `ListView.builder` disposes rows that
/// leave the viewport and builds them fresh on the way back, so an entrance
/// animation living in the row replays on every recycle — scroll a session
/// list down and up and each row fades in again under your finger. The set
/// lives above the list, where recycling cannot reach it, so a row arrives
/// exactly once per time the *surface* appears.
///
/// Menus do not need one: they are built once and thrown away.
class StaggerScope extends StatefulWidget {
  const StaggerScope({required this.child, super.key});

  final Widget child;

  @override
  State<StaggerScope> createState() => _StaggerScopeState();
}

class _StaggerScopeState extends State<StaggerScope> {
  final Set<int> _arrived = {};

  @override
  Widget build(BuildContext context) =>
      _StaggerRegistry(arrived: _arrived, child: widget.child);
}

class _StaggerRegistry extends InheritedWidget {
  const _StaggerRegistry({required this.arrived, required super.child});

  final Set<int> arrived;

  static Set<int>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StaggerRegistry>()?.arrived;

  @override
  bool updateShouldNotify(_StaggerRegistry old) => false;
}

/// 开关旋钮过冲 3px，轨道颜色用 lerp 而不是切换.
///
/// Both halves matter and Material's switch does neither. The thumb overshoots
/// its destination by 3 points and settles back, which is what makes the throw
/// feel like a physical toggle rather than a value changing. The track *lerps*
/// between its two colours across the same motion — switching it at the
/// midpoint, or at the end, makes the colour and the thumb read as two
/// unrelated events.
class GlassSwitch extends StatefulWidget {
  const GlassSwitch({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

class _GlassSwitchState extends State<GlassSwitch>
    with SingleTickerProviderStateMixin {
  static const _width = 46.0;
  static const _height = 28.0;
  static const _thumb = 22.0;
  static const _inset = 3.0;
  static const travel = _width - _thumb - _inset * 2;

  /// How far past its destination the thumb goes, in points.
  static const overshoot = 3.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.standard,
    value: widget.value ? 1 : 0,
  );

  /// [Curves.easeOutBack] normalised so its peak lands exactly [overshoot]
  /// points past the end, whatever the travel happens to be.
  ///
  /// The stock curve overshoots by about a tenth of its range, which on 18
  /// points of travel is 1.8 — close enough to look deliberate and not close
  /// enough to be the number the design asks for.
  static final _thrown = _NormalisedOvershoot(overshoot / travel);
  late final Animation<double> _slide = CurvedAnimation(
    parent: _c,
    curve: _thrown,
    reverseCurve: FlippedCurve(_thrown),
  );

  @override
  void didUpdateWidget(GlassSwitch old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      widget.value ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      toggled: widget.value,
      child: Pressable(
        haptic: false,
        onTap: () {
          Haptics.select();
          widget.onChanged(!widget.value);
        },
        child: SizedBox(
          width: 60,
          height: 44,
          child: Center(
            child: AnimatedBuilder(
              animation: _slide,
              builder: (context, _) {
                // The two halves of the spec, driven apart on purpose: the
                // track lerps on the linear controller so the colour arrives
                // when the thumb does, while the thumb rides the overshoot.
                final t = _c.value;
                final x = _slide.value * travel;
                return Container(
                  width: _width,
                  height: _height,
                  decoration: BoxDecoration(
                    borderRadius: Radii.pillAll,
                    color: Color.lerp(
                      context.ink.base.withValues(alpha: .16),
                      Palette.brassDeep,
                      t,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: _inset + x,
                        top: _inset,
                        child: Container(
                          width: _thumb,
                          height: _thumb,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// [Curves.easeOutBack] with its overshoot rescaled to a chosen size.
///
/// The stock curve's overshoot is whatever its control points happen to give.
/// Rescaling only the part above 1 keeps the approach identical and makes the
/// one number the design actually specifies — how far past the end it goes —
/// something you can set rather than inherit.
class _NormalisedOvershoot extends Curve {
  const _NormalisedOvershoot(this.peak);

  /// The desired overshoot, as a fraction of the range.
  final double peak;

  /// What [Curves.easeOutBack] overshoots by on its own, found by sampling
  /// rather than asserted: it is a property of the cubic, not of this class.
  static final double _stock = () {
    var max = 1.0;
    for (var i = 0; i <= 1000; i++) {
      final v = Curves.easeOutBack.transform(i / 1000);
      if (v > max) max = v;
    }
    return max - 1;
  }();

  @override
  double transformInternal(double t) {
    final v = Curves.easeOutBack.transform(t);
    return v <= 1 ? v : 1 + (v - 1) * (peak / _stock);
  }
}

/// 交错入场 — children slide in 24 ms apart, up to eight.
///
/// The cap matters more than the stagger: without it the ninth row of a long
/// list arrives a quarter-second late and the list feels slow rather than
/// choreographed.
///
/// In a scrolling list, wrap the list in a [StaggerScope] or every row will
/// animate again each time it scrolls back into view.
class Staggered extends StatelessWidget {
  const Staggered({
    required this.index,
    required this.child,
    this.from = const Offset(-10, 0),
    super.key,
  });

  final int index;
  final Widget child;
  final Offset from;

  @override
  Widget build(BuildContext context) {
    final arrived = _StaggerRegistry.of(context);
    if (arrived != null && !arrived.add(index)) return child;
    final steps = math.min(index, Motion.staggerCap);
    return _Entrance(delay: Motion.stagger * steps, from: from, child: child);
  }
}

class _Entrance extends StatefulWidget {
  const _Entrance({
    required this.delay,
    required this.from,
    required this.child,
  });

  final Duration delay;
  final Offset from;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  /// One controller covering *delay plus travel*, with the delay expressed as
  /// an [Interval] rather than a timer.
  ///
  /// The timer version worked and was still the wrong shape: between `delay`
  /// firing and `forward()` running there is a window where the row is armed
  /// but not moving, and anything that costs it frames in that window —
  /// a stalled harness, a jank spike, a rebuild — leaves it stranded at zero
  /// opacity, which is indistinguishable from a broken build. With an
  /// interval there is nothing to strand: whenever the next frame lands, the
  /// value is a pure function of elapsed time.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + Motion.emphasized,
  )..forward();

  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMicroseconds / _c.duration!.inMicroseconds,
      1,
      curve: Motion.emphasizedCurve,
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _t,
    // Flutter drops a transparent subtree from the semantics tree, so for the
    // length of an entrance the content is invisible to VoiceOver — and
    // permanently invisible if the animation ever failed to finish. Verified
    // by removing this line: `accessibility_test` stops finding the label a
    // failed tool call is announced with. The content is real the moment it is
    // built; only its *appearance* is arriving.
    alwaysIncludeSemantics: true,
    child: AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          widget.from.dx * (1 - _t.value),
          widget.from.dy * (1 - _t.value),
        ),
        child: child,
      ),
      child: widget.child,
    ),
  );
}

/// Plays an arrival once, the first time this index is seen.
///
/// The counterpart to [StaggerScope] for lists whose "already arrived" set
/// cannot live in the widget tree — a turn's timeline sits inside the
/// transcript's `ListView`, so every widget it owns is thrown away and rebuilt
/// on scroll. Hand it a set that belongs to the model instead.
///
/// No stagger: these entries arrive one at a time, seconds apart, as the model
/// thinks and runs things. Delaying the third one by 72 ms would be delaying
/// the only thing that just happened.
class Reveal extends StatelessWidget {
  const Reveal({
    required this.index,
    required this.revealed,
    required this.child,
    super.key,
  });

  final int index;
  final Set<int> revealed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!revealed.add(index)) return child;
    return _Entrance(
      delay: Duration.zero,
      // 工具卡 gl-tool-in: up and into place. Sideways would fight the
      // timeline's vertical reading order.
      from: const Offset(0, 12),
      child: child,
    );
  }
}

/// 气泡从输入条位置向上生长入场 — a question grows out of where it was typed.
///
/// The same first-time-only bookkeeping as [Reveal], because the same trap
/// applies: `ListView.builder` disposes what leaves the viewport and builds it
/// fresh on return, so an entrance keyed on "is this widget new" replays every
/// time you scroll back to it. The set is what makes *new* mean new.
///
/// It scales from the bottom-trailing corner rather than the centre. That
/// corner is where the composer is, so the bubble reads as having come from
/// the thing you pressed — which is the whole claim the animation makes. A
/// centred scale is a bubble that appeared, not one that was sent.
class GrowFromComposer extends StatelessWidget {
  const GrowFromComposer({
    required this.index,
    required this.revealed,
    required this.child,
    super.key,
  });

  final int index;
  final Set<int> revealed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!revealed.add(index)) return child;
    return _Grow(child: child);
  }
}

class _Grow extends StatefulWidget {
  const _Grow({required this.child});

  final Widget child;

  @override
  State<_Grow> createState() => _GrowState();
}

class _GrowState extends State<_Grow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.emphasized,
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Motion.emphasizedCurve);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        // Never fully transparent: a bubble at zero opacity drops out of the
        // semantics tree, and the question you just asked is the last thing
        // that should be unreadable to a screen reader.
        opacity: .15 + curved.value * .85,
        child: Transform.scale(
          // Only the last of the growth is visible — starting at .8 makes the
          // bubble lunge, and a question is not an event.
          scale: .92 + curved.value * .08,
          alignment: AlignmentDirectional.bottomEnd,
          child: Transform.translate(
            offset: Offset(0, (1 - curved.value) * 10),
            child: child,
          ),
        ),
      ),
      child: widget.child,
    );
  }
}

/// 文末光标闪烁 — the caret at the end of text still being written.
///
/// The one piece of chrome that says *more is coming* without occupying a
/// line. It matters most in the gap the rest of the UI cannot cover: between
/// two sentences, when nothing has arrived for a second and the composer's rim
/// light is at the far edge of the screen from where you are reading.
///
/// A hard blink, not a fade: 0–45% on, 55–100% off, which is what a terminal
/// caret does and what the source specifies.
class StreamCaret extends StatefulWidget {
  const StreamCaret({super.key});

  @override
  State<StreamCaret> createState() => _StreamCaretState();
}

class _StreamCaretState extends State<StreamCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    Materials.ambientPaused.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final wanted = ambientAllowed(context);
    if (wanted == _c.isAnimating) return;
    // Stopped, it rests *visible* rather than wherever the blink happened to
    // be: a caret frozen mid-off looks like the answer ended.
    wanted ? _c.repeat() : _c.value = 0;
  }

  @override
  void dispose() {
    Materials.ambientPaused.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 10),
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: _c.value < .45 ? 1 : 0,
        child: Container(
          width: 8,
          height: 16,
          decoration: BoxDecoration(
            color: Palette.brass,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      ),
    ),
  );
}

/// Fades its child in when it is mounted, and never holds an old one.
///
/// Key it by the session id: changing the key remounts, which plays the fade.
/// Nothing lingers, so two views of one conversation can never coexist —
/// the property that matters, because both would attach that conversation's
/// single scroll controller.
class SessionFade extends StatelessWidget {
  const SessionFade({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _Entrance(delay: Duration.zero, from: Offset.zero, child: child);
}

/// 边缘流光 — a light running around the rim while a turn is generating.
///
/// This replaces a "generating…" label entirely. The composer is already where
/// the user is looking, and a moving edge says *working* without occupying a
/// line of text or needing translation.
class RimLight extends StatefulWidget {
  const RimLight({
    required this.child,
    required this.active,
    this.radius = Radii.pillAll,
    this.color = Palette.brass,
    super.key,
  });

  final Widget child;
  final bool active;
  final BorderRadius radius;
  final Color color;

  @override
  State<RimLight> createState() => _RimLightState();
}

class _RimLightState extends State<RimLight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didUpdateWidget(RimLight old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final wanted = widget.active && ambientAllowed(context);
    if (wanted == _c.isAnimating) return;
    if (wanted) {
      _c.repeat();
    } else {
      // Back to the start of the travel rather than frozen partway along it:
      // a light stopped mid-sweep looks like a rendering fault, and the rim
      // is still drawn while `active`, so the turn still reads as running.
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (widget.active)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => CustomPaint(
                    painter: _RimPainter(
                      t: _c.value,
                      radius: widget.radius,
                      color: widget.color,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RimPainter extends CustomPainter {
  const _RimPainter({
    required this.t,
    required this.radius,
    required this.color,
  });

  final double t;
  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // A sweep gradient rotated by t: one bright arc travelling the border.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: GradientRotation(t * math.pi * 2),
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0),
          color.withValues(alpha: .85),
          color.withValues(alpha: 0),
        ],
        stops: const [0, .55, .72, .9],
      ).createShader(rect);
    canvas.drawRRect(radius.toRRect(rect).deflate(.7), paint);
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.t != t || old.color != color;
}

/// The header close × shared by every glass-card overlay: a 34 pt pressable
/// that pops the route it sits in. Defined once so the Settings card, the
/// panel card and any other overlay cannot drift apart.
class HeaderCloseButton extends StatelessWidget {
  const HeaderCloseButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n?.close ?? 'Close',
      child: Pressable(
        onTap: () => Navigator.of(context).maybePop(),
        semanticLabel: l10n?.close ?? 'Close',
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: context.ink.secondary,
          ),
        ),
      ),
    );
  }
}
