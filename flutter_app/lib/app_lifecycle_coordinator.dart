/// Coordinates app-level lifecycle work for every live agent.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'agent_tabs.dart';
import 'design/tokens.dart';

/// Pauses ambient rendering when the app leaves the foreground and validates
/// connections when it returns.
///
/// A suspended phone and a hidden desktop window both invalidate long-lived
/// sockets, but callers should not need to know which platform produced the
/// event. Active tabs are validated before background tabs so the visible
/// workspace recovers first.
class AppLifecycleCoordinator with WidgetsBindingObserver {
  AppLifecycleCoordinator(this._tabs);

  final AgentTabs _tabs;
  bool? _ambientWasPaused;
  bool _leftForeground = false;
  bool _validating = false;
  bool _validationRequestedAgain = false;

  /// Starts receiving lifecycle events from the engine.
  void attach() => WidgetsBinding.instance.addObserver(this);

  /// Stops receiving events and restores the ambient state this coordinator
  /// changed. Connections stay owned by their tabs.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restoreAmbientMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(handleLifecycleChange(state));
  }

  /// Applies [state] and completes the recovery work it requires.
  ///
  /// Public so lifecycle behaviour can be tested without synthesizing an
  /// engine lifecycle message.
  Future<void> handleLifecycleChange(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        _restoreAmbientMotion();
        if (!_leftForeground) return;
        _leftForeground = false;
        await _validateConnections();
      case AppLifecycleState.inactive:
        _pauseAmbientMotion();
      case AppLifecycleState.hidden:
        _pauseAmbientMotion();
        _leftForeground = true;
      case AppLifecycleState.paused:
        _pauseAmbientMotion();
        _leftForeground = true;
      case AppLifecycleState.detached:
        _pauseAmbientMotion();
    }
  }

  void _pauseAmbientMotion() {
    _ambientWasPaused ??= Materials.ambientPaused.value;
    Materials.ambientPaused.value = true;
  }

  void _restoreAmbientMotion() {
    final previous = _ambientWasPaused;
    if (previous != null) Materials.ambientPaused.value = previous;
    _ambientWasPaused = null;
  }

  Future<void> _validateConnections() async {
    if (_validating) {
      _validationRequestedAgain = true;
      return;
    }
    _validating = true;
    try {
      final snapshot = _tabs.tabs;
      final active = _tabs.active;
      if (active != null) await active.workspace.resumeFromBackground();

      final background = snapshot.where((tab) => tab != active).toList();
      if (background.isNotEmpty) {
        await Future.wait([
          for (final tab in background) tab.workspace.resumeFromBackground(),
        ]);
      }
    } finally {
      _validating = false;
      if (_validationRequestedAgain) {
        _validationRequestedAgain = false;
        await _validateConnections();
      }
    }
  }
}
