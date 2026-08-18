import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'native_bindings.dart';

class NativeKeyPair {
  const NativeKeyPair({
    required this.publicKey,
    required this.secretKey,
  });

  final Uint8List publicKey;
  final Uint8List secretKey;
}

class CryptoNative {
  /// Computes SHA-256 hash using native C implementation.
  /// Returns null if native engine is unavailable.
  static Uint8List? sha256(Uint8List data) {
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final inPtr = malloc<ffi.Uint8>(data.length);
    inPtr.asTypedList(data.length).setAll(0, data);
    final outPtr = malloc<ffi.Uint8>(32);

    try {
      bindings.sha256(inPtr, data.length, outPtr);
      final result = Uint8List(32);
      result.setAll(0, outPtr.asTypedList(32));
      return result;
    } finally {
      malloc.free(inPtr);
      malloc.free(outPtr);
    }
  }

  /// Generates an Ed25519 keypair from a 32-byte seed.
  static NativeKeyPair? ed25519KeypairFromSeed(Uint8List seed) {
    if (seed.length != 32) {
      throw ArgumentError('Seed must be exactly 32 bytes');
    }

    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final seedPtr = malloc<ffi.Uint8>(32);
    seedPtr.asTypedList(32).setAll(0, seed);
    final pubPtr = malloc<ffi.Uint8>(32);
    final secPtr = malloc<ffi.Uint8>(64);

    try {
      bindings.ed25519Keypair(seedPtr, pubPtr, secPtr);
      final pubKey = Uint8List(32);
      pubKey.setAll(0, pubPtr.asTypedList(32));
      final secKey = Uint8List(64);
      secKey.setAll(0, secPtr.asTypedList(64));
      return NativeKeyPair(publicKey: pubKey, secretKey: secKey);
    } finally {
      malloc.free(seedPtr);
      malloc.free(pubPtr);
      malloc.free(secPtr);
    }
  }

  /// Signs a message using Ed25519 secret key.
  static Uint8List? ed25519Sign(Uint8List message, Uint8List secretKey) {
    final bindings = CaduceusNativeBindings.instance;
    if (bindings == null) return null;

    final msgPtr = malloc<ffi.Uint8>(message.length);
    msgPtr.asTypedList(message.length).setAll(0, message);
    final secPtr = malloc<ffi.Uint8>(secretKey.length);
    secPtr.asTypedList(secretKey.length).setAll(0, secretKey);
    final sigPtr = malloc<ffi.Uint8>(64);

    try {
      bindings.ed25519Sign(msgPtr, message.length, secPtr, sigPtr);
      final signature = Uint8List(64);
      signature.setAll(0, sigPtr.asTypedList(64));
      return signature;
    } finally {
      malloc.free(msgPtr);
      malloc.free(secPtr);
      malloc.free(sigPtr);
    }
  }
}
