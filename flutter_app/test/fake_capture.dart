/// Stand-ins for the camera and the speech recogniser.
///
/// Both are platform channels that do not exist under `flutter test`, and both
/// are worth testing anyway: "did the composer ask for a photo, and did the
/// bytes reach the session" is the question, and it does not need a camera.
library;

import 'package:caduceus/capture.dart';
import 'package:flutter/foundation.dart';

class FakeMedia implements MediaCapture {
  FakeMedia({this.hasCamera = true, this.result, this.throws});

  @override
  final bool hasCamera;

  /// What each source hands back. Null stands for the user backing out, which
  /// is indistinguishable from a refusal at the system prompt and should be.
  final Captured? result;

  /// Thrown instead, for the path where the platform itself fails.
  final Object? throws;

  final calls = <String>[];

  Future<Captured?> _run(String name) async {
    calls.add(name);
    if (throws case final e?) throw e as Exception;
    return result;
  }

  @override
  Future<Captured?> photo() => _run('photo');

  @override
  Future<Captured?> video() => _run('video');

  @override
  Future<Captured?> fromLibrary() => _run('library');
}

class FakeVoice implements VoiceInput {
  FakeVoice({this.available = true});

  /// False stands for a refused permission or a device with no recogniser.
  final bool available;

  @override
  bool isListening = false;

  void Function(String text, bool finished)? _onResult;
  int starts = 0;
  int stops = 0;

  /// Speaks. `finished` marks the recogniser closing itself, which is what
  /// ends a dictation without the user tapping anything.
  void say(String text, {bool finished = false}) {
    _onResult?.call(text, finished);
    if (finished) isListening = false;
  }

  @override
  Future<bool> start({
    required void Function(String text, bool finished) onResult,
    String? localeId,
  }) async {
    starts++;
    if (!available) return false;
    _onResult = onResult;
    isListening = true;
    return true;
  }

  @override
  Future<void> stop() async {
    stops++;
    isListening = false;
  }
}

Captured photoBytes([String name = 'IMG_0042.jpg']) => Captured(
  name: name,
  bytes: Uint8List.fromList(const [137, 80, 78, 71]),
  mimeType: 'image/jpeg',
);
