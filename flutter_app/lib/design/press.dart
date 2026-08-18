/// 按压物理 — what a press feels like.
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../haptics.dart';
import 'theme.dart';
import 'tokens.dart';

/// Scales its child down on touch-down and releases it on a spring.
///
/// The release is a [SpringSimulation], not a curve: the child overshoots to
/// about 1.02 and settles. A curve can imitate the shape but not the
/// behaviour — interrupt a spring halfway and it carries its velocity into the
/// new motion, which is exactly what makes rapid tapping feel physical instead
/// of stuttery.
///
/// Haptics fire on the frame the animation *arrives*, not the frame the finger
/// lands. Feedback that precedes the visible response reads as a glitch.
class Pressable extends StatefulWidget {
  const Pressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = Motion.pressScale,
    this.haptic = true,
    this.semanticLabel,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final String? semanticLabel;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: Motion.springStiffness,
    damping: Motion.springDamping,
  );

  bool get _live =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _down(_) {
    if (!_live) return;
    _c.animateTo(
      widget.scale,
      duration: Motion.pressDown,
      curve: Motion.standardCurve,
    );
  }

  void _release() {
    if (!_live) return;
    // Velocity carries the overshoot; the spring does the rest.
    _c.animateWith(SpringSimulation(_spring, _c.value, 1, 3.2));
  }

  void _tap() {
    _release();
    if (!_live) return;
    if (widget.haptic) Haptics.tap();
    widget.onTap?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _down,
      onTapUp: (_) => _tap(),
      onTapCancel: _release,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _release();
              Haptics.warn();
              widget.onLongPress!();
            },
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) =>
            Transform.scale(scale: _c.value, child: child),
        child: widget.child,
      ),
    );
    if (widget.semanticLabel == null) return gesture;
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: _live,
      child: gesture,
    );
  }
}

