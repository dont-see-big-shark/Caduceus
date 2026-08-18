/// [ThemeData] assembled from the Liquid Glass tokens.
library;

import 'package:flutter/material.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

import 'tokens.dart';

/// Text on this design is layered by opacity, so widgets need the *base* ink
/// colour and the four steps, not a pile of named colours.
@immutable
class InkTheme extends ThemeExtension<InkTheme> {
  const InkTheme({required this.base});

  final Color base;

  Color get primary => base.withValues(alpha: InkLevel.primary);
  Color get secondary => base.withValues(alpha: InkLevel.secondary);
  Color get tertiary => base.withValues(alpha: InkLevel.tertiary);
  Color get faint => base.withValues(alpha: InkLevel.faint);

  /// A hairline in the ink colour — dividers, edges of non-glass surfaces.
  Color get hairline => base.withValues(alpha: .12);

  @override
  InkTheme copyWith({Color? base}) => InkTheme(base: base ?? this.base);

  @override
  InkTheme lerp(InkTheme? other, double t) => other == null
      ? this
      : InkTheme(base: Color.lerp(base, other.base, t) ?? base);
}

/// Shorthand at the call site: `context.ink.secondary`.
extension InkAccess on BuildContext {
  InkTheme get ink =>
      Theme.of(this).extension<InkTheme>() ??
      const InkTheme(base: Palette.snow);
}

/// The type ramp.
///
/// Body is 15/1.8 with a 72-character measure. The serif appears in exactly
/// three places — welcome, empty session, and a consequential confirmation —
/// and is therefore *not* wired into `displayLarge` where it would leak
/// everywhere; ask for [serifDisplay] deliberately.
TextTheme _textTheme(Color ink) {
  TextStyle sans(double size, {FontWeight? weight, double? height}) =>
      TextStyle(
        fontFamily: Fonts.sans,
        fontFamilyFallback: Fonts.sansFallback,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: ink,
      );

  return TextTheme(
    // Section headings inside panels.
    titleLarge: sans(17, weight: FontWeight.w600, height: 1.3),
    titleMedium: sans(15, weight: FontWeight.w500, height: 1.4),
    titleSmall: sans(14, weight: FontWeight.w500, height: 1.4),
    bodyLarge: sans(15, height: 1.8),
    bodyMedium: sans(14, height: 1.7),
    bodySmall: sans(
      13,
      height: 1.75,
    ).copyWith(color: ink.withValues(alpha: InkLevel.tertiary)),
    labelLarge: sans(14, weight: FontWeight.w500),
    labelMedium: sans(13),
    // The 11 px tracked-out uppercase eyebrow over every group in the design.
    labelSmall: sans(11, weight: FontWeight.w500).copyWith(
      letterSpacing: 1.9,
      color: ink.withValues(alpha: InkLevel.tertiary),
    ),
  );
}

/// 只在三处出现. Use it sparingly enough that it still means something.
TextStyle serifDisplay(BuildContext context, {double size = 34}) => TextStyle(
  fontFamily: Fonts.serif,
  fontFamilyFallback: Fonts.sansFallback,
  fontSize: size,
  height: 1.1,
  letterSpacing: -.3,
  color: context.ink.primary,
);

/// Addresses, tokens, code, elapsed times — anything quoted from the machine.
TextStyle mono(BuildContext context, {double size = 12, double? opacity}) =>
    TextStyle(
      fontFamily: Fonts.mono,
      fontFamilyFallback: Fonts.monoFallback,
      fontSize: size,
      height: 1.5,
      color: context.ink.base.withValues(alpha: opacity ?? InkLevel.secondary),
    );

ThemeData caduceusTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? Palette.snow : Palette.slate;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: Palette.brass,
    // Brass is a light colour: text on it has to be near-black in both modes,
    // which is also what the primary button in the source does.
    onPrimary: Palette.slate,
    secondary: Palette.azure,
    onSecondary: Palette.snow,
    error: Palette.coral,
    onError: Palette.slate,
    // White, not snow: every opaque surface in this design sits *above*
    // the page, and the light page is now a step deeper than the sheets on
    // it. Snow was drawn for a page that no longer exists.
    surface: dark ? Palette.slate : Colors.white,
    onSurface: ink,
    surfaceTint: Colors.transparent,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    // The aurora is the background. Anything opaque behind it would hide it.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    fontFamily: Fonts.sans,
    fontFamilyFallback: Fonts.sansFallback,
    textTheme: _textTheme(ink),
    dividerColor: ink.withValues(alpha: .12),
    visualDensity: VisualDensity.standard,
    splashFactory: NoSplash.splashFactory,
    // Material's ink ripple is a different design language than this one:
    // feedback here is the glass brightening and the press spring.
    highlightColor: Colors.transparent,
    hoverColor: ink.withValues(alpha: .05),
    extensions: [InkTheme(base: ink)],
    iconTheme: IconThemeData(
      color: ink.withValues(alpha: InkLevel.secondary),
      size: 18,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? Palette.slate : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: Radii.largeAll),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark
          ? Palette.slate.withValues(alpha: .96)
          : Colors.white.withValues(alpha: .98),
      surfaceTintColor: Colors.transparent,
      elevation: 18,
      shape: const RoundedRectangleBorder(borderRadius: Radii.mediumAll),
      textStyle: TextStyle(
        fontFamily: Fonts.sans,
        fontFamilyFallback: Fonts.sansFallback,
        fontSize: 13,
        color: ink,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? Palette.slate : Colors.white,
      contentTextStyle: TextStyle(
        fontFamily: Fonts.sans,
        fontFamilyFallback: Fonts.sansFallback,
        fontSize: 13,
        color: ink,
      ),
      shape: const RoundedRectangleBorder(borderRadius: Radii.mediumAll),
      behavior: SnackBarBehavior.floating,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Palette.brass,
      selectionColor: Palette.brass.withValues(alpha: .28),
      selectionHandleColor: Palette.brass,
    ),
  );
}

/// How the transcript renders Markdown.
///
/// Everything not named here still comes from the theme — this exists for the
/// handful of places where the renderer's defaults contradict the design.
///
/// **The thematic break.** `MarkdownStyleSheet.fromTheme` draws `---` as a
/// 5-point border in the divider colour, which on a phone is a grey bar across
/// the conversation heavy enough to read as a section of chrome rather than a
/// mark in someone's answer. Models emit `---` freely — between every numbered
/// section of a long reply — so the transcript ended up striped. The break is
/// still *there*, as the space it was asking for: a rule is a request for a
/// pause, and the pause is what the reader actually needed.
MarkdownStyleSheet transcriptMarkdown(BuildContext context) {
  final theme = Theme.of(context);
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    horizontalRuleDecoration: const BoxDecoration(),
    blockquoteDecoration: BoxDecoration(
      color: context.ink.base.withValues(alpha: .04),
      border: Border(
        left: BorderSide(color: Palette.brass.withValues(alpha: .5), width: 2),
      ),
    ),
    code: mono(context, size: 12.5),
    codeblockDecoration: BoxDecoration(
      color: context.ink.base.withValues(alpha: .05),
      borderRadius: Radii.smallAll,
    ),
  );
}
