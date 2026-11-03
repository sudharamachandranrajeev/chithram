import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _MallocC = Pointer<Uint8> Function(IntPtr);
typedef _MallocD = Pointer<Uint8> Function(int);
typedef _FreeC = Void Function(Pointer<Uint8>);
typedef _FreeD = void Function(Pointer<Uint8>);
typedef _ChmodC = Int32 Function(Pointer<Uint8>, Uint32);
typedef _ChmodD = int Function(Pointer<Uint8>, int);

/// chmod(path, 0600) through libc. The runtime image has no shell or chmod binary and Dart
/// cannot set a umask, so owner-only files need this single libc call. Returns false on failure.
bool chmod600(String path) {
  if (Platform.isWindows) return true;
  try {
    final lib = DynamicLibrary.process();
    final malloc = lib.lookupFunction<_MallocC, _MallocD>('malloc');
    final free = lib.lookupFunction<_FreeC, _FreeD>('free');
    final chmod = lib.lookupFunction<_ChmodC, _ChmodD>('chmod');
    final bytes = [...utf8.encode(path), 0];
    if (bytes.indexOf(0) != bytes.length - 1) return false; // embedded NUL
    final p = malloc(bytes.length);
    try {
      for (var i = 0; i < bytes.length; i++) {
        p[i] = bytes[i];
      }
      return chmod(p, 384) == 0; // 0600
    } finally {
      free(p);
    }
  } catch (_) {
    return false;
  }
}
