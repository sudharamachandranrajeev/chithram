import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services.dart';
import '../../../theme.dart';
import '../../../ui/common/dims.dart';
import '../../../ui/common/tokens.dart';
import '../../../ui/tv/focus_card.dart';
import '../feed/youtube_feed.dart';
import 'youtube_home_desktop.dart';
import 'youtube_home_phone.dart';
import 'youtube_home_tv.dart';
import 'youtube_topics.dart';

/// The YouTube section's home: a search bar, topic chips, a billboard and
/// rails (For you) or a grid (a topic) of videos, all from the feed Home
/// already keeps (no extra requests). Searching opens results over it.
class YouTubeHome extends StatefulWidget {
  const YouTubeHome({super.key, required this.focus});

  final SectionFocus focus;

  @override
  State<YouTubeHome> createState() => _YouTubeHomeState();
}

class _YouTubeHomeState extends State<YouTubeHome> {
  YouTubeTopic _topic = forYouTopic;

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
        final topics = topicsFor(state);
        // A topic that went away (Continue watching emptied) falls back to For you.
        final topic = topics.firstWhere((t) => t.id == _topic.id, orElse: () => forYouTopic);
        final view = YouTubeHomeView(
          state: state,
          topics: topics,
          topic: topic,
          focus: widget.focus,
          onTopic: (t) => setState(() => _topic = t),
          onRetry: () => unawaited(feed.refresh(force: true)),
          refresh: () => feed.refresh(force: true),
        );
        return switch (Dims.of(context).form) {
          FormFactor.desktop => DesktopYouTubeHome(view: view),
          FormFactor.phone => PhoneYouTubeHome(view: view),
          FormFactor.tv => TvYouTubeHome(view: view),
        };
      },
    );
  }
}

/// What a YouTube home shows: the same for every form factor.
class YouTubeHomeView {
  const YouTubeHomeView({
    required this.state,
    required this.topics,
    required this.topic,
    required this.focus,
    required this.onTopic,
    required this.onRetry,
    required this.refresh,
  });

  final FeedState state;
  final List<YouTubeTopic> topics;
  final YouTubeTopic topic;
  final SectionFocus focus;
  final ValueChanged<YouTubeTopic> onTopic;
  final VoidCallback onRetry;

  /// Pull to refresh: done when the feed is.
  final Future<void> Function() refresh;

  FeedRail? get rail => railFor(topic, state);

  /// What the content area is in.
  HomeStatus get status {
    final has = topic.forYou ? state.hero.isNotEmpty || state.rails.isNotEmpty : (rail?.items.isNotEmpty ?? false);
    if (has) return HomeStatus.ready;
    if (state.loading) return HomeStatus.loading;
    if (state.error != null) return HomeStatus.failed;
    return HomeStatus.empty;
  }

  /// A key for the content: changes with the topic and the status, so the
  /// switcher fades through on either.
  Key get contentKey => ValueKey('yt-topic-${topic.id}-${status.name}');
}

enum HomeStatus { loading, ready, failed, empty }

/// The words of a failed or empty home.
(String, String) statusText(YouTubeHomeView view) => switch (view.status) {
  HomeStatus.failed => ('Could not load YouTube', view.state.error ?? 'Check the connection, then retry.'),
  _ => ('Nothing here yet', 'There are no ${view.topic.label.toLowerCase()} videos right now.'),
};

/// The icon over an error or empty message.
IconData statusIcon(YouTubeHomeView view) =>
    view.status == HomeStatus.failed ? Icons.cloud_off_rounded : Icons.video_library_outlined;

/// The YouTube mark and name at the head of the section.
class YouTubeMark extends StatelessWidget {
  const YouTubeMark({super.key});

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: d.phone ? 30 : 36,
          height: d.phone ? 22 : 26,
          decoration: BoxDecoration(
            // YouTube's red, so the section reads as YouTube at a glance.
            color: const Color(0xFFE5252A),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: d.phone ? 18 : 20),
        ),
        const SizedBox(width: Space.s8),
        Text('YouTube', style: d.type.h1.copyWith(fontSize: d.phone ? 20 : d.t(24), color: c.text, letterSpacing: -0.4)),
      ],
    );
  }
}
