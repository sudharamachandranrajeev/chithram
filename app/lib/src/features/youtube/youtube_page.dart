import 'package:flutter/material.dart';

import '../../ui/tv/focus_card.dart';
import 'home/youtube_home.dart';

/// YouTube section: search, topic chips, a billboard and rails of videos;
/// searching opens results over it.
class YouTubePage extends StatelessWidget {
  const YouTubePage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) => YouTubeHome(focus: focus);
}
