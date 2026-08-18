import 'dart:convert';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'native_bindings.dart';

class NativeBlockSpan {
  const NativeBlockSpan({
    required this.startOffset,
    required this.endOffset,
    required this.isFence,
  });

  final int startOffset;
  final int endOffset;
  final bool isFence;
}

class NativeSplitResult {
  const NativeSplitResult({
    required this.spans,
    required this.tailStart,
  });

  final List<NativeBlockSpan> spans;
  final int tailStart;
}

class MarkdownNative {
  /// Splits markdown text into settled block spans and tail offset using native C engine.
  /// Returns null if native engine is unavailable.
  static NativeSplitResult? splitBlocks(String text, {int maxBlocks = 1024}) {
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null || text.isEmpty) return null;

    final utf8Units = utf8.encode(text);
    final textPtr = malloc<ffi.Uint8>(utf8Units.length + 1);
    for (var i = 0; i < utf8Units.length; i++) {
      textPtr[i] = utf8Units[i];
    }
    textPtr[utf8Units.length] = 0;

    final spansPtr = malloc<CaduceusBlockSpanNative>(maxBlocks);
    final tailStartPtr = malloc<ffi.Int32>(1);

    try {
      final count = bindings.splitBlocks(
        textPtr.cast<Utf8>(),
        utf8Units.length,
        spansPtr,
        maxBlocks,
        tailStartPtr,
      );

      final spans = <NativeBlockSpan>[];
      for (var i = 0; i < count; i++) {
        final span = spansPtr[i];
        spans.add(NativeBlockSpan(
          startOffset: span.startOffset,
          endOffset: span.endOffset,
          isFence: span.isFence != 0,
        ));
      }

      return NativeSplitResult(
        spans: spans,
        tailStart: tailStartPtr.value,
      );
    } finally {
      malloc.free(textPtr);
      malloc.free(spansPtr);
      malloc.free(tailStartPtr);
    }
  }

  /// Normalizes markdown text to generate memory fingerprints using native C engine.
  static String? normalizeFingerprint(String text) {
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final utf8Units = utf8.encode(text);
    final inputPtr = malloc<ffi.Uint8>(utf8Units.length + 1);
    for (var i = 0; i < utf8Units.length; i++) {
      inputPtr[i] = utf8Units[i];
    }
    inputPtr[utf8Units.length] = 0;

    final outCap = utf8Units.length + 64;
    final outPtr = malloc<ffi.Uint8>(outCap);

    try {
      final written = bindings.normalizeFingerprint(
        inputPtr.cast<Utf8>(),
        utf8Units.length,
        outPtr.cast<Utf8>(),
        outCap,
      );
      if (written <= 0) return '';
      return outPtr.cast<Utf8>().toDartString(length: written);
    } finally {
      malloc.free(inputPtr);
      malloc.free(outPtr);
    }
  }
}
