/// The design tokens of *方向 C · 流光 Liquid Glass*.
///
/// One source for both platforms. The two shells differ in layout — a Mac has
/// a permanent sidebar, a phone has a drawer — but the material, the palette,
/// the type ramp and the motion are identical, which is what makes them look
/// like one product rather than two ports.
library;

import 'package:flutter/widgets.dart';

/// 深空、极光、一处黄铜.
///
/// The three aurora colours ([azure], [violet], [jade]) live in the background
/// light and in tiny indicators — never as a foreground fill. Foreground is
/// snow, brass, and coral for danger. That restraint is what keeps the glass
/// looking like a material instead of a colour scheme.
abstract final class Palette {
  /// The page under everything.
  static const voidBlack = Color(0xFF04050A);

  /// Opaque panels. Long-form text lands here, never on glass.
  static const slate = Color(0xFF0A0C13);

  static const snow = Color(0xFFF3F4F8);
  static const brass = Color(0xFFE3C08A);

  /// Brass, lit — the top of the primary button's gradient.
  static const brassLight = Color(0xFFF6E4C4);

  /// Brass, in shadow — the bottom of it.
  static const brassDeep = Color(0xFFDBB379);

  /// The true base of the primary's gradient.
  ///
  /// The gradient ran brassLight → brassDeep, and those two sit close enough
  /// together that the button read as a flat gold disc with a slight wash on
  /// it. What makes a small circle look like an object is the *range*: light
  /// gathers along the top edge and the base is genuinely in shadow.
  static const brassShadow = Color(0xFFC08F52);

  static const azure = Color(0xFF5B7CFA);
  static const violet = Color(0xFF9B6BF0);
  static const jade = Color(0xFF2ED3A5);
  static const coral = Color(0xFFFF6B63);

  /// Coral is unreadable as text at 14 px; this is the tint used for labels.
  static const coralText = Color(0xFFFF9088);
}

/// Brass is one material, so its gradient is written down once.
///
/// It was inlined at three call sites — the connect pill, the morph button and
/// the send circle — which is three chances for the one primary control in the
/// system to stop looking like itself depending on which screen you are on.
const brassSheen = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Palette.brassLight, Palette.brass, Palette.brassShadow],
  // The light lives in the top third and the fall into shadow takes the rest,
  // which is how a curved surface actually catches it. An even ramp between
  // two close tones reads as a printed swatch.
  stops: [0, .38, 1],
);

/// Text hierarchy is opacity, not colour: 100 / 70 / 50 / 34.
///
/// Four steps and no more. Every "just slightly dimmer" one-off is how a
/// palette turns into mud.
abstract final class InkLevel {
  static const primary = 1.0;
  static const secondary = .70;
  static const tertiary = .50;
  static const faint = .34;
}

/// Three thicknesses of glass, and the rule for which one to use.
///
/// The tint percentages are a gradient from top-left to bottom-right, which is
/// what makes a panel read as a *sheet* catching light rather than a flat fill.
enum Glass {
  /// List rows, grouping containers. Barely more than a mist.
  thin(
    blur: 18,
    saturate: 1.6,
    tintTop: .09,
    tintBottom: .03,
    border: .11,
    highlight: .22,
    shadow: 0,
  ),

  /// Sidebars, toolbars, inputs. The default — 90% of chrome is this.
  regular(
    blur: 28,
    saturate: 1.8,
    tintTop: .15,
    tintBottom: .05,
    border: .18,
    highlight: .36,
    shadow: 40,
  ),

  /// Popovers, the command palette, modals. Furthest from the page.
  ///
  /// The border is deliberately higher than the sheet tint so a popover still
  /// reads as a *card with edges* over whatever is behind it — at `.26` the
  /// hairline melted into the glass and the corners looked frameless.
  thick(
    blur: 40,
    saturate: 2.0,
    tintTop: .22,
    tintBottom: .08,
    border: .5,
    highlight: .50,
    shadow: 70,
  );

  const Glass({
    required this.blur,
    required this.saturate,
    required this.tintTop,
    required this.tintBottom,
    required this.border,
    required this.highlight,
    required this.shadow,
  });

  /// Backdrop blur sigma. Also the thing that costs GPU time, which is why
  /// [Materials.degraded] exists.
  final double blur;
  final double saturate;
  final double tintTop;
  final double tintBottom;
  final double border;

  /// The 1 px inset line along the top edge. This single detail is most of
  /// what separates "glass" from "a translucent rectangle".
  final double highlight;

