import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart' hide Page;

import '../../../theme.dart';
import '../../../ui/common/dims.dart';
import '../../../ui/common/pill_button.dart';
import '../../../ui/common/tokens.dart';
import '../../../ui/common/video_billboard.dart' show ChannelMark;
import '../../../ui/common/video_card.dart';
import '../../../ui/tv/focus_card.dart';
import '../../../ui/tv/home_page.dart' show ActionLabel;
import '../youtube_results.dart';
import 'youtube_home_keys.dart';

/// A video's details: its big frame, title, channel and views, with Play.
/// A bottom sheet on a phone (where the thumb is), a dialog elsewhere; on a
/// TV the buttons are D-pad cards and Play has focus.
Future<void> showVideoDetails(BuildContext context, VideoItem v, {String? source}) {
  final d = Dims.of(context);
  void play(BuildContext sheet) {
    Navigator.of(sheet).pop();
    playVideo(context, v, source: source);
  }

  if (d.phone) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: ChithramColors.of(context).surface,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.s16, 0, Space.s16, Space.s16),
          child: _DetailsBody(video: v, onPlay: () => play(sheet), onClose: () => Navigator.of(sheet).pop()),
        ),
      ),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close details',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: Motion.of(context).reduced ? Duration.zero : const Duration(milliseconds: 260),
    pageBuilder: (dialog, _, _) => Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: d.tv ? 640 : 720),
        child: Material(
          color: ChithramColors.of(context).surface,
          borderRadius: BorderRadius.circular(Radii.panel),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: _DetailsBody(
              video: v,
              inset: true,
              onPlay: () => play(dialog),
              onClose: () => Navigator.of(dialog).pop(),
            ),
          ),
        ),
      ),
    ),
    // Grows from 94% while fading in: the card seems to come forward.
    transitionBuilder: (context, a, _, child) {
      final t = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: t,
        child: d.tv ? child : ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(t), child: child),
      );
    },
  );
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.video, required this.onPlay, required this.onClose, this.inset = false});

  final VideoItem video;
  final VoidCallback onPlay;
  final VoidCallback onClose;

  /// The frame runs edge to edge and the text is padded (a dialog).
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final type = d.type;
    final pad = inset ? const EdgeInsets.all(Space.s24) : const EdgeInsets.only(top: Space.s16);
    final Widget actions;
    if (d.tv) {
      actions = _TvActions(onPlay: onPlay, onClose: onClose);
    } else if (d.phone) {
      actions = Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: YouTubeHomeKeys.detailsPlay,
              onPressed: onPlay,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: const StadiumBorder()),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play'),
            ),
          ),
        ],
      );
    } else {
      actions = Row(
        children: [
          DesktopPill(
            key: YouTubeHomeKeys.detailsPlay,
            primary: true,
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            onPressed: onPlay,
          ),
          const SizedBox(width: Space.s12),
          DesktopPill(label: 'Close', onPressed: onClose),
        ],
      );
    }
    final frame = AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: c.surfaceHigh, child: HeroImage(videoId: video.videoId)),
          Positioned(right: Space.s12, bottom: Space.s12, child: VideoBadge(item: video)),
        ],
      ),
    );
    return Column(
      key: YouTubeHomeKeys.details,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (inset) frame else ClipRRect(borderRadius: BorderRadius.circular(Radii.card(d.form)), child: frame),
        Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(video.title, style: type.h1.copyWith(height: 1.2)),
              const SizedBox(height: Space.s12),
              Row(
                children: [
                  if (video.author.isNotEmpty) ...[
                    ChannelMark(name: video.author, size: 28),
                    const SizedBox(width: Space.s8),
                  ],
                  Expanded(
                    child: Text(
                      videoMeta(video),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: type.body.copyWith(color: c.textDim),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s24),
              actions,
            ],
          ),
        ),
      ],
    );
  }
}

/// Play and Close as D-pad cards; Play takes focus when the dialog opens.
class _TvActions extends StatefulWidget {
  const _TvActions({required this.onPlay, required this.onClose});

  final VoidCallback onPlay;
  final VoidCallback onClose;

  @override
  State<_TvActions> createState() => _TvActionsState();
}

class _TvActionsState extends State<_TvActions> {
  final _play = FocusNode(debugLabel: 'details play');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _play.requestFocus();
    });
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.s16,
    children: [
      FocusCard(
        key: YouTubeHomeKeys.detailsPlay,
        focusNode: _play,
        radius: Radii.pill,
        onActivate: widget.onPlay,
        child: const ActionLabel(icon: Icons.play_arrow_rounded, text: 'Play', primary: true),
      ),
      FocusCard(
        radius: Radii.pill,
        onActivate: widget.onClose,
        child: const ActionLabel(icon: Icons.close_rounded, text: 'Close'),
      ),
    ],
  );
}
