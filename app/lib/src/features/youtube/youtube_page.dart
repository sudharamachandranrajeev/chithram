import 'package:flutter/material.dart';

import '../../ui/focus_card.dart';
import '../../ui/placeholder_page.dart';
import '../../ui/sections.dart';

/// YouTube section. Placeholder body until the YouTube work package.
class YouTubePage extends StatelessWidget {
  const YouTubePage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) => PlaceholderPage(section: Section.youtube, focus: focus);
}
