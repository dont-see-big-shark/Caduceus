/// How many backdrop blurs a screen is allowed to open.
///
/// The design's budget is two blurred layers at once. Nesting is how that gets
/// blown without anyone noticing: a drawer is one sheet, and then its search
/// pill, its button and each of its rows quietly opens another — eleven
/// filters for one panel. The result is not only slow, it is *wrong*: the
/// inner filter blurs what the outer one already blurred, so the aurora turns
/// to flat grey haze and the material stops reading as glass.
library;

import 'package:caduceus/design/glass.dart';
import 'package:caduceus/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _blurs(WidgetTester tester) =>
    tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).length;

void main() {
  testWidgets('a lone sheet blurs its backdrop', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GlassPanel(child: Text('x'))),
      ),
    );
    expect(_blurs(tester), 1);
  });

  testWidgets('a sheet inside a sheet does not blur again', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassPanel(
            child: Column(
              children: [
                GlassPanel.pill(child: Text('search')),
                GlassPanel(child: Text('row')),
                GlassPanel(child: Text('another row')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      _blurs(tester),
      1,
      reason: 'only the outermost sheet bends the backdrop',
    );

    // The inner sheets are still *there* — the tint, border and lit rim are
    // what make them read as separate surfaces, and dropping those would trade
    // one bug for another.
    expect(find.text('search'), findsOneWidget);
    expect(find.text('row'), findsOneWidget);
  });

  testWidgets('degraded material opens no filters at all', (tester) async {
    Materials.degraded.value = true;
    addTearDown(() => Materials.degraded.value = false);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassPanel(child: GlassPanel(child: Text('x'))),
        ),
      ),
    );
    await tester.pump();

    expect(_blurs(tester), 0, reason: 'the blur is the cost being avoided');
    expect(find.text('x'), findsOneWidget);
  });
}
