import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/tv/focus_card.dart';

/// A lazily built grid of video tiles (a sliver, so it lives inside the
/// page's scroll view). Asks for the next page near the end.
class VideoResultsSliver extends StatelessWidget {
  const VideoResultsSliver({
    super.key,
    required this.items,
    required this.section,
    required this.onOpen,
    this.onNearEnd,
  });

  final List<VideoItem> items;
  final SectionFocus section;
  final void Function(VideoItem item) onOpen;
  final VoidCallback? onNearEnd;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: d.u(320),
        mainAxisExtent: VideoTile.extent(d),
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
      ),
      delegate: SliverChildBuilderDelegate((context, i) {
        if (i >= items.length - 3) onNearEnd?.call();
        final v = items[i];
        return VideoTile(
          key: ValueKey('yt-result-${v.videoId}'),
          item: v,
          section: section,
          onActivate: () => onOpen(v),
        );
      }, childCount: items.length),
    );
  }
}

class VideoTile extends StatelessWidget {
  const VideoTile({
    super.key,
    required this.item,
    required this.section,
    required this.onActivate,
  });

  final VideoItem item;
  final SectionFocus section;
  final VoidCallback onActivate;

  /// A tile is a fixed height whatever its width, so the grid can build lazily.
  static double thumbnailHeight(Dims d) => d.u(170);

  static double extent(Dims d) =>
      thumbnailHeight(d) + d.t(14) * 3.4 + d.t(12) * 1.7 + 22;

  /// The smallest thumbnail at least 320 px wide, else the largest.
  static String? thumbnailUrl(List<ThumbnailInfo> list) {
    if (list.isEmpty) return null;
    final sorted = [...list]
      ..sort((a, b) => (a.width ?? 0).compareTo(b.width ?? 0));
    return sorted
        .firstWhere((t) => (t.width ?? 0) >= 320, orElse: () => sorted.last)
        .url;
  }

  static String clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final url = thumbnailUrl(item.thumbnails);
    final duration = item.duration;
    final badge = item.isLive
        ? 'LIVE'
        : (duration == null ? null : clock(duration));
    return FocusCard(
      section: section,
      onActivate: onActivate,
      child: Container(
        color: ChithramColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: thumbnailHeight(d),
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: ChithramColors.surfaceHigh,
                    child: url == null
                        ? const Icon(Icons.smart_display_rounded, size: 40)
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            cacheWidth: 320,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.smart_display_rounded,
                              size: 40,
                            ),
                          ),
                  ),
                  if (badge != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: d.t(12),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: d.t(14),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (item.author.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
                child: Text(
                  item.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: d.t(12),
                    color: ChithramColors.textDim,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
