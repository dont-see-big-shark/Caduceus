/// Text has to be readable on the surface it actually sits on.
///
/// This used to assert against a `ColorScheme.fromSeed` — the theme the app
/// abandoned when the design system landed. It kept passing while covering
/// nothing the app draws, which is the quietest way for a test to stop being
/// a test.
///
/// Now it checks the real palette, on the real surfaces, in both modes.
/// Threshold is WCAG 2.1 AA: 4.5:1 for body text, 3:1 for large or supporting
/// text. Applied to text that has to be *read* — the deliberate 34% "faint"
/// step is a hierarchy signal on metadata, not something anyone reads a
/// sentence of.
library;

import 'dart:math' as math;

import 'package:caduceus/design/components.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Flattens a translucent colour onto an opaque one.
Color _over(Color top, Color bottom) => Color.from(
  alpha: 1,
  red: top.r * top.a + bottom.r * (1 - top.a),
  green: top.g * top.a + bottom.g * (1 - top.a),
  blue: top.b * top.a + bottom.b * (1 - top.a),
);

void main() {
  for (final dark in [true, false]) {
    final name = dark ? 'dark' : 'light';
    // The opaque plane long-form text lands on — the iron rule of the design.
    final plane = dark ? Palette.slate : Colors.white;
    final page = dark ? Palette.voidBlack : const Color(0xFFE4E7EF);
    final ink = dark ? Palette.snow : Palette.slate;

    test('body text is legible on the content plane in $name', () {
      for (final (step, label) in [
        (InkLevel.primary, 'primary'),
        (InkLevel.secondary, 'secondary'),
      ]) {
        expect(
          _contrast(_over(ink.withValues(alpha: step), plane), plane),
          greaterThanOrEqualTo(4.5),
          reason: '$label ink on the $name transcript',
        );
      }
    });

    test('the tertiary step clears supporting-text contrast in $name', () {
      // 50% carries a session's message count, a timestamp, a model id. Not
      // body copy, but still meant to be read.
      expect(
        _contrast(
          _over(ink.withValues(alpha: InkLevel.tertiary), plane),
          plane,
        ),
        greaterThanOrEqualTo(3),
      );
    });

    test('a status pill can be read in $name', () {
      // The pill is how a lost connection is reported: its label is the whole
      // message. It is tinted rather than filled, so the text sits on
      // something very close to the page behind it.
      for (final (colour, label) in [
        (Palette.jade, 'jade'),
        (Palette.brass, 'brass'),
        (Palette.coral, 'coral'),
      ]) {
        final pill = _over(colour.withValues(alpha: .12), page);
        // The function the widget actually calls, not a copy of its arithmetic
        // — a contrast test that re-implements the thing it is checking will
        // agree with itself forever.
        final text = statusInk(colour, dark: dark);
        expect(
          _contrast(text, pill),
          greaterThanOrEqualTo(4.5),
          reason: 'a $label status pill in $name',
        );
      }
    });

    testWidgets('danger text is legible in $name', (tester) async {
      // Coral lightened to read on slate measures 8.9:1 there and 2.2:1 on
      // white — a delete button nobody can read. The same mode-blind mistake
      // as the status pill, in four places.
      late Color ink;
      await tester.pumpWidget(
        MaterialApp(
          theme: caduceusTheme(dark ? Brightness.dark : Brightness.light),
          home: Builder(
            builder: (context) {
              ink = dangerInk(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        _contrast(ink, plane),
        greaterThanOrEqualTo(4.5),
        reason: 'destructive text on the $name content plane',
      );
    });

    test('the brass button label is legible in $name', () {
      // Brass is a light colour in both modes, so its label is near-black in
      // both — the one place this design does not flip with the theme.
      for (final stop in [Palette.brassLight, Palette.brassDeep]) {
        expect(
          _contrast(Palette.slate, stop),
          greaterThanOrEqualTo(4.5),
          reason: 'brass button label on $stop in $name',
        );
      }
    });

    testWidgets('the theme hands out ink that matches the mode in $name', (
      tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: caduceusTheme(dark ? Brightness.dark : Brightness.light),
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(captured.ink.base, ink);
    });
  }
}
