/// Applies to every test under `test/` — Flutter runs this automatically.
library;

import 'dart:async';

import 'package:caduceus/design/tokens.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The design has deliberate endless motion: the aurora drifts, the brass
  // button catches light, a running turn lights the composer's rim. Those
  // loops never finish, and `pumpAndSettle` waits for exactly that — so a
  // widget test that opens the drawer would hang rather than fail, which is
  // the worst way for a suite to tell you something.
  //
  // Freezing ambient motion for tests is the same switch the app already uses
  // while a list is being dragged and on reduced-motion devices, so this is
  // not a test-only code path: it is a supported state of the UI.
  Materials.ambientPaused.value = true;
  await testMain();
}
