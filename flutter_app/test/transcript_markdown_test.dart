/// `---` in an answer is a pause, not a piece of chrome.
///
/// The transcript ran on `MarkdownStyleSheet.fromTheme` defaults, which draw a
/// thematic break as a 5-point border in the divider colour. Models emit `---`
/// freely — between every numbered section of a long reply — so a two-part
/// answer arrived with grey bars across it heavy enough to read as part of the
/// app rather than part of what was written.
library;

import 'package:caduceus/design/theme.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

Future<MarkdownStyleSheet> _sheet(
  WidgetTester tester,
  Brightness brightness,
) async {
  late MarkdownStyleSheet sheet;
  late ThemeData theme;
  await tester.pumpWidget(
    MaterialApp(
      theme: caduceusTheme(brightness),
      home: Builder(
        builder: (context) {
          sheet = transcriptMarkdown(context);
          theme = Theme.of(context);
          return const SizedBox();
        },
      ),
    ),
  );
  // Guard against the comparison being vacuous: the default this replaces has
  // to actually draw something, or the test proves nothing.
  final stock =
      MarkdownStyleSheet.fromTheme(theme).horizontalRuleDecoration
          as BoxDecoration;
  expect(stock.border, isNotNull, reason: 'the default draws a rule');
  return sheet;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('the thematic break draws nothing in ${brightness.name}', (
      tester,
    ) async {
      final sheet = await _sheet(tester, brightness);
      final rule = sheet.horizontalRuleDecoration! as BoxDecoration;

      expect(rule.border, isNull);
      expect(rule.color, isNull);
      expect(rule.gradient, isNull);
    });

    testWidgets('and code still reads as machine text in ${brightness.name}', (
      tester,
    ) async {
      final sheet = await _sheet(tester, brightness);
      expect(sheet.code?.fontFamily, Fonts.mono);
    });
  }
}
