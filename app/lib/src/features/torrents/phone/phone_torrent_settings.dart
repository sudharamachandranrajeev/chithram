import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services.dart';
import '../downloads.dart';
import '../torrent_actions.dart';

/// Torrent settings as list tiles: the network choice (changing it restarts
/// the engine), the download folder, speed limits and seeding.
class PhoneTorrentSettings extends StatelessWidget {
  const PhoneTorrentSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).torrents;
    final prefs = service.prefs;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Torrent network'),
            subtitle: Text(service.guard.choice.label),
            onTap: () => unawaited(service.changeNetworkChoice(context)),
          ),
          FutureBuilder(
            future: service.downloadsBase(),
            builder: (context, s) => ListTile(
              key: const ValueKey('settings-download-folder'),
              minTileHeight: 56,
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Download folder'),
              subtitle: Text(s.data?.path ?? '...'),
              onTap: () => unawaited(editDownloadFolder(context)),
            ),
          ),
          ListTile(
            key: const ValueKey('settings-limit-down'),
            minTileHeight: 56,
            leading: const Icon(Icons.download_rounded),
            title: const Text('Download limit'),
            subtitle: Text(limitLabel(prefs.getInt(DownloadPrefs.downKib) ?? 0)),
            onTap: () => unawaited(editLimit(context, DownloadPrefs.downKib, 'Download')),
          ),
          ListTile(
            key: const ValueKey('settings-limit-up'),
            minTileHeight: 56,
            leading: const Icon(Icons.upload_rounded),
            title: const Text('Upload limit'),
            subtitle: Text(limitLabel(prefs.getInt(DownloadPrefs.upKib) ?? 0)),
            onTap: () => unawaited(editLimit(context, DownloadPrefs.upKib, 'Upload')),
          ),
          SwitchListTile(
            key: const ValueKey('settings-seed'),
            secondary: const Icon(Icons.swap_vert_rounded),
            title: const Text('Seed finished downloads'),
            subtitle: const Text('Keep sharing them while Chithram is open'),
            value: service.seeding,
            onChanged: (_) => unawaited(toggleSeeding(context)),
          ),
        ],
      ),
    );
  }
}
