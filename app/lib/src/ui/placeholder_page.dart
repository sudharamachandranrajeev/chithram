import 'package:flutter/material.dart';

import '../theme.dart';
import 'focus_card.dart';
import 'sections.dart';

const _blurbs = {
  Section.search: 'Unified search across your sources. Coming in a later phase.',
  Section.liveTv: 'M3U / Xtream playlists and the programme guide you add yourself.',
  Section.torrents: 'Stream torrents from magnets and the indexers you add. Needs a VPN/SOCKS5 by default.',
  Section.youtube: 'YouTube without an account: local subscriptions, feed and history.',
};

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.section, required this.focus});

  final Section section;
  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(section.icon, size: 48, color: ChithramColors.accent),
          const SizedBox(height: 16),
          Text(section.label, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_blurbs[section] ?? '', style: const TextStyle(color: ChithramColors.textDim)),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.all(8),
            child: FocusCard(
              focusNode: focus.entry,
              section: focus,
              radius: 24,
              onActivate: () {},
              child: Container(
                color: ChithramColors.surfaceHigh,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                child: const Text('Coming soon', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
