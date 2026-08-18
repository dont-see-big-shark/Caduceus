/// Links in the transcript have to do something, and file paths are special.
///
/// MarkdownBody renders links in link colours whether or not a tap is handled,
/// so having no handler was worse than plain text: it promised something the
/// app did not do.
library;

import 'package:caduceus/widgets/transcript_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a file: link explains itself and offers the path', (
    tester,
  ) async {
    // These paths belong to the machine running the agent, and the control
    // plane has no method for reading a file back — file.attach, image.attach
    // and pdf.attach all push *to* the server. Downloading is not possible, so
    // the honest move is saying so and handing over the path.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openTranscriptLink(context, 'file:///srv/project/report.pdf'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('not on this device'),
      findsOneWidget,
      reason: 'the reason it cannot be downloaded has to be stated',
    );
    expect(
      find.text('/srv/project/report.pdf'),
      findsOneWidget,
      reason: 'the scheme is stripped: this is meant for scp or an editor',
    );

    await tester.tap(find.text('Copy path'));
    await tester.pumpAndSettle();
    expect(copied, '/srv/project/report.pdf');
  });

  testWidgets('an empty or unparseable href does nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openTranscriptLink(context, '   '),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