/// A slow highlight travelling across a surface.
///
/// 是材料的反光，不是动效 — at 4.5 s it is too slow to read as an animation and
/// registers instead as light moving over something polished. Reserved for the
/// single brass button on a screen.
class Sheen extends StatefulWidget {
  const Sheen({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  State<Sheen> createState() => _SheenState();
}

class _SheenState extends State<Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4500),
  );

  @override
  void initState() {
    super.initState();
    Materials.ambientPaused.addListener(_sync);
  }

  @override
  void didUpdateWidget(Sheen old) {
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
    final wanted = widget.enabled && ambientAllowed(context);
    if (wanted == _c.isAnimating) return;
    if (wanted) {
      _c.repeat();
    } else {
      // Value 0 puts the band fully off the left edge, where it is invisible.
      // Stopping in place would freeze a bright stripe across the brass —
      // the one thing a reflection must never do, in a new way.
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    Materials.ambientPaused.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  /// How wide the highlight is, as a fraction of the button.
  static const _band = .34;

  /// Fractional position of the band's centre → the `Alignment` that puts it
  /// there. `Align` resolves against the free space, so anything outside
  /// 0…1 needs the same compensation the aurora does.
  static double _offscreen(double centre) => (centre - .5) * 2 / (1 - _band);

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return ClipRect(
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => FractionallySizedBox(
                  widthFactor: _band,
                  // Starts and ends fully *outside* the button, so the loop
                  // has no visible beginning. At alignment -1 the band is
                  // flush against the left edge rather than beyond it, which
                  // made the highlight pop into existence every 4.5 s — the
                  // one thing a reflection must never do.
                  alignment: Alignment(
                    _offscreen(-.2) +
                        (_offscreen(1.2) - _offscreen(-.2)) * _c.value,
                    0,
                  ),
                  child: Transform(
                    transform: Matrix4.skewX(-.32),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: .55),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hold to confirm something destructive.
///
/// 危险操作不做二次弹窗 — a modal asking "are you sure?" is dismissed without
/// reading it, every time. A 900 ms hold cannot be, and it costs a deliberate
/// user less than a dialog does. Letting go early rewinds in 240 ms, because
/// undoing a decision should never be slower than making it.
class HoldToConfirm extends StatefulWidget {
  const HoldToConfirm({
    required this.label,
    required this.confirmedLabel,
    required this.onConfirmed,
    this.color = Palette.coral,
    super.key,
  });

  final String label;
  final String confirmedLabel;
  final VoidCallback onConfirmed;
  final Color color;

  @override
  State<HoldToConfirm> createState() => _HoldToConfirmState();
}

class _HoldToConfirmState extends State<HoldToConfirm>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.hold,
    reverseDuration: Motion.holdRewind,
  )..addStatusListener(_onStatus);

  bool _done = false;

  void _onStatus(AnimationStatus s) {
    if (s != AnimationStatus.completed || _done) return;
    setState(() => _done = true);
    Haptics.warn();
    widget.onConfirmed();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (!_done) _c.forward();
      },
      onTapUp: (_) => _c.reverse(),
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: Radii.pillAll,
            color: widget.color.withValues(alpha: .10 + _c.value * .16),
            border: Border.all(
              color: widget.color.withValues(alpha: .35 + _c.value * .45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The progress runs *around* the label rather than under it, so
              // the control stays readable while it fills.
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  value: _done ? 1 : _c.value,
                  strokeWidth: 2,
                  color: widget.color,
                  backgroundColor: widget.color.withValues(alpha: .2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _done ? widget.confirmedLabel : widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: widget.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 手势跟随 — a sheet that follows the finger 1:1 and leaves on release.
///
/// 松手后按速度决定去留: velocity *or* distance ends it, because a fast flick
/// is a dismissal even when it covered barely any ground — which is how the
/// gesture is actually performed. Anything that eases behind the finger makes
/// the sheet feel stuck to the glass.
///
/// The [handle] is the drag target and the affordance at once. Give it the
/// whole header where there is one: a 4-point bar is a hard thing to hit, and
/// the hand is already up there.
class PullToDismiss extends StatefulWidget {
  const PullToDismiss({
    required this.child,
    this.enabled = true,
    this.handle,
    this.onDismiss,
    super.key,
  });

  final Widget child;

  /// Off on a desktop, where there is no thumb at the bottom of the screen
  /// and the sheet is a dialog in the middle of a window.
  final bool enabled;

  /// Drawn above [child] and used as the drag target. Omit to make the whole
  /// child draggable.
  final Widget? handle;

  /// Defaults to popping the route.
  final VoidCallback? onDismiss;

  @override
  State<PullToDismiss> createState() => _PullToDismissState();
}

class _PullToDismissState extends State<PullToDismiss> {
  double _drag = 0;

  /// Past this, letting go dismisses rather than springs back.
  static const _dismissAfter = 90.0;

  /// A flick this fast dismisses whatever ground it covered.
  static const _flick = 700.0;

  void _update(DragUpdateDetails d) {
    if (!widget.enabled) return;
    setState(() => _drag = (_drag + d.delta.dy).clamp(0.0, 400.0));
  }

  void _end(DragEndDetails d) {
    if (!widget.enabled) return;
    if (d.velocity.pixelsPerSecond.dy > _flick || _drag > _dismissAfter) {
      (widget.onDismiss ?? Navigator.of(context).pop)();
    } else {
      setState(() => _drag = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final handle = widget.handle;
    return Transform.translate(
      offset: Offset(0, _drag),
      child: handle == null
          ? GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onVerticalDragUpdate: _update,
              onVerticalDragEnd: _end,
              child: widget.child,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _update,
                  onVerticalDragEnd: _end,
                  child: handle,
                ),
                Flexible(child: widget.child),
              ],
            ),
    );
  }
}

/// The grab bar itself — 36×4, the size every sheet on the platform uses.
class GrabHandle extends StatelessWidget {
  const GrabHandle({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: context.ink.base.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}
