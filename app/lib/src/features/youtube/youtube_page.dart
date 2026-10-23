import 'package:flutter/material.dart';

import '../../ui/tv/focus_card.dart';
import '../../ui/common/search_page.dart';

/// YouTube section: the search keyboard and a grid of results.
class YouTubePage extends StatelessWidget {
  const YouTubePage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) =>
      SearchPage(focus: focus, youtubeOnly: true);
}