  /// Drop shadow blur radius; 0 means the sheet sits flat on the page.
  final double shadow;
}

/// Corner radii. Pill is a real value, not `999` used as a sentinel.
abstract final class Radii {
  static const small = Radius.circular(12);
  static const medium = Radius.circular(16);
  static const large = Radius.circular(22);
  static const xlarge = Radius.circular(26);
  static const pill = Radius.circular(999);

  static const smallAll = BorderRadius.all(small);
  static const mediumAll = BorderRadius.all(medium);
  static const largeAll = BorderRadius.all(large);
  static const xlargeAll = BorderRadius.all(xlarge);
  static const pillAll = BorderRadius.all(pill);
}

/// 动 — 材料的物理，而非动画.
///
/// Three curves and four durations for the whole product. An interaction that
/// wants a fifth is nearly always an interaction that should have reused one.
abstract final class Motion {
  /// Hover, selection, switches. 90% of interactions.
  static const standard = Duration(milliseconds: 200);
  static const standardCurve = Cubic(.32, .72, 0, 1);

  /// Page-level: drawers, the command palette, switching sessions.
  static const emphasized = Duration(milliseconds: 320);
  static const emphasizedCurve = Cubic(.2, 0, 0, 1);

  /// Disappearing is always half the speed of appearing — never make someone
  /// wait for a dismissal.
  static const exit = Duration(milliseconds: 160);
  static const exitCurve = Cubic(.4, 0, 1, 1);

  /// Ambient loops mean exactly one thing: this is alive. Connection,
  /// generation, background work.
  static const ambient = Duration(milliseconds: 2400);

  /// Per-item delay when a list or menu enters.
  static const stagger = Duration(milliseconds: 24);

  /// Past this many items the stagger stops and the rest arrive together —
  /// otherwise the last row of a long list lands a second late.
  static const staggerCap = 8;

  /// The press spring: down to .94 over 90 ms, then released with an
  /// overshoot to ~1.02 before settling.
  static const pressScale = .94;
  static const pressDown = Duration(milliseconds: 90);
  static const springStiffness = 420.0;
  static const springDamping = 22.0;

  /// A destructive hold, and the fast rewind if the finger leaves early.
  static const hold = Duration(milliseconds: 900);
  static const holdRewind = Duration(milliseconds: 240);
}

/// Type. Serif for moments, sans for everything, mono for machine facts.
abstract final class Fonts {
  /// 只在三处出现：欢迎页、空会话、以及重大确认。
  ///
  /// The serif is not decoration — it is what gives the product somewhere to
  /// pause. Spend it anywhere else and it stops meaning anything.
  static const serif = 'InstrumentSerif';
  static const sans = 'InstrumentSans';

  /// Addresses, tokens, code, and elapsed times. Anything the machine said
  /// verbatim, so it can be read character by character.
  static const mono = 'IBMPlexMono';

  /// Ordered fallbacks: Latin first, then the CJK face, then the platform.
  static const sansFallback = ['Noto Sans SC', '.SF Pro Text', 'PingFang SC'];
  static const monoFallback = ['SF Mono', 'Menlo', 'Noto Sans SC'];
}

/// Runtime material policy.
///
/// `backdrop_filter` is a real GPU cost, and the design calls for at most two
/// blurred layers on screen at once. [degraded] swaps every sheet for solid
/// slate with a 1 px edge: the look drops, the structure and every duration
/// stay exactly the same, so the app feels identical on hardware that cannot
/// afford the blur.
abstract final class Materials {
  static final degraded = ValueNotifier<bool>(false);

  /// Ambient loops are suspended while a list is being dragged. A 30 s drift
  /// animation repainting behind a scrolling transcript is the one place this
  /// design can cost frames on hardware that could otherwise afford it.
  static final ambientPaused = ValueNotifier<bool>(false);
}

/// Whether looping motion may run right now.
///
/// Three ways to say no, and all of them matter:
///  * the user asked their OS to reduce motion — for some people this design's
///    drifting light is not atmosphere, it is a symptom trigger;
///  * the material is degraded, where the loop is the cost being avoided;
///  * something is being scrolled, and ambient repaints are competing with it.
///
/// Everything that stops here is decoration. No state, no progress and no
/// affordance is expressed by an ambient loop alone — that is what makes it
/// safe to switch off.
bool ambientAllowed(BuildContext context) =>
    !Materials.ambientPaused.value &&
    !Materials.degraded.value &&
    !MediaQuery.disableAnimationsOf(context);
