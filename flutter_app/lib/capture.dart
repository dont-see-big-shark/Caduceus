/// Getting bytes out of the device's own hardware.
///
/// The camera, the photo library and the microphone are the three things the
/// prototype's composer offers that no amount of layout work can fake. They
/// are behind an interface because every one of them is a platform channel
/// that does not exist under `flutter test`, and because "did the composer ask
/// for a photo" is a question worth being able to answer without a camera.
library;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Something the user captured, ready to attach.
@immutable
class Captured {
  const Captured({required this.name, required this.bytes, this.mimeType});

  final String name;
  final Uint8List bytes;
  final String? mimeType;
}

/// The camera and the photo library.
abstract interface class MediaCapture {
  /// A still from the camera. Null if the user backed out or said no.
  Future<Captured?> photo();

  /// A clip from the camera.
  Future<Captured?> video();

  /// A picture already in the library.
  Future<Captured?> fromLibrary();

  /// Whether this device has a camera to open at all.
  ///
  /// macOS has no `image_picker` camera implementation, and a tile that opens
  /// nothing is worse than a tile that is not there.
  bool get hasCamera;
}

class PlatformMediaCapture implements MediaCapture {
  PlatformMediaCapture({ImagePicker? picker, TargetPlatform? platform})
    : _picker = picker ?? ImagePicker(),
      _platform = platform ?? defaultTargetPlatform;

  final ImagePicker _picker;
  final TargetPlatform _platform;

  @override
  bool get hasCamera =>
      _platform == TargetPlatform.iOS || _platform == TargetPlatform.android;

  @override
  Future<Captured?> photo() => _read(
    _picker.pickImage(
      source: ImageSource.camera,
      // A modern phone camera produces 4000×3000 images of eight megabytes.
      // Nothing downstream benefits: the model reads a resized copy anyway,
      // and the upload happens over whatever the phone is holding onto.
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    ),
  );

  @override
  Future<Captured?> video() =>
      _read(_picker.pickVideo(source: ImageSource.camera));

  @override
  Future<Captured?> fromLibrary() => _read(
    _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    ),
  );

  Future<Captured?> _read(Future<XFile?> pick) async {
    final file = await pick;
    if (file == null) return null;
    return Captured(
      name: file.name,
      bytes: await file.readAsBytes(),
      mimeType: file.mimeType,
    );
  }
}

/// What a dictation session is doing.
enum Dictation { idle, listening, unavailable }

/// Speech to text, as a thing that fills the composer.
///
/// Deliberately *not* a "voice message": there is no audio channel to the
/// agent, and a recording the server cannot hear would be a button that looks
/// like it worked. What the microphone does here is type — the words land in
/// the field, where they can be read and corrected before they are sent.
abstract interface class VoiceInput {
  /// Asks for permission and starts listening. The callback fires on every
  /// partial result, so the field fills as the sentence is spoken.
  ///
  /// Returns false when the platform said no, or has no recogniser.
  Future<bool> start({
    required void Function(String text, bool finished) onResult,
    String? localeId,
  });

  Future<void> stop();

  bool get isListening;
}

class PlatformVoiceInput implements VoiceInput {
  PlatformVoiceInput({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _ready = false;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> start({
    required void Function(String text, bool finished) onResult,
    String? localeId,
  }) async {
    // `initialize` is what triggers the two iOS permission prompts, so it is
    // called on first use rather than at startup: a microphone dialog on the
    // very first launch, before anything has been said, reads as an app
    // asking for something it has not earned.
    _ready =
        _ready ||
        await _speech.initialize(onError: (_) {}, debugLogging: false);
    if (!_ready) return false;
    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        // Partial results are the whole point: the words appear as they are
        // said, so a misheard phrase is obvious before the sentence ends.
        partialResults: true,
        cancelOnError: true,
        // Long enough for a paragraph, and it stops on its own at the end of
        // a sentence anyway — a microphone left open is a battery and a
        // privacy problem at once.
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 4),
      ),
    );
    return true;
  }

  @override
  Future<void> stop() => _speech.stop();
}
