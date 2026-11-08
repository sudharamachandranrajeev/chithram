import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import 'downloads.dart';
import 'torrent_actions.dart';

/// Settings section for torrents: the network choice (SOCKS5 or direct;
/// changing it restarts the engine), the download folder, speed limits and
/// seeding.
class TorrentSettings extends StatelessWidget {
  const TorrentSettings({super.key, this.entry});

  final SectionFocus? entry;

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).torrents;
    final prefs = service.prefs;
    Widget card(String text, VoidCallback onActivate, {Key? key, FocusNode? node}) => Padding(
          padding: const EdgeInsets.all(8),
          child: FocusCard(
            key: key,
            focusNode: node,
            section: entry,
            radius: 24,
            onActivate: onActivate,
            child: ActionLabel(text: text),
          ),
        );
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Wrap(
        children: [
          card('Torrent network: ${service.guard.choice.label}', () => unawaited(service.changeNetworkChoice(context)),
              node: entry?.entry),
          FutureBuilder(
            future: service.downloadsBase(),
            builder: (context, s) => card(
              'Download folder: ${s.data?.path ?? '...'}',
              () => unawaited(editDownloadFolder(context)),
              key: const ValueKey('settings-download-folder'),
            ),
          ),
          card('Download limit: ${limitLabel(prefs.getInt(DownloadPrefs.downKib) ?? 0)}',
              () => unawaited(editLimit(context, DownloadPrefs.downKib, 'Download')),
              key: const ValueKey('settings-limit-down')),
          card('Upload limit: ${limitLabel(prefs.getInt(DownloadPrefs.upKib) ?? 0)}',
              () => unawaited(editLimit(context, DownloadPrefs.upKib, 'Upload')),
              key: const ValueKey('settings-limit-up')),
          card('Seed finished downloads: ${service.seeding ? 'On' : 'Off'}', () => unawaited(toggleSeeding(context)),
              key: const ValueKey('settings-seed')),
        ],
      ),
    );
  }
}
