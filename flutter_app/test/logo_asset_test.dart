/// The mark on the connect screen and at the top of the drawer.
///
/// It exists because the file was *committed broken*: the PNG's IDAT chunk
/// declared 4096 bytes and 1890 remained, so every decode failed and both
/// places drew nothing. Nothing caught it — an `Image.asset` that cannot
/// decode logs to the console and renders empty, which on a dark screen is
/// indistinguishable from a mark that is simply small.
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _asset = 'assets/images/caduceus-pixel.png';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the mark decodes, and is square', () async {
    final data = await rootBundle.load(_asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    addTearDown(frame.image.dispose);

    expect(
      frame.image.width,
      frame.image.height,
      reason: 'the mark is drawn on a square grid',
    );
    expect(
      frame.image.width,
      greaterThanOrEqualTo(192),
      reason: 'it is drawn at 48pt on a 3x screen',
    );
  });

  test('and its art grid divides the size it is drawn at', () async {
    // `FilterQuality.none` is what keeps pixel art from turning to mush, and
    // it only works when the display size divides the grid — otherwise the
    // nearest-neighbour sampling doubles some rows and drops others, which is
    // the shattered look the contact sheet showed. 48 art pixels upscaled x8
    // gives 384, which divides evenly at 48pt, 24pt and 16pt.
    final data = await rootBundle.load(_asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    addTearDown(frame.image.dispose);

    expect(frame.image.width % 48, 0);
  });
}
