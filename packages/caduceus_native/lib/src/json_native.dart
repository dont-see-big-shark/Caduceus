import 'dart:convert';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'native_bindings.dart';

class JsonNative {
  /// Extracts the string/literal value of `fieldName` from `jsonStr` without full deserialization.
  /// Returns null if native engine is unavailable or field is not found.
  static String? extractField(String jsonStr, String fieldName) {
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null || jsonStr.isEmpty || fieldName.isEmpty) return null;

    final jsonBytes = utf8.encode(jsonStr);
    final jsonPtr = malloc<ffi.Uint8>(jsonBytes.length + 1);
    for (var i = 0; i < jsonBytes.length; i++) {
      jsonPtr[i] = jsonBytes[i];
    }
    jsonPtr[jsonBytes.length] = 0;

    final fieldBytes = utf8.encode(fieldName);
    final fieldPtr = malloc<ffi.Uint8>(fieldBytes.length + 1);
    for (var i = 0; i < fieldBytes.length; i++) {
      fieldPtr[i] = fieldBytes[i];
    }
    fieldPtr[fieldBytes.length] = 0;

    final startPtr = malloc<ffi.Int32>(1);
    final endPtr = malloc<ffi.Int32>(1);

    try {
      final found = bindings.jsonExtractString(
        jsonPtr.cast<Utf8>(),
        jsonBytes.length,
        fieldPtr.cast<Utf8>(),
        startPtr,
        endPtr,
      );

      if (found == 1) {
        final s = startPtr.value;
        final e = endPtr.value;
        if (s >= 0 && e >= s && e <= jsonBytes.length) {
          final sub = jsonBytes.sublist(s, e);
          return utf8.decode(sub, allowMalformed: true);
        }
      }
      return null;
    } finally {
      malloc.free(jsonPtr);
      malloc.free(fieldPtr);
      malloc.free(startPtr);
      malloc.free(endPtr);
    }
  }

  /// Direct zero-copy field extraction from raw UTF-8 bytes without intermediate String decoding.
  static String? extractFieldFromBytes(List<int> rawBytes, String fieldName) {
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null || rawBytes.isEmpty || fieldName.isEmpty) return null;

    final bytesPtr = malloc<ffi.Uint8>(rawBytes.length);
    for (var i = 0; i < rawBytes.length; i++) {
      bytesPtr[i] = rawBytes[i];
    }

    final fieldBytes = utf8.encode(fieldName);
    final fieldPtr = malloc<ffi.Uint8>(fieldBytes.length + 1);
    for (var i = 0; i < fieldBytes.length; i++) {
      fieldPtr[i] = fieldBytes[i];
    }
    fieldPtr[fieldBytes.length] = 0;

    final startPtr = malloc<ffi.Int32>(1);
    final endPtr = malloc<ffi.Int32>(1);

    try {
      final found = bindings.jsonExtractFromBytes(
        bytesPtr,
        rawBytes.length,
        fieldPtr.cast<Utf8>(),
        startPtr,
        endPtr,
      );

      if (found == 1) {
        final s = startPtr.value;
        final e = endPtr.value;
        if (s >= 0 && e >= s && e <= rawBytes.length) {
          final sub = rawBytes.sublist(s, e);
          return utf8.decode(sub, allowMalformed: true);
        }
      }
      return null;
    } finally {
      malloc.free(bytesPtr);
      malloc.free(fieldPtr);
      malloc.free(startPtr);
      malloc.free(endPtr);
    }
  }
}
