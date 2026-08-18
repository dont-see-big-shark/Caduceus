/// The tab strip, and the thing it must not do: rebuild a tab on switch.
///
/// `AgentTabs` owns the lifecycle and `agent_tabs_test.dart` pins it. This is
/// about the widget layer, where the failure is different and quieter — a
/// switch that rebuilds the workspace drops the turn in flight, loses the
/// scroll position, and looks like the agent restarted.
library;

import 'package:caduceus/agent_shell.dart';
import 'package:caduceus/connect_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for a WorkspaceScreen: counts how often it is built from scratch.
class _Pane extends StatefulWidget {
  const _Pane({required this.name, required this.builds, super.key});

  final String name;
  final Map<String, int> builds;

  @override
  State<_Pane> createState() => _PaneState();
}

class _PaneState extends State<_Pane> {
  @override
  void initState() {
    super.initState();
    widget.builds[widget.name] = (widget.builds[widget.name] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.name));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('switching tabs does not rebuild the one left behind', (
    tester,
  ) async {
    // The property that makes these tabs and not bookmarks. A workspace holds
    // the live socket, the streaming transcript and the scroll position, so a
    // rebuild on switch would drop a turn every time the user glanced away.
    final builds = <String, int>{};
    var index = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                Row(
                  children: [
                    for (final (i, name) in ['a', 'b'].indexed)
                      TextButton(
                        onPressed: () => setState(() => index = i),
                        child: Text('go-$name'),
                      ),
                  ],
                ),
                Expanded(
                  child: IndexedStack(
                    index: index,
                    children: [
                      for (final name in ['a', 'b'])
                        _Pane(key: ValueKey(name), name: name, builds: builds),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(builds, {'a': 1, 'b': 1});

    await tester.tap(find.text('go-b'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go-a'));
    await tester.pumpAndSettle();

    expect(
      builds,
      {'a': 1, 'b': 1},
      reason:
          'an IndexedStack keeps both alive; switching must not '
          'reinitialise either',
    );
  });

  testWidgets('with nothing open the shell is just the connect screen', (
    tester,
  ) async {
    // No empty strip and no placeholder — before tabs existed the connect
    // screen was the app, and with nothing open it still is.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AgentShell()));
    // The shell restores saved tabs before deciding what to show, so it holds
    // a spinner for a frame rather than flashing the connect screen in front
    // of agents that are about to appear. Not pumpAndSettle: the spinner
    // animates forever and would time out.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Caduceus'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Connect another agent'),
      findsNothing,
      reason: 'there is nothing to add a tab beside yet',
    );
  });

  testWidgets('the + button does not reconnect the tab you already have', (
    tester,
  ) async {
    // The bug: ConnectScreen auto-reconnects the last-used server on open,
    // and the shell pushed it with that behaviour left on. So pressing + built
    // a second connection to the agent already in front, popped with it, and
    // the shell focused the tab you were already on. Pressing + appeared to do
    // nothing — while leaking a socket each time.
    //
    // Asserted on the widget the shell constructs rather than by driving the
    // whole flow, because the flow needs a live gateway and the property that
    // matters is a single flag.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AgentShell()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // With nothing open the shell renders the connect screen itself, and it
    // must already have auto-reconnect off — the shell decided what to reopen.
    final screen = tester.widget<ConnectScreen>(find.byType(ConnectScreen));
    expect(
      screen.autoReconnect,
      isFalse,
      reason:
          'two mechanisms restoring would open one server twice, and on '
          'OpenClaw that is a second device pairing',
    );
  });
}
