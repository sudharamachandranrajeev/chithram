import 'package:flutter/material.dart';

import '../../ui/focus_card.dart';
import '../../ui/placeholder_page.dart';
import '../../ui/sections.dart';

/// Live TV section. Placeholder body until the Live TV work package.
class LiveTvPage extends StatelessWidget {
  const LiveTvPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) => PlaceholderPage(section: Section.liveTv, focus: focus);
}
