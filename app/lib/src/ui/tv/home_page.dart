import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../features/youtube/feed/youtube_feed.dart';
import '../../features/youtube/youtube_results.dart';
import '../../theme.dart';
import '../common/dims.dart';
import '../common/tokens.dart';
import '../common/video_billboard.dart';
import 'focus_card.dart';
import 'focus_rail.dart';

/// Home: a billboard and rails of YouTube videos, popular now and, as Chithram
/// learns what the user watches, suggestions for them.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // After the first frame: nothing on the startup path reads the network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppServices.of(context).feed.open());
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = AppServices.of(context).feed;
    final d = Dims.of(context);
    final tileWidth = d.tv ? tvTileWidth(context) : d.u(300);
    return ValueListenableBuilder<FeedState>(
      valueListenable: feed.state,
      builder: (context, state, _) {
        final suggested = state.rails.any((r) => r.id == 'for-you');
        return SingleChildScrollView(
        key: const PageStorageKey<String>('home-scroll'),
        padding: const EdgeInsets.only(bottom: Space.s32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TvBillboard(
              focus: widget.focus,
              items: state.hero,
              kicker: suggested ? 'Recommended for you' : 'Popular on YouTube',
              error: state.error,
              playFocusNode: widget.focus.entry,
              onPlay: (v) => playVideo(context, v, source: suggested ? 'for-you' : null),
              onRetry: () => feed.refresh(force: true),
            ),
            SizedBox(height: d.tv ? Space.s24 : Space.s16),
            for (final rail in state.rails)
              FocusRail(
                key: ValueKey('home-${rail.id}'),
                title: rail.title,
                count: rail.items.length,
                section: widget.focus,
                // A TV tile is 208 dp on the 960 dp screen (about three and a
                // half across) with a 16:9 thumbnail, and grows with a wider
                // layout (a desktop in 10-foot mode).
                spacing: d.tv ? tvRailGap(tileWidth) : null,
                itemBuilder: (_, i) => SizedBox(
                  width: tileWidth,
                  child: VideoTileBody(
                    item: rail.items[i],
                    thumbnailHeight: d.tv ? tileWidth * 9 / 16 : null,
                  ),
                ),
                onSelect: (i) => playVideo(context, rail.items[i], source: rail.id),
              ),
          ],
        ),
        );
      },
    );
  }
}

/// A TV tile: 208 dp on the 960 dp (1080p) screen, scaling with the width up to
/// twice that.
const double _tvTileBase = 208;
const double _tvScreenBase = 960;

double tvTileWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * _tvTileBase / _tvScreenBase)
        .clamp(_tvTileBase, _tvTileBase * 2);

/// The pill inside a button-like [FocusCard].
class ActionLabel extends StatelessWidget {
  const ActionLabel({super.key, required this.text, this.icon, this.primary = false});

  final String text;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final color = primary ? c.onAccent : c.text;
    return Container(
      color: primary ? ChithramColors.of(context).accent : ChithramColors.of(context).surfaceHigh,
      padding: d.tv
          ? const EdgeInsets.symmetric(horizontal: Space.s16, vertical: Space.s12)
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: d.tv ? 22 : 24),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: d.tv
                    ? d.type.card.copyWith(color: color, fontWeight: primary ? FontWeight.w700 : FontWeight.w600)
                    : TextStyle(color: color, fontSize: d.t(16), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
