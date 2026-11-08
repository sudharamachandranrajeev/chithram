import 'package:flutter/material.dart';

import '../../../core/services.dart';
import '../torrent_actions.dart';
import '../torrent_logic.dart';
import 'popular_item.dart';

export '../torrent_actions.dart' show autoPick;

/// The magnet to add for [item]: its own, or one built from the infohash.
/// Null when it has only a .torrent link.
String? magnetFor(PopularItem item) {
  final m = item.magnet;
  if (m != null && btihFromMagnet(m) != null) return m;
  final h = item.infoHash;
  if (h == null) return null;
  return 'magnet:?xt=urn:btih:$h&dn=${Uri.encodeComponent(item.title)}';
}

/// Select on a tile: stream it ([streamTorrent]); with [chooseFile] (the Menu
/// key, or a long press) the file list always opens.
Future<void> openPopular(BuildContext context, PopularItem item, {bool chooseFile = false}) {
  final feed = AppServices.of(context).torrentHome;
  return streamTorrent(
    context,
    magnet: magnetFor(item),
    fetch: () => feed.fetchTorrent(item),
    chooseFile: chooseFile,
  );
}
