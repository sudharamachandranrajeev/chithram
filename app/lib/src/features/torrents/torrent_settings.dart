import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../ui/focus_card.dart';
import '../../ui/home_page.dart' show ActionLabel;

/// Settings section for the torrent network choice (SOCKS5 or direct).
/// Shows the stored choice; changing it comes with the torrents work package.
class TorrentSettings extends StatelessWidget {
  const TorrentSettings({super.key, this.entry});

  final SectionFocus? entry;

  @override
  Widget build(BuildContext context) {
    final choice = AppServices.of(context).prefs.getString('torrent.network');
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FocusCard(
        focusNode: entry?.entry,
        section: entry,
        radius: 24,
        onActivate: () {},
        child: ActionLabel(text: 'Torrent network: ${choice ?? 'not set'}'),
      ),
    );
  }
}
