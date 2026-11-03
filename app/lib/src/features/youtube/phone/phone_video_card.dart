import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../../theme.dart';
import '../../../ui/common/form_factor.dart';
import '../../../ui/common/glass.dart' show WatchProgress;
import '../../../ui/common/tokens.dart';
import '../../../ui/phone/touch_card.dart';
import '../youtube_results.dart';

/// A video result for a phone: a rounded 16:9 thumbnail, the title and the
/// channel below it. The whole card is one tap target.
class PhoneVideoCard extends StatelessWidget {
  const PhoneVideoCard({super.key, required this.item, required this.onOpen, this.progress});

  final VideoItem item;
  final VoidCallback onOpen;

  /// How much has been watched (0 to 1); a thin bar over the thumbnail.
  final double? progress;

  /// Height of the text under the thumbnail, for the grid's fixed row height.
  static double textHeight(TextScaler scaler) =>
      scaler.scale(15) * 1.4 * 2 + scaler.scale(12) * 1.4 + 28;

  @override
  Widget build(BuildContext context) {
    final url = VideoTile.thumbnailUrl(item.thumbnails);
    final duration = item.duration;
    final badge = item.isLive ? 'LIVE' : (duration == null ? null : VideoTile.clock(duration));
    final by = item.author.isEmpty ? '' : ', ${item.author}';
    final percent = progress == null ? '' : ', ${(progress! * 100).round()}% watched';
    final c = ChithramColors.of(context);
    final type = TypeScale.of(FormFactor.phone);
    final shape = BorderRadius.circular(Radii.card(FormFactor.phone));
    final watched = progress;
    return TouchCard(
      key: ValueKey('yt-result-${item.videoId}'),
      label: 'Play ${item.title}$by${badge == null ? '' : ', $badge'}$percent',
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: shape,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: c.surfaceHigh,
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
                      right: Space.s8,
                      bottom: Space.s8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(Space.s4),
                        ),
                        child: Text(badge, style: type.meta.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  if (watched != null)
                    Positioned(left: 0, right: 0, bottom: 0, child: WatchProgress(fraction: watched)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s8, Space.s4, 0),
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: type.card.copyWith(height: 1.4),
            ),
          ),
          if (item.author.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s4, 2, Space.s4, 0),
              child: Text(
                item.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.meta.copyWith(fontWeight: FontWeight.w400, height: 1.4, color: c.textDim),
              ),
            ),
        ],
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

  static const _gap = Space.s12;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent - 2 * Space.s16;
        final columns = (width / 340).floor().clamp(1, 4);
        final cell = (width - (columns - 1) * _gap) / columns;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s16),
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
