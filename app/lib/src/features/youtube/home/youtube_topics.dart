import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../../theme.dart';
import '../../../ui/common/dims.dart';
import '../../../ui/common/tokens.dart';
import '../../../ui/tv/focus_card.dart';
import '../feed/youtube_feed.dart';
import 'youtube_home_keys.dart';

/// A chip on the YouTube home: For you, or one of the feed's rails.
class YouTubeTopic {
  const YouTubeTopic(this.id, this.label, this.icon, [this.railId]);

  final String id;
  final String label;
  final IconData icon;

  /// The [FeedRail] it shows; null for For you (the whole feed).
  final String? railId;

  bool get forYou => railId == null;
}

const forYouTopic = YouTubeTopic('for-you', 'For you', Icons.auto_awesome_rounded);
const continueTopic = YouTubeTopic('continue', 'Continue watching', Icons.history_rounded, 'continue');

/// The topic chips, in order. The feed fetches each of these rails already
/// (its popular topics), so a chip costs no extra request.
const youTubeTopics = [
  forYouTopic,
  continueTopic,
  YouTubeTopic('music', 'Music', Icons.music_note_rounded, 'popular-music'),
  YouTubeTopic('live', 'Live', Icons.sensors_rounded, 'popular-live'),
  YouTubeTopic('sports', 'Sports', Icons.sports_soccer_rounded, 'popular-sports'),
  YouTubeTopic('news', 'News', Icons.newspaper_rounded, 'popular-news'),
  YouTubeTopic('gaming', 'Gaming', Icons.sports_esports_rounded, 'popular-gaming'),
];

/// The chips to show for [state]: Continue watching only once something
/// has been watched.
List<YouTubeTopic> topicsFor(FeedState state) => [
  for (final t in youTubeTopics)
    if (t != continueTopic || state.rails.any((r) => r.id == continueTopic.railId)) t,
];

/// The rail [topic] shows, if the feed has it.
FeedRail? railFor(YouTubeTopic topic, FeedState state) {
  for (final r in state.rails) {
    if (r.id == topic.railId) return r;
  }
  return null;
}

/// The billboard's videos for [topic]: the feed's own hero for For you, else
/// the first five of the rail, finished videos before live ones (a live
/// stream's frame is often a static card).
List<VideoItem> heroFor(YouTubeTopic topic, FeedState state) {
  if (topic.forYou) return state.hero;
  final items = railFor(topic, state)?.items ?? const <VideoItem>[];
  final vod = items.where((v) => !v.isLive).take(5).toList();
  return vod.isNotEmpty ? vod : items.take(5).toList();
}

/// The kicker over the billboard for [topic].
String kickerFor(YouTubeTopic topic, FeedState state) {
  if (!topic.forYou) return topic.id == 'continue' ? 'Pick up where you left off' : 'Popular in ${topic.label}';
  return state.rails.any((r) => r.id == 'for-you') ? 'Recommended for you' : 'Popular on YouTube';
}

/// A topic chip for pointer and touch: accent-filled when selected, the
/// colour sliding in. [height] 48 on a phone (the touch guideline).
class TopicChip extends StatefulWidget {
  const TopicChip({super.key, required this.topic, required this.selected, required this.onTap, this.height = 40});

  final YouTubeTopic topic;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  State<TopicChip> createState() => _TopicChipState();
}

class _TopicChipState extends State<TopicChip> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final d = Dims.of(context);
    final motion = Motion.of(context);
    final selected = widget.selected;
    final fg = selected ? c.onAccent : c.text;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.topic.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: FocusableActionDetector(
        onFocusChange: (f) => setState(() => _focused = f),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: motion.expandTime,
              curve: Motion.curve,
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: Space.s16),
              decoration: BoxDecoration(
                color: selected
                    ? c.accent
                    : Color.alphaBlend(c.text.withValues(alpha: _hovered ? 0.12 : 0.06), c.surface),
                borderRadius: BorderRadius.circular(Radii.chip),
                border: Border.all(
                  color: _focused ? c.accent : (selected ? c.accent : c.text.withValues(alpha: 0.1)),
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.topic.icon, size: 18, color: fg),
                  const SizedBox(width: Space.s8),
                  AnimatedDefaultTextStyle(
                    duration: motion.expandTime,
                    // Merged onto the inherited style: on its own it would
                    // replace the theme's font family.
                    style: DefaultTextStyle.of(context).style.merge(
                      d.type.card.copyWith(color: fg, fontSize: d.phone ? 14 : 15),
                    ),
                    child: Text(widget.topic.label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chips in a row that scrolls sideways when it does not fit.
class TopicChipBar extends StatelessWidget {
  const TopicChipBar({
    super.key,
    required this.topics,
    required this.selected,
    required this.onSelect,
    this.padding = EdgeInsets.zero,
    this.height = 40,
  });

  final List<YouTubeTopic> topics;
  final YouTubeTopic selected;
  final ValueChanged<YouTubeTopic> onSelect;
  final EdgeInsets padding;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: padding,
      itemCount: topics.length,
      separatorBuilder: (_, _) => const SizedBox(width: Space.s8),
      itemBuilder: (_, i) => TopicChip(
        key: YouTubeHomeKeys.chip(topics[i].id),
        topic: topics[i],
        selected: topics[i].id == selected.id,
        height: height,
        onTap: () => onSelect(topics[i]),
      ),
    ),
  );
}

/// A TV topic chip: a [FocusCard] (the D-pad's ring and lift), selected by
/// OK. No blur and no colour animation beyond the card's own.
class TvTopicChip extends StatelessWidget {
  const TvTopicChip({super.key, required this.topic, required this.selected, required this.focus, required this.onSelect});

  final YouTubeTopic topic;
  final bool selected;
  final SectionFocus focus;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final d = Dims.of(context);
    final fg = selected ? c.onAccent : c.text;
    return Semantics(
      selected: selected,
      child: FocusCard(
        section: focus,
        radius: Radii.pill,
        onActivate: onSelect,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: Space.s16),
          color: selected ? c.accent : c.surfaceHigh,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(topic.icon, size: 18, color: fg),
              const SizedBox(width: Space.s8),
              Text(topic.label, style: TextStyle(color: fg, fontSize: d.t(15), fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
