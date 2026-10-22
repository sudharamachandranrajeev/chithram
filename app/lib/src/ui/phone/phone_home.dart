import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/details_page.dart';
import 'touch_card.dart';

/// Phone Home: a full-bleed swipeable hero and swipeable rails of placeholder
/// tiles (the real content comes with the Media Home work).
class PhoneHome extends StatelessWidget {
  const PhoneHome({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => ListView(
        key: const PageStorageKey<String>('phone-home-scroll'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // About 56% of the room under the top bar, so the first rail peeks in.
          _PhoneHero(height: math.max(box.maxHeight * 0.56, 280)),
          _rail(context, 'Continue watching', 8, 30),
          _rail(context, 'Trending on YouTube', 10, 210),
          _rail(context, 'Live now', 9, 140),
        ],
      ),
    );
  }

  Widget _rail(BuildContext context, String title, int count, double hue) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          height: 216,
          child: ListView.separated(
            key: PageStorageKey<String>('phone-rail-$title'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _Poster(
              label: 'Title ${i + 1}',
              hue: hue + i * 12,
              onTap: () => openDetails(context, title: 'Title ${i + 1}', hue: hue + i * 12),
            ),
          ),
        ),
      ],
    );
  }
}

/// A 112x168 dp poster with its title below.
class _Poster extends StatelessWidget {
  const _Poster({required this.label, required this.hue, required this.onTap});

  final String label;
  final double hue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: TouchCard(
        label: label,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 168,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    HSLColor.fromAHSL(1, hue % 360, 0.35, 0.26).toColor(),
                    HSLColor.fromAHSL(1, hue % 360, 0.30, 0.12).toColor(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

/// Five swipeable pages, edge to edge.
class _PhoneHero extends StatefulWidget {
  const _PhoneHero({required this.height});

  final double height;

  @override
  State<_PhoneHero> createState() => _PhoneHeroState();
}

class _PhoneHeroState extends State<_PhoneHero> {
  static const _pages = 5;
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          PageView.builder(
            key: const ValueKey('phone-hero'),
            controller: _controller,
            itemCount: _pages,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _HeroPage(index: i),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page ? ChithramColors.accent : ChithramColors.textDim,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPage extends StatelessWidget {
  const _HeroPage({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = index == 0 ? 'Hero billboard' : 'Hero billboard ${index + 1}';
    void open() => openDetails(context, title: title, hue: 40 + index * 50);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            HSLColor.fromAHSL(1, (40 + index * 50) % 360, 0.55, 0.30).toColor(),
            ChithramColors.surface,
            ChithramColors.background,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Featured',
                style: text.labelLarge?.copyWith(color: ChithramColors.accent, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(title, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'A placeholder: your own sources will fill this.',
              style: text.bodyMedium?.copyWith(color: ChithramColors.textDim),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: open,
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: open,
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('More info'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
