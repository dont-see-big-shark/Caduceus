import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Touch feedback, on the platforms that have it.
///
/// A phone has no hover state and no cursor change, so a tap that starts
/// something slow — sending a prompt, interrupting a turn — gives no signal
/// that it registered until the result arrives. On iOS that gap is what makes
/// an app feel unresponsive even when it is working, and it is the reason
/// people tap a second time.
///
/// The mapping is the design's, and it is a *vocabulary*: four distinct
/// sensations, each meaning one thing, so the hand can tell them apart without
/// the eyes.
///
///   send a message      light impact
///   a tool finished     two selection clicks
///   needs approval      medium impact
///   something failed    heavy impact
///
/// Deliberately silent on desktop: `HapticFeedback` is a no-op there, but
/// routing every button through a platform channel that does nothing is waste
/// on the platform where the benchmark runs.
abstract final class Haptics {
  static bool get _enabled =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// 连点时按 120ms 节流.
  ///
  /// Without it a burst — rapid taps, or a turn finishing three tool calls in
  /// the same second — fires a run of pulses the hand reads as one long buzz.
  /// Every distinction in the vocabulary above is lost exactly when the most
  /// is happening.
  static const _floor = Duration(milliseconds: 120);
  static DateTime? _last;

  /// The throttle is wall-clock based, which a widget test has no patience
  /// for. Resetting between cases keeps them independent.
  @visibleForTesting
  static void resetThrottle() => _last = null;

  static bool _allow() {
    final now = DateTime.now();
    final last = _last;
    if (last != null && now.difference(last) < _floor) return false;
    _last = now;
    return true;
  }

  /// A committed action: send, interrupt, confirm.
  ///
  /// Sound as well as vibration. A phone on a desk, or in a silent-switch-off
  /// pocket, gives the two to different senses, and the system click is the
  /// one iOS users already associate with "that registered".
  static void tap() {
    if (!_enabled || !_allow()) return;
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  /// A choice among options: picking a model, answering a clarify.
  static void select() {
    if (!_enabled || !_allow()) return;
    HapticFeedback.selectionClick();
    SystemSound.play(SystemSoundType.click);
  }

  /// A tool call finished — 工具完成＝双轻.
  ///
  /// Two clicks rather than one, so it cannot be mistaken for the user's own
  /// tap. This is the app reporting, not acknowledging.
  static Future<void> toolDone() async {
    if (!_enabled || !_allow()) return;
    await HapticFeedback.selectionClick();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await HapticFeedback.selectionClick();
  }

  /// Something is waiting on the user — an approval, a blocking prompt.
  ///
  /// Medium: heavier than an acknowledgement, lighter than a failure, because
  /// nothing has gone wrong. Not throttled — a request for permission that
  /// arrives silently because something else buzzed 100 ms ago is the one case
  /// where dropping the signal costs more than repeating it.
  static void needsAttention() {
    if (!_enabled) return;
    _last = DateTime.now();
    HapticFeedback.mediumImpact();
  }

  /// Something the user should notice went wrong.
  static void warn() {
    if (!_enabled) return;
    _last = DateTime.now();
    HapticFeedback.heavyImpact();
  }
}
