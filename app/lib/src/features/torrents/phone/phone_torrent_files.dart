import 'package:flutter/material.dart';
import 'package:torrent/torrent.dart';

import '../../../theme.dart';
import '../torrent_files_page.dart' show TorrentKeys;
import '../torrent_logic.dart';
import '../torrent_service.dart';

/// The files of one torrent as list tiles: streamable first, largest first.
/// Tapping one plays it; others say they are not media.
class PhoneFileTiles extends StatelessWidget {
  const PhoneFileTiles({super.key, required this.info, required this.onPlay});

  final TorrentInfo info;
  final void Function(TorrentFile) onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final f in orderFiles(info.files))
          ListTile(
            key: TorrentKeys.file(f.index),
            minTileHeight: 56,
            leading: Icon(
              f.streamable ? Icons.play_arrow_rounded : Icons.insert_drive_file_outlined,
              color: f.streamable ? ChithramColors.of(context).accent : ChithramColors.of(context).textDim,
            ),
            title: Text(f.path, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(f.streamable ? formatBytes(f.length) : '${formatBytes(f.length)}, not a media file'),
            onTap: () => onPlay(f),
          ),
      ],
    );
  }
}

/// The file list screen on a phone (shown by the page that owns the torrent,
/// which removes it when the screen closes).
class PhoneTorrentFiles extends StatelessWidget {
  const PhoneTorrentFiles({super.key, required this.info, required this.service, required this.onPlay});

  final TorrentInfo info;
  final TorrentService service;
  final void Function(TorrentFile) onPlay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(info.name ?? 'Torrent', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ListenableBuilder(
              listenable: service,
              builder: (_, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  statusLine(service.stats),
                  key: TorrentKeys.stats,
                  style: TextStyle(color: ChithramColors.of(context).textDim),
                ),
              ),
            ),
            PhoneFileTiles(info: info, onPlay: onPlay),
          ],
        ),
      ),
    );
  }
}
