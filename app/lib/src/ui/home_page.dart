import 'package:flutter/material.dart';

import '../theme.dart';
import 'focus_card.dart';

/// Home: a hero billboard and a few rails of placeholder tiles.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Hero(focus: focus),
          const SizedBox(height: 16),
          _Rail(title: 'Continue watching', focus: focus, count: 8, hue: 30),
          _Rail(title: 'Trending on YouTube', focus: focus, count: 10, hue: 210),
          _Rail(title: 'Live now', focus: focus, count: 9, hue: 140),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.42).clamp(220.0, 460.0);
    return Container(
      height: height,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(28),
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
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Featured', style: TextStyle(color: ChithramColors.accent, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Hero billboard', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'A placeholder: your own sources will fill this.',
            style: TextStyle(color: ChithramColors.textDim),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FocusCard(
                focusNode: focus.entry,
                section: focus,
                radius: 24,
                onActivate: () {},
                child: Container(
                  color: ChithramColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded, color: Colors.black),
                      SizedBox(width: 6),
                      Text('Play', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              FocusCard(
                section: focus,
                radius: 24,
                onActivate: () {},
                child: Container(
                  color: ChithramColors.surfaceHigh,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  child: const Text('More info', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.title, required this.focus, required this.count, required this.hue});

  final String title;
  final SectionFocus focus;
  final int count;
  final double hue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ),
        // Vertical padding leaves room for the focus scale and glow.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              for (var i = 0; i < count; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: FocusCard(
                    section: focus,
                    onActivate: () {},
                    child: _Tile(index: i + 1, hue: (hue + i * 12) % 360),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.index, required this.hue});

  final int index;
  final double hue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 124,
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.35, 0.22).toColor(),
            HSLColor.fromAHSL(1, hue, 0.30, 0.12).toColor(),
          ],
        ),
      ),
      child: Text('Title $index', style: const TextStyle(fontWeight: FontWeight.w500)),
    );
  }
}
