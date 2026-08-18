import 'dart:ffi' as ffi;
import 'dart:io';

/// Resolves and opens the Caduceus native dynamic library.
class CaduceusNativeLoader {
  static ffi.DynamicLibrary? _cachedLibrary;
  static bool _attempted = false;

  /// Whether the native library is successfully loaded and available.
  static bool get isAvailable => library != null;

  /// Gets the loaded DynamicLibrary, or null if native compilation is unavailable.
  static ffi.DynamicLibrary? get library {
    if (_attempted) return _cachedLibrary;
    _attempted = true;
    _cachedLibrary = _load();
    return _cachedLibrary;
  }

  static ffi.DynamicLibrary? _load() {
    final libraryName = _getLibraryFileName();

    // 1. Search common workspace locations and climb up directory tree
    var currentDir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final candidates = [
        '${currentDir.path}/$libraryName',
        '${currentDir.path}/lib/src/bin/$libraryName',
        '${currentDir.path}/packages/caduceus_native/lib/src/bin/$libraryName',
      ];
      for (final path in candidates) {
        final f = File(path);
        if (f.existsSync()) {
          try {
            return ffi.DynamicLibrary.open(f.path);
          } catch (_) {}
        }
      }
      final parent = currentDir.parent;
      if (parent.path == currentDir.path) break;
      currentDir = parent;
    }

    // 2. Try default dynamic linker search path
    try {
      return ffi.DynamicLibrary.open(libraryName);
    } catch (_) {}

    // 3. Try process lookup (when statically linked into executable)
    try {
      return ffi.DynamicLibrary.process();
    } catch (_) {}

    return null;
  }

  static String _getLibraryFileName() {
    if (Platform.isMacOS || Platform.isIOS) {
      return 'libcaduceus_native.dylib';
    } else if (Platform.isWindows) {
      return 'caduceus_native.dll';
    } else {
      return 'libcaduceus_native.so';
    }
  }
}
