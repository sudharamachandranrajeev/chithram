// Torrent flows shared by the Torrents pages, the Find page, the popular
// rails and Settings: stream, download, search, and the download settings.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:torrent/torrent.dart';

import '../../core/redact.dart';
import '../../core/services.dart';
import '../../find/find_api.dart';
import '../../player/play_request.dart';
import '../../ui/common/text_entry.dart';
import 'downloads.dart';
import 'downloads_view.dart';
import 'torrent_logic.dart';

void _say(BuildContext context, String m) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
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

/// Streams a torrent from [magnet] or the bytes [fetch] returns. The network
/// guard asks first; then the file is picked ([autoPick]) and plays, or the
/// file list opens (always with [chooseFile]).
Future<void> streamTorrent(
  BuildContext context, {
  String? magnet,
  Future<Uint8List> Function()? fetch,
  bool chooseFile = false,
}) async {
  final service = AppServices.of(context).torrents;
  if (!await service.ensureNetworkChoice(context) || !context.mounted) return;
  try {
    final info = magnet != null ? await service.addMagnet(magnet) : await service.addTorrentBytes(await fetch!());
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
    if (context.mounted) _say(context, redactText(e.message));
  } catch (e) {
    if (context.mounted) _say(context, redactText('$e'));
  }
}

/// Keeps a torrent as a download, then opens it.
Future<void> downloadTorrent(
  BuildContext context, {
  String? magnet,
  Future<Uint8List> Function()? fetch,
}) async {
  final service = AppServices.of(context).torrents;
  if (!await service.ensureNetworkChoice(context) || !context.mounted) return;
  try {
    final d = await service.download(magnet: magnet, bytes: magnet == null ? await fetch!() : null);
    if (!context.mounted) return;
    _say(context, 'Downloading to ${d.record.folder}');
    await openDownload(context, d);
  } on TorrentException catch (e) {
    if (context.mounted) _say(context, redactText(e.message));
  } catch (e) {
    if (context.mounted) _say(context, redactText('$e'));
  }
}

/// Asks what to look for, then lists what the search plugins find.
Future<void> searchTorrents(BuildContext context) async {
  final text = await askText(context, title: 'Search torrents', hint: 'Title, year, quality...', kind: TextEntryKind.search);
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  final t = text.trim();
  // A pasted magnet goes straight to the stream flow.
  if (btihFromMagnet(t) != null && t.startsWith('magnet:')) {
    await streamTorrent(context, magnet: t);
    return;
  }
  await openFindSources(context, TextQuery(t));
}

/// Settings: the folder new downloads go to.
Future<void> editDownloadFolder(BuildContext context) async {
  final service = AppServices.of(context).torrents;
  final current = (await service.downloadsBase()).path;
  if (!context.mounted) return;
  final text = await askText(
    context,
    title: 'Download folder (empty for the default)',
    hint: current,
    initial: service.prefs.getString(DownloadPrefs.folder) ?? '',
  );
  if (text == null || !context.mounted) return;
  try {
    await service.setDownloadsBase(text);
  } catch (e) {
    if (context.mounted) _say(context, 'Cannot use that folder: ${redactText('$e')}');
  }
}

/// Settings: a speed limit in KiB/s (or "2m" for MiB/s).
Future<void> editLimit(BuildContext context, String key, String what) async {
  final prefs = AppServices.of(context).torrents.prefs;
  final current = prefs.getInt(key) ?? 0;
  final text = await askText(
    context,
    title: '$what limit in KiB/s (0 for none)',
    hint: 'e.g. 500, or 2m for 2 MiB/s',
    initial: current > 0 ? '$current' : '',
    kind: TextEntryKind.search,
  );
  if (text == null || !context.mounted) return;
  final kib = parseLimit(text);
  if (kib == null) {
    _say(context, 'Type a number of KiB/s');
    return;
  }
  await prefs.set(key, kib);
}

/// Settings: keep sharing finished downloads.
Future<void> toggleSeeding(BuildContext context) async {
  final service = AppServices.of(context).torrents;
  await service.prefs.set(DownloadPrefs.seed, !service.seeding);
}
