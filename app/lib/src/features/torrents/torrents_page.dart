import 'package:flutter/material.dart';

import '../../ui/focus_card.dart';
import '../../ui/placeholder_page.dart';
import '../../ui/sections.dart';

/// Torrents section. Placeholder body until the torrents work package.
class TorrentsPage extends StatelessWidget {
  const TorrentsPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) => PlaceholderPage(section: Section.torrents, focus: focus);
}
