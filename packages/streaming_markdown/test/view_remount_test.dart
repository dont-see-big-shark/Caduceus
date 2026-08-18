/// A view that is torn down and rebuilt must keep rendering.
///
/// Flutter mounts the replacement element before unmounting the one it
/// replaced, so the old state's `dispose` runs *after* the new state's
/// `initState`. When the surrounding layout inserts a widget above the
/// transcript — a reasoning pane, a tool strip — an unkeyed parent rebuilds the
/// view into a new slot and that ordering used to leave the controller with no
/// listener at all: tokens kept arriving and nothing rendered again.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streaming_markdown/streaming_markdown.dart';

/// Mirrors the console: a banner that appears mid-stream, above the transcript.
class _Host extends StatefulWidget {
  const _Host({required this.controller, super.key});
  final StreamingMarkdownController controller;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool banner = false;

  void showBanner() => setState(() => banner = true);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (banner) const Text('banner'),
      Expanded(child: StreamingMarkdownView(controller: widget.controller)),
    ],
  );
}

void main() {
  testWidgets('a banner appearing above the view does not freeze it', (
    tester,
  ) async {
    final controller = StreamingMarkdownController();
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _Host(key: key, controller: controller),
        ),
      ),
    );

    controller.append('before\n\n');
    await tester.pumpAndSettle();
    expect(find.text('before'), findsOneWidget);

    // The insertion shifts the transcript down one slot, remounting it.
    key.currentState!.showBanner();
    await tester.pumpAndSettle();
    expect(find.text('banner'), findsOneWidget);
    expect(
      find.text('before'),
      findsOneWidget,
      reason: 'settled content survives the remount',
    );

    controller.append('after\n\n');
    await tester.pumpAndSettle();
    expect(
      find.text('after'),
      findsOneWidget,
      reason: 'the remounted view must still be receiving appends',
    );

    controller.dispose();
  });

  testWidgets('detaching a stale view does not unhook the live one', (
    tester,
  ) async {
    // The same thing at the unit level: two views over one controller, the
    // second replacing the first.
    final controller = StreamingMarkdownController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownView(
            key: const ValueKey('a'),
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StreamingMarkdownView(
            key: const ValueKey('b'),
            controller: controller,
          ),
        ),
      ),
    );

    controller.append('still live\n\n');
    await tester.pumpAndSettle();
    expect(find.text('still live'), findsOneWidget);

    controller.dispose();
  });
}
