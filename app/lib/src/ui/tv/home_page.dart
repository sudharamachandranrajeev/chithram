import 'dart:async';

import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../core/services.dart';
import '../../features/youtube/feed/youtube_feed.dart';
import '../../features/youtube/youtube_results.dart';
import '../../theme.dart';
import '../common/dims.dart';
import '../common/glass.dart';
import '../common/tokens.dart';
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
    return ValueListenableBuilder<FeedState>(
      valueListenable: feed.state,
      builder: (context, state, _) => SingleChildScrollView(
        key: const PageStorageKey<String>('home-scroll'),
        padding: const EdgeInsets.only(bottom: Space.s32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Hero(focus: widget.focus, state: state, onRetry: () => feed.refresh(force: true)),
            SizedBox(height: d.tv ? Space.s24 : Space.s16),
            for (final rail in state.rails)
              FocusRail(
                key: ValueKey('home-${rail.id}'),
                title: rail.title,
                count: rail.items.length,
                section: widget.focus,
                // A TV tile is 208 dp on the 960 dp screen (four across), and grows with
                // a wider layout (a desktop in 10-foot mode).
                itemBuilder: (_, i) => SizedBox(width: d.tv ? _tvTileWidth(context) : d.u(300), child: VideoTileBody(item: rail.items[i])),
                onSelect: (i) => playVideo(context, rail.items[i], source: rail.id),
              ),
          ],
        ),
      ),
    );
  }
}

double _tvTileWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * 208 / 960).clamp(208.0, 416.0);

/// The first suggestion (or popular video) over its frame, with Play. While
/// nothing is there yet it says so, and offers Retry after a failure.
class _Hero extends StatelessWidget {
  const _Hero({required this.focus, required this.state, required this.onRetry});

  final SectionFocus focus;
  final FeedState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final height = (MediaQuery.sizeOf(context).height * (d.tv ? 0.44 : 0.42)).clamp(d.tv ? 190.0 : 220.0, 460.0);
    final VideoItem? video = state.hero.firstOrNull;
    final suggested = state.rails.any((r) => r.id == 'for-you');
    final error = state.error;
    final String label, title, line;
    final facts = <String>[];
    if (video != null) {
      label = suggested ? 'Recommended for you' : 'Popular on YouTube';
      title = video.title;
      line = '';
      final duration = video.duration;
      facts.addAll([
        video.author,
        video.viewsText,
        if (duration != null) VideoTile.clock(duration),
      ].where((s) => s.isNotEmpty));
    } else if (error != null) {
      (label, title, line) = ('YouTube', error, 'Check the connection, then retry.');
    } else {
      (label, title, line) = ('YouTube', 'Loading what is popular…', '');
    }
    return Container(
      // Fill the width: without it the card shrinks to its widest child.
      width: double.infinity,
      constraints: BoxConstraints(minHeight: height),
      margin: EdgeInsets.fromLTRB(d.phone ? Space.s8 : Space.s16, d.tv ? Space.s12 : Space.s16, d.phone ? Space.s8 : Space.s16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.hero),
        border: Border.all(color: ChithramColors.of(context).glassEdge),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            ChithramColors.of(context).heroTint,
            ChithramColors.of(context).surface,
            ChithramColors.of(context).background,
          ],
        ),
      ),
      child: Stack(
        children: [
          if (video != null) ...[
            Positioned.fill(child: HeroImage(videoId: video.videoId)),
            // Keeps the text readable over any frame.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [
                      ChithramColors.of(context).background.withAlpha(0x33),
                      ChithramColors.of(context).background.withAlpha(0xEE),
                    ],
                  ),
                ),
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.all(d.phone ? 18 : (d.tv ? Space.s24 : 28)),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height - (d.phone ? 36 : (d.tv ? Space.s48 : 56))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (video != null)
                    MetaPill(
                      text: label,
                      icon: suggested ? Icons.auto_awesome_rounded : Icons.local_fire_department_rounded,
                      filled: true,
                    )
                  else
                    Text(label,
                        style: TextStyle(color: ChithramColors.of(context).accent, fontSize: d.t(14), fontWeight: FontWeight.w600)),
                  const SizedBox(height: Space.s8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: d.tv
                            ? d.type.hero.copyWith(height: 1.1)
                            : TextStyle(fontSize: d.t(34), fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.3)),
                  ),
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [for (final f in facts) MetaPill(text: f)],
                    ),
                  ],
                  if (line.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ChithramColors.of(context).textDim, fontSize: d.t(14))),
                  ],
                  SizedBox(height: d.tv ? Space.s16 : 18),
                  FocusCard(
                    key: const ValueKey('home-hero-action'),
                    focusNode: focus.entry,
                    section: focus,
                    radius: Radii.pill,
                    onActivate: video != null
                        ? () => playVideo(context, video, source: suggested ? 'for-you' : null)
                        : error != null
                            ? onRetry
                            : null,
                    child: video != null
                        ? ActionLabel(icon: Icons.play_arrow_rounded, text: 'Play', primary: true)
                        : ActionLabel(icon: Icons.refresh_rounded, text: error != null ? 'Retry' : 'Loading'),
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
