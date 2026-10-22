import 'package:flutter/material.dart';

import '../../theme.dart';
import 'dims.dart';
import '../tv/focus_card.dart';
import '../tv/home_page.dart' show ActionLabel;
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
    final d = Dims.of(context);
    return Padding(
      padding: EdgeInsets.all(d.phone ? 16 : 32),
      child: SingleChildScrollView(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(section.icon, size: d.u(48), color: ChithramColors.accent),
          const SizedBox(height: 16),
          Text(section.label, style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_blurbs[section] ?? '', style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14))),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.all(8),
            child: FocusCard(
              focusNode: focus.entry,
              section: focus,
              radius: 24,
              onActivate: () {},
              child: const ActionLabel(text: 'Coming soon'),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
