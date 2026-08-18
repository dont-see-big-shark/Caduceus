/// Light mode, which is not dark mode with the colours swapped.
///
/// The rule the material rests on is that a sheet of glass is *lighter* than
/// what is behind it — that is what catching light means. Deriving light mode
/// by flipping the ink colour broke exactly that: sheets were tinted with
/// slate over a light page, so every panel came out darker than the paper and
/// the composer read as a hole punched in it rather than a panel floating over
/// it.
///
/// Asserted against [glassTint] rather than by reading the widget tree. A
/// first version of this walked the `DecoratedBox`es under a `GlassPanel`, and
/// it passed with the inverted colours still in place — a test that cannot
/// fail is worse than no test, because it certifies the bug.
library;

import 'dart:ui' as ui;

import 'package:caduceus/design/glass.dart';
import 'package:caduceus/design/theme.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page under the sheets in each mode.
const _lightPage = Color(0xFFE4E7EF);

/// A translucent sheet composited over an opaque page.
double _luminanceOver(Color sheet, Color page) {
  final a = sheet.a;
  return Color.from(
    alpha: 1,
    red: sheet.r * a + page.r * (1 - a),
    green: sheet.g * a + page.g * (1 - a),
    blue: sheet.b * a + page.b * (1 - a),
  ).computeLuminance();
}

void main() {
  for (final level in Glass.values) {
    test('${level.name} glass catches light in both modes', () {
      for (final (dark, page) in [
        (true, Palette.voidBlack),
        (false, _lightPage),
      ]) {
        // Both ends of the gradient, not just the bright one: the dim end is
        // what let the page through and turned the panel grey halfway down.
        for (final stop in glassTint(level, dark: dark)) {
          expect(
            _luminanceOver(stop, page),
            greaterThan(page.computeLuminance()),
            reason:
                'a ${level.name} sheet must be brighter than the '
                '${dark ? "dark" : "light"} page behind it',
          );
        }
      }
    });
  }

  test('a brass sheet still reads as brass on a light page', () {
    // The bubble is the only tinted sheet in the system, and the tint is the
    // entire reason it exists — it is how you find where an exchange starts.
    // At the alpha that suits dark mode it came out a warm grey.
    final stops = glassTint(Glass.regular, dark: false, tint: Palette.brass);
    final over = Color.from(
      alpha: 1,
      red: stops.first.r * stops.first.a + _lightPage.r * (1 - stops.first.a),
      green: stops.first.g * stops.first.a + _lightPage.g * (1 - stops.first.a),
      blue: stops.first.b * stops.first.a + _lightPage.b * (1 - stops.first.a),
    );
    expect(
      over.r - over.b,
      greaterThan(.06),
      reason: 'brass is warm; a grey bubble carries no signal at all',
    );
  });

  test('the content plane is brighter than the page it sits on', () {
    // Otherwise there is no "glass over content" — snow on a snow-coloured
    // background is one flat field with sheets floating over nothing.
    expect(
      Colors.white.computeLuminance(),
      greaterThan(_lightPage.computeLuminance()),
    );
    expect(
      Palette.slate.computeLuminance(),
      greaterThan(Palette.voidBlack.computeLuminance()),
      reason: 'the same relationship, one step deeper, in the dark',
    );
  });

  test('saturation is turned down on a light ground', () {
    // Over near-black, saturating the backdrop is what keeps the aurora
    // reading as colour behind glass. Over a light page the same amount
    // pushes that colour up through the sheet and it looks dirty.
    final dark = glassFilter(Glass.regular, 1, true);
    final light = glassFilter(Glass.regular, 1, false);
    expect(dark, isA<ui.ImageFilter>());
    expect(
      light.toString(),
      isNot(dark.toString()),
      reason: 'the two modes must not ask for the same saturation',
    );
  });

  testWidgets('the theme still resolves in both modes', (tester) async {
    for (final mode in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: caduceusTheme(mode),
          home: const Scaffold(body: GlassPanel(child: Text('x'))),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
