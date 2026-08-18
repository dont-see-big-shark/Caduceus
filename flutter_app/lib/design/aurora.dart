/// The light behind the glass.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Four coloured lights drifting under the whole app.
///
/// Everything else in this design is a sheet of glass, and a sheet of glass
/// over a flat colour is just a grey rectangle — the aurora is what there is
/// to refract. It is the only place [Palette.azure], [Palette.violet] and
/// [Palette.jade] appear at full strength.
///
/// The source animates `filter: blur(30px)` over four radial gradients. The
/// blur is not reproduced here: a full-screen `ImageFilter.blur` every frame
/// costs more than the entire rest of the UI, and radial gradients with a
/// transparent outer stop are already soft. What is reproduced exactly is the
/// 30-second drift, because that slow movement is the part you actually
/// perceive.
class Aurora extends StatefulWidget {
  const Aurora({
    this.child,
    this.opacity = .5,
    this.colors = const [
      Palette.azure,
      Palette.violet,
      Palette.jade,
      Palette.brass,
    ],
    super.key,
  });

  final Widget? child;
  final double opacity;

  /// In painting order: upper-left, upper-right, lower-right, lower-left.
  final List<Color> colors;

  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  /// How often the drift advances. The source takes 30 s to travel the loop;
  /// at 10 Hz that is 300 distinct positions — more than the eye resolves —
  /// and each step repaints the full-bleed lights. A 60 Hz frame-clock loop
  /// repaints six times as often for a movement that is a fraction of a
  /// pixel per frame, which was the app's largest idle cost: the raster
  /// thread composited every vsync even with nothing on screen.
  static const _driftTick = Duration(milliseconds: 100);

  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  );
  Timer? _driftTimer;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    Materials.ambientPaused.addListener(_sync);
    Materials.degraded.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  /// Every runtime switch lands here: paused ambience, degraded material and
  /// reduce-motion all mean the same thing to this widget — stop repainting.
  void _sync() {
    if (!mounted) return;
    final wanted = ambientAllowed(context);
    if (wanted == _running) return;
    _running = wanted;
    _driftTimer?.cancel();
    _driftTimer = null;
    if (wanted) {
      // Advance the drift on a coarse timer rather than the frame clock.
      // Pausing (scroll, reduce-motion, degraded) stops the timer, and
      // resuming carries on from the current value — no jump.
      _driftTimer = Timer.periodic(_driftTick, (_) {
        if (!mounted || !_running) return;
        final step =
            _driftTick.inMilliseconds / _drift.duration!.inMilliseconds;
        final next = _drift.value + step;
        _drift.value = next >= 1 ? next - 1 : next;
      });
    }
  }

  @override
  void dispose() {
    _driftTimer?.cancel();
    Materials.ambientPaused.removeListener(_sync);
    Materials.degraded.removeListener(_sync);
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<bool>(
      valueListenable: Materials.degraded,
      builder: (context, degraded, _) => DecoratedBox(
        decoration: BoxDecoration(
          // The light page is deliberately a step deeper than the sheets that
          // float on it. At #EFF0F5 it was within a hair of the content plane,
          // and the two planes merged into one flat field — glass with nothing
          // to be over.
          color: dark ? Palette.voidBlack : const Color(0xFFE4E7EF),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Degraded hardware gets the flat page and no lights at all —
            // half a dozen full-screen gradients is exactly the fill cost the
            // fallback exists to avoid.
            if (!degraded)
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _drift,
                  builder: (context, _) => _Lights(
                    t: _drift.value,
                    // The page is meant to read as deep space first: the
                    // lights are a faint wash behind the glass, not a coloured
                    // sky. At full strength they lifted the background to a
                    // blue-grey instead of the near-black #04050A the design
                    // names as `--bg`.
                    opacity: widget.opacity * (dark ? .14 : .4),
                    colors: widget.colors,
                  ),
                ),
              ),
            if (!degraded) const _Grain(),
            if (widget.child != null) widget.child!,
          ],
        ),
      ),
    );
  }
}

/// The four lights, and the drift.
///
/// One `Transform` over one painted layer, matching the source's single
/// animated element: the gradients rasterise once and the frames after that
/// only move the layer.
class _Lights extends StatelessWidget {
  const _Lights({required this.t, required this.opacity, required this.colors});

