import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'models.dart';

typedef _StartC = Pointer<Utf8> Function(Pointer<Utf8>, Uint64, Pointer<Utf8>);
typedef _StartD = Pointer<Utf8> Function(Pointer<Utf8>, int, Pointer<Utf8>);
typedef _AddC = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Uint8>, UintPtr, Pointer<Utf8>);
typedef _AddD = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Utf8>);
typedef _StatsC = Pointer<Utf8> Function(Uint64);
typedef _StatsD = Pointer<Utf8> Function(int);
typedef _RemoveC = Pointer<Utf8> Function(Uint64, Int32);
typedef _RemoveD = Pointer<Utf8> Function(int, int);
typedef _NoArgC = Pointer<Utf8> Function();
typedef _FreeC = Void Function(Pointer<Utf8>);
typedef _FreeD = void Function(Pointer<Utf8>);

/// Loads the native library for this platform. Set CHITHRAM_TORRENT_LIB to override (tests, dev).
DynamicLibrary openTorrentLibrary() {
  final override = Platform.environment['CHITHRAM_TORRENT_LIB'];
  if (override != null && override.isNotEmpty) return DynamicLibrary.open(override);
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libchithram_torrent.so');
  }
  if (Platform.isWindows) return DynamicLibrary.open('chithram_torrent.dll');
  throw UnsupportedError('torrent: unsupported platform ${Platform.operatingSystem}');
}

/// Thin typed wrapper over the C ABI. Every call blocks: run it off the UI isolate.
class TorrentBindings {
  TorrentBindings(DynamicLibrary lib)
      : _start = lib.lookupFunction<_StartC, _StartD>('ct_start'),
        _add = lib.lookupFunction<_AddC, _AddD>('ct_add'),
        _stats = lib.lookupFunction<_StatsC, _StatsD>('ct_stats'),
        _remove = lib.lookupFunction<_RemoveC, _RemoveD>('ct_remove'),
        _stop = lib.lookupFunction<_NoArgC, Pointer<Utf8> Function()>('ct_stop'),
        _free = lib.lookupFunction<_FreeC, _FreeD>('ct_free');

  factory TorrentBindings.open() => TorrentBindings(openTorrentLibrary());

  final _StartD _start;
  final _AddD _add;
  final _StatsD _stats;
  final _RemoveD _remove;
  final Pointer<Utf8> Function() _stop;
  final _FreeD _free;

  Map<String, dynamic> _take(Pointer<Utf8> p) {
    try {
      final j = jsonDecode(p.toDartString()) as Map<String, dynamic>;
      if (j['ok'] != true) throw TorrentException(j['error']?.toString() ?? 'unknown error');
      return j;
    } finally {
      _free(p);
    }
  }

  Map<String, dynamic> start(String dir, int quotaBytes, String? socks5) {
    final d = dir.toNativeUtf8();
    final s = socks5 == null ? nullptr.cast<Utf8>() : socks5.toNativeUtf8();
    try {
      return _take(_start(d, quotaBytes, s));
    } finally {
      malloc.free(d);
      if (socks5 != null) malloc.free(s);
    }
  }

  Map<String, dynamic> add({String? magnet, Uint8List? torrentBytes, List<String> peers = const []}) {
    final m = magnet == null ? nullptr.cast<Utf8>() : magnet.toNativeUtf8();
    final p = peers.isEmpty ? nullptr.cast<Utf8>() : jsonEncode(peers).toNativeUtf8();
    Pointer<Uint8> data = nullptr;
    var len = 0;
    if (torrentBytes != null && torrentBytes.isNotEmpty) {
      len = torrentBytes.length;
      data = malloc<Uint8>(len);
      data.asTypedList(len).setAll(0, torrentBytes);
    }
    try {
      return _take(_add(m, data, len, p));
    } finally {
      if (magnet != null) malloc.free(m);
      if (peers.isNotEmpty) malloc.free(p);
      if (data != nullptr) malloc.free(data);
    }
  }

  Map<String, dynamic> stats(int id) => _take(_stats(id));
  void remove(int id, bool deleteFiles) => _take(_remove(id, deleteFiles ? 1 : 0));
  void stop() => _take(_stop());
}
