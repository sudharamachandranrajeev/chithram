import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;

/// Settings section for the torrent network choice (SOCKS5 or direct).
/// Changing it restarts the torrent engine.
class TorrentSettings extends StatelessWidget {
  const TorrentSettings({super.key, this.entry});

  final SectionFocus? entry;

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).torrents;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: FocusCard(
          focusNode: entry?.entry,
          section: entry,
          radius: 24,
          onActivate: () => unawaited(service.changeNetworkChoice(context)),
          child: ActionLabel(text: 'Torrent network: ${service.guard.choice.label}'),
        ),
      ),
    );
  }
}
