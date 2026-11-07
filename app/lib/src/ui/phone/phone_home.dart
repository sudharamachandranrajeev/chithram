import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../features/youtube/feed/youtube_feed.dart';
import '../../features/youtube/phone/phone_video_card.dart';
import '../../features/youtube/youtube_results.dart';
import '../common/form_factor.dart';
import '../common/tokens.dart';
import '../common/video_billboard.dart';

/// Space between a rail's title and its cards.
const _railTitleGap = 10.0;

/// Height of the hero's text at scale 1 (kicker, two title lines, meta line)
/// and of everything else in it (gaps, Play, insets); the card is never
/// shorter than these at the user's text scale.
const _heroTextHeight = 113.0;
const _heroChrome = 104.0;

/// The billboard's height in a list [viewport] tall: 220 dp on a small phone,
/// taller on a big one, so the first rail peeks in under it; taller still for
/// large text.
double phoneHeroHeight(BuildContext context, double viewport) =>
    math.max((viewport * 0.36).clamp(220.0, 320.0), MediaQuery.textScalerOf(context).scale(_heroTextHeight) + _heroChrome) +
    Space.s16;

/// Phone Home: a swipeable billboard card and swipeable rails of YouTube
/// videos, popular now and, as Chithram learns, suggestions. Pull to refresh.
class PhoneHome extends StatefulWidget {
  const PhoneHome({super.key});

  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> {
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
    return ValueListenableBuilder<FeedState>(
      valueListenable: feed.state,
      builder: (context, state, _) {
        final suggested = state.rails.any((r) => r.id == 'for-you');
        return LayoutBuilder(
        builder: (context, box) => RefreshIndicator(
          onRefresh: () => feed.refresh(force: true),
          child: ListView(
            key: const PageStorageKey<String>('phone-home-scroll'),
            padding: const EdgeInsets.only(bottom: Space.s24),
            children: [
              // 220 dp on a small phone, taller on a big one, so the first rail
              // peeks in under it; taller still for large text.
              PhoneBillboard(
                key: const ValueKey('phone-hero'),
                height: phoneHeroHeight(context, box.maxHeight),
                items: state.hero,
                kicker: suggested ? 'Recommended for you' : 'Popular on YouTube',
                error: state.error,
                onPlay: (v) => playVideo(context, v, source: suggested ? 'for-you' : null),
                onRetry: () => feed.refresh(force: true),
              ),
              for (final rail in state.rails) PhoneRail(key: ValueKey('home-${rail.id}'), rail: rail),
            ],
          ),
        ),
        );
      },
    );
  }
}

/// A titled rail of [PhoneVideoCard]s that swipes sideways.
class PhoneRail extends StatelessWidget {
  const PhoneRail({super.key, required this.rail});

  final FeedRail rail;

  static const _cardWidth = 240.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s16, Space.s24, Space.s16, _railTitleGap),
          child: Semantics(
            header: true,
            child: Text(
              rail.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.of(FormFactor.phone).row,
            ),
          ),
        ),
        SizedBox(
          height: _cardWidth * 9 / 16 + PhoneVideoCard.textHeight(scaler),
          child: ListView.separated(
            key: PageStorageKey<String>('phone-rail-${rail.id}'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.s16),
            itemCount: rail.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.s12),
            itemBuilder: (context, i) => SizedBox(
              width: _cardWidth,
              child: PhoneVideoCard(
                item: rail.items[i],
                progress: rail.progress[rail.items[i].videoId],
                onOpen: () => playVideo(context, rail.items[i], source: rail.id),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
