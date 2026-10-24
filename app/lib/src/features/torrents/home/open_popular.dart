import 'package:flutter/material.dart';
import 'package:torrent/torrent.dart';

import '../../../core/redact.dart';
import '../../../core/services.dart';
import '../../../player/play_request.dart';
import '../torrent_logic.dart';
import 'popular_item.dart';

/// The magnet to add for [item]: its own, or one built from the infohash.
/// Null when it has only a .torrent link.
String? magnetFor(PopularItem item) {
  final m = item.magnet;
  if (m != null && btihFromMagnet(m) != null) return m;
  final h = item.infoHash;
  if (h == null) return null;
  return 'magnet:?xt=urn:btih:$h&dn=${Uri.encodeComponent(item.title)}';
}

/// The file to play without asking: the only streamable file, or one at
/// least three times the size of the next (a film beside a sample or extras).
/// Null when it is a pack: the file list is shown instead.
TorrentFile? autoPick(TorrentInfo info) {
  final streamable = orderFiles(info.files).where((f) => f.streamable).toList();
  if (streamable.isEmpty) return null;
  if (streamable.length == 1 || streamable[0].length >= streamable[1].length * 3) return streamable.first;
  return null;
}

/// Select on a tile: the existing add-torrent flow. The network guard asks
/// first; then the file is picked ([autoPick]) and plays, or the file list
/// opens (always with [chooseFile]: the Menu key, or a long press).
Future<void> openPopular(BuildContext context, PopularItem item, {bool chooseFile = false}) async {
  final services = AppServices.of(context);
  final service = services.torrents;
  void say(String m) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  if (!await service.ensureNetworkChoice(context) || !context.mounted) return;
  try {
    final magnet = magnetFor(item);
    final info = magnet != null
        ? await service.addMagnet(magnet)
        : await service.addTorrentBytes(await services.torrentHome.fetchTorrent(item));
    if (!context.mounted) {
      await service.removeActive(id: info.id);
      return;
    }
    final pick = chooseFile ? null : autoPick(info);
    if (pick == null) {
      await service.openFiles(context, info);
    } else {
      await openPlayer(context, service.playRequest(info, pick));
    }
  } on TorrentException catch (e) {
    say(redactText(e.message));
  } catch (e) {
    say(redactText('$e'));
  }
}
