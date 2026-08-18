import 'dart:io';

void main() async {
  var pkgDir = Directory.current.path;
  if (!File('$pkgDir/c/caduceus_native.c').existsSync()) {
    final scriptPath = Platform.script.toFilePath();
    pkgDir = File(scriptPath).parent.parent.path;
  }
  final binDir = Directory('$pkgDir/lib/src/bin');
  if (!binDir.existsSync()) {
    binDir.createSync(recursive: true);
  }

  String libName;
  if (Platform.isMacOS || Platform.isIOS) {
    libName = 'libcaduceus_native.dylib';
  } else if (Platform.isWindows) {
    libName = 'caduceus_native.dll';
  } else {
    libName = 'libcaduceus_native.so';
  }

  final sourceFile = '$pkgDir/c/caduceus_native.c';
  final targetFile = '${binDir.path}/$libName';

  print('Compiling $sourceFile -> $targetFile ...');
  final result = await Process.run('clang', [
    '-O3',
    '-fPIC',
    '-shared',
    '-Wall',
    '-Wextra',
    '-Werror',
    sourceFile,
    '-o',
    targetFile,
  ]);

  if (result.exitCode != 0) {
    print('Compilation failed:\n${result.stderr}');
    exit(result.exitCode);
  }

  print('Successfully compiled $targetFile');
}
