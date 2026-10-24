import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../../theme.dart';
import '../../../ui/phone/touch_card.dart';
import '../youtube_results.dart';

/// A video result for a phone: a 16:9 thumbnail across the card, the title
/// and the channel below it. The whole card is one tap target.
class PhoneVideoCard extends StatelessWidget {
  const PhoneVideoCard({super.key, required this.item, required this.onOpen});

  final VideoItem item;
  final VoidCallback onOpen;

  /// Height of the text under the thumbnail, for the grid's fixed row height.
  static double textHeight(TextScaler scaler) =>
      scaler.scale(15) * 1.4 * 2 + scaler.scale(12) * 1.4 + 28;

  @override
  Widget build(BuildContext context) {
    final url = VideoTile.thumbnailUrl(item.thumbnails);
    final duration = item.duration;
    final badge = item.isLive ? 'LIVE' : (duration == null ? null : VideoTile.clock(duration));
    final by = item.author.isEmpty ? '' : ', ${item.author}';
    return TouchCard(
      key: ValueKey('yt-result-${item.videoId}'),
      label: 'Play ${item.title}$by${badge == null ? '' : ', $badge'}',
      onTap: onOpen,
      child: ColoredBox(
        color: ChithramColors.of(context).surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: ChithramColors.of(context).surfaceHigh,
                    child: url == null
                        ? const Icon(Icons.smart_display_rounded, size: 40)
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            cacheWidth: 640,
                            errorBuilder: (_, _, _) => const Icon(Icons.smart_display_rounded, size: 40),
                          ),
                  ),
                  if (badge != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(badge, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
              ),
            ),
            if (item.author.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                child: Text(
                  item.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: 1.4, color: ChithramColors.of(context).textDim),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Video cards in one column on a phone, more on a wide screen. A sliver, so it
/// sits in the page's scroll view; asks for the next page near the end.
class PhoneVideoSliver extends StatelessWidget {
  const PhoneVideoSliver({super.key, required this.items, required this.onOpen, this.onNearEnd});

  final List<VideoItem> items;
  final void Function(VideoItem item) onOpen;
  final VoidCallback? onNearEnd;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent - 2 * 16;
        final columns = (width / 340).floor().clamp(1, 4);
        final cell = (width - (columns - 1) * _gap) / columns;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: _gap,
              crossAxisSpacing: _gap,
              mainAxisExtent: cell * 9 / 16 + PhoneVideoCard.textHeight(scaler),
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              if (i >= items.length - 3) onNearEnd?.call();
              final v = items[i];
              return PhoneVideoCard(item: v, onOpen: () => onOpen(v));
            }, childCount: items.length),
          ),
        );
      },
    );
  }
}
