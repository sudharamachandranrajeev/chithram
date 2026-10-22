import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/details_page.dart';
import '../common/dims.dart';
import 'focus_card.dart';
import 'focus_rail.dart';

/// Home: a hero billboard and a few rails of placeholder tiles.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const PageStorageKey<String>('home-scroll'),
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Hero(focus: focus),
          const SizedBox(height: 16),
          _rail(context, 'Continue watching', 8, 30),
          _rail(context, 'Trending on YouTube', 10, 210),
          _rail(context, 'Live now', 9, 140),
        ],
      ),
    );
  }

  Widget _rail(BuildContext context, String title, int count, double hue) {
    return FocusRail(
      title: title,
      count: count,
      section: focus,
      itemBuilder: (_, i) => PosterTile(label: 'Title ${i + 1}', hue: hue + i * 12),
      onSelect: (i) => openDetails(context, title: 'Title ${i + 1}', hue: hue + i * 12),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final height = (MediaQuery.sizeOf(context).height * 0.42).clamp(220.0, 460.0);
    return Container(
      // Fill the width: without it the card shrinks to its widest child.
      width: double.infinity,
      constraints: BoxConstraints(minHeight: height),
      margin: EdgeInsets.fromLTRB(d.phone ? 8 : 16, 16, d.phone ? 8 : 16, 0),
      padding: EdgeInsets.all(d.phone ? 18 : 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            ChithramColors.accent.withValues(alpha: 0.35),
            ChithramColors.surface,
            ChithramColors.background,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Featured',
              style: TextStyle(color: ChithramColors.accent, fontSize: d.t(14), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Hero billboard', style: TextStyle(fontSize: d.t(34), fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'A placeholder: your own sources will fill this.',
            style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              FocusCard(
                focusNode: focus.entry,
                section: focus,
                radius: 28,
                onActivate: () => openDetails(context, title: 'Hero billboard', hue: 40),
                child: ActionLabel(icon: Icons.play_arrow_rounded, text: 'Play', primary: true),
              ),
              FocusCard(
                section: focus,
                radius: 28,
                onActivate: () => openDetails(context, title: 'Hero billboard', hue: 40),
                child: ActionLabel(text: 'More info'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The pill inside a button-like [FocusCard].
class ActionLabel extends StatelessWidget {
  const ActionLabel({super.key, required this.text, this.icon, this.primary = false});

  final String text;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final color = primary ? Colors.black : Colors.white;
    return Container(
      color: primary ? ChithramColors.accent : ChithramColors.surfaceHigh,
      padding: EdgeInsets.symmetric(horizontal: d.u(24), vertical: d.u(11)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: d.t(24)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: d.t(16), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