  final double t;
  final double opacity;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    // gl-drift: 0% none → 33% (3%,-3%) ×1.09 → 66% (-3%,2%) ×0.95 → 100% none.
    final (dx, dy, scale) = switch (t) {
      < .33 => _lerp3(t / .33, (0, 0, 1), (.03, -.03, 1.09)),
      < .66 => _lerp3((t - .33) / .33, (.03, -.03, 1.09), (-.03, .02, .95)),
      _ => _lerp3((t - .66) / .34, (-.03, .02, .95), (0, 0, 1)),
    };

    return LayoutBuilder(
      builder: (context, box) => Transform(
        transform: Matrix4.identity()
          ..translateByDouble(box.maxWidth * dx, box.maxHeight * dy, 0, 1)
          ..scaleByDouble(scale, scale, 1, 1),
        alignment: Alignment.center,
        // No `Opacity` widget: it saves the whole screen to an offscreen
        // buffer and composites it back every frame, which on a full-bleed
        // background is the most expensive way to multiply four numbers.
        // The opacity is folded into the gradient colours instead.
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Read straight off the source's four `radial-gradient(w h at
            // x y)` stops: half-size first, then where its centre sits.
            _light(colors[0], .36, .40, .20, .18),
            _light(colors[1], .32, .36, .82, .14),
            _light(colors[2], .40, .44, .72, .78),
            _light(colors[3], .28, .32, .26, .88),
          ],
        ),
      ),
    );
  }

  /// One light, expressed the way the source does: a radius as a fraction of
  /// the viewport, and a centre as a fraction of it.
  ///
  /// The compensation in [_at] is the whole reason this is a method. `Align`
  /// resolves its alignment against the *free* space — parent minus child —
  /// so a light 72% as wide as the screen asked to sit at 20% lands at 42%
  /// instead. All four then pile up in the middle, which is precisely what
  /// they did: a smudge in the centre rather than light in the corners.
  Widget _light(Color color, double rx, double ry, double cx, double cy) =>
      Align(
        alignment: Alignment(_at(cx, rx * 2), _at(cy, ry * 2)),
        child: FractionallySizedBox(
          widthFactor: rx * 2,
          heightFactor: ry * 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                // Five stops on an eased falloff rather than two on a linear
                // one. A straight ramp from a saturated colour to nothing
                // across half a screen crosses far more 8-bit steps than the
                // display has, and the result is visible rings — worst on the
                // OLED near-black this design sits on. The extra stops bend
                // the ramp so most of its travel happens where the colour is
                // already faint.
                colors: [
                  color.withValues(alpha: opacity),
                  color.withValues(alpha: opacity * .72),
                  color.withValues(alpha: opacity * .38),
                  color.withValues(alpha: opacity * .12),
                  color.withValues(alpha: 0),
                ],
                // Fades to nothing before the edge, so four overlapping
                // lights stay four lights instead of a wash.
                stops: const [0, .22, .40, .54, .68],
              ),
            ),
          ),
        ),
      );

  /// Fractional position → the `Alignment` that actually puts a child of
  /// [size] (also fractional) there. Degenerates safely when the child is as
  /// large as the parent, where no alignment can move it at all.
  static double _at(double centre, double size) {
    final free = 1 - size;
    if (free.abs() < .001) return 0;
    return (centre - .5) * 2 / free;
  }

  (double, double, double) _lerp3(
    double t,
    (double, double, double) a,
    (double, double, double) b,
  ) {
    // The drift keyframes are `ease-in-out`, not linear.
    final e = Curves.easeInOut.transform(t.clamp(0, 1));
    return (
      a.$1 + (b.$1 - a.$1) * e,
      a.$2 + (b.$2 - a.$2) * e,
      a.$3 + (b.$3 - a.$3) * e,
    );
  }
}

/// A 3 px dot grid at 4.5% white.
///
/// Almost invisible, and doing a lot of work: it gives the gradients a surface
/// so large flat areas do not band on an OLED panel. Painted as a repeating
/// 3×3 tile rather than thousands of circles.
class _Grain extends StatefulWidget {
  const _Grain();

  @override
  State<_Grain> createState() => _GrainState();
}

class _GrainState extends State<_Grain> {
  ui.Image? _tile;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      // The 4.5% is baked into the tile rather than applied with an `Opacity`
      // widget: that would save the entire screen to an offscreen buffer and
      // composite it back, every frame, to multiply one number.
      Paint()..color = const Color(0x0BFFFFFF),
    );
    final image = await recorder.endRecording().toImage(3, 3);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() => _tile = image);
  }

  @override
  void dispose() {
    _tile?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tile = _tile;
    if (tile == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(child: CustomPaint(painter: _GrainPainter(tile))),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter(this.tile);

  final ui.Image tile;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        ),
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.tile != tile;
}
