import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:torrent/torrent.dart';

import '../../core/paths.dart';
import '../../core/prefs.dart';
import '../../player/play_request.dart';

/// The single active torrent and the network-choice guard. Stub: every method
/// is filled in by the torrents work package.
class TorrentService {
  TorrentService({required this.paths, required this.prefs});

  final AppPaths paths;
  final Prefs prefs;

  /// Asks for SOCKS5 or direct on the first torrent action; true when the user chose.
  Future<bool> ensureNetworkChoice(BuildContext c) => throw UnimplementedError('torrent network choice');

  Future<TorrentInfo> addMagnet(String magnet) => throw UnimplementedError('torrent addMagnet');

  Future<TorrentInfo> addTorrentBytes(Uint8List b) => throw UnimplementedError('torrent addTorrentBytes');

  PlayRequest playRequest(TorrentInfo t, TorrentFile f) => throw UnimplementedError('torrent playRequest');

  Future<void> openFiles(BuildContext c, TorrentInfo t) => throw UnimplementedError('torrent openFiles');
}
