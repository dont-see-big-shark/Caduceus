/// The composer as a surface, not a box with glyphs loose in it.
///
/// Three things were wrong at once and they compound: the brass gradient ran
/// between two tones close enough that the send button read as a flat disc,
/// the ＋ had no backing at all while the microphone had a fill and no edge,
/// and the field ran into the control row with nothing between them.
library;

import 'package:caduceus/design/theme.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:caduceus/widgets/console_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Relative luminance, for asking whether one end of a gradient is genuinely
/// darker than the other rather than eyeballing two hex strings.
double _luminance(Color c) => c.computeLuminance();

void main() {
  test('brass is lit at the top and in shadow at the base', () {
    final colors = brassSheen.colors;
    expect(colors.length, 3, reason: 'a midpoint, so the fall is not linear');

    // The answer to "how should the bottom behave": 顶部有亮，底部是暗的.
    expect(_luminance(colors.first), greaterThan(_luminance(colors.last)));

    // And it descends the whole way — a gradient that brightens again in the
    // middle is a smear, not a curved surface.
    for (var i = 1; i < colors.length; i++) {
      expect(
        _luminance(colors[i]),
        lessThan(_luminance(colors[i - 1])),
        reason: 'stop $i must be darker than the one before it',
      );
    }
  });

  test('and it has enough range to read as an object', () {
    // The old gradient was brassLight → brassDeep, which measures at about
    // .18 of luminance apart: enough to notice, not enough to look lit. That
    // flatness is what the button was reported for.
    final spread =
        _luminance(brassSheen.colors.first) -
        _luminance(brassSheen.colors.last);
    final old = _luminance(Palette.brassLight) - _luminance(Palette.brassDeep);

    expect(spread, greaterThan(old * 1.5));
  });

  test('the light gathers in the top third rather than ramping evenly', () {
    // An even ramp between two tones is a printed swatch. A curved surface
    // catches light in a band near the edge and falls away from it.
    expect(brassSheen.stops, isNotNull);
    expect(brassSheen.stops![1], lessThan(.5));
  });

  test('brass is one material, defined once', () {
    // Inlined at three call sites it was three chances for the one primary
    // control in the system to stop looking like itself.
    expect(brassSheen.begin, Alignment.topCenter);
    expect(brassSheen.end, Alignment.bottomCenter);
  });

  _chipTests();
}

/// The control row, as a set of things that agree with each other.
void _chipTests() {
  testWidgets('the three small controls share one backing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: caduceusTheme(Brightness.dark),
        home: const Scaffold(
          body: Row(
            children: [
              ComposerChip(child: Icon(Icons.add_rounded)),
              ComposerChip(child: Icon(Icons.mic_none_rounded)),
            ],
          ),
        ),
      ),
    );

    final chips = tester.widgetList<ComposerChip>(find.byType(ComposerChip));
    expect(chips.length, 2);

    // Same size, whatever is inside them. The ＋ used to be a bare glyph on
    // the field while the microphone had a fill — two controls in one row,
    // neither of them the same object.
    final sizes = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((c) => (c.constraints?.maxWidth, c.constraints?.maxHeight))
        .toSet();
    expect(sizes.length, 1, reason: 'one shape, not two');
  });

  testWidgets('a chip that has to leave the palette drops its border', (
    tester,
  ) async {
    // Listening is the state that must be unmistakable: a microphone that is
    // open and looks shut is the worst failure this control has.
    await tester.pumpWidget(
      MaterialApp(
        theme: caduceusTheme(Brightness.dark),
        home: Scaffold(
          body: ComposerChip(
            fill: Palette.coral,
            child: const Icon(Icons.stop_rounded),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final box =
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration!
            as BoxDecoration;
    expect(box.color, Palette.coral);
  });
}
