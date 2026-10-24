import 'package:flutter/material.dart';
import 'package:chithram_player/chithram_player.dart';

import '../theme.dart';
import '../ui/common/dims.dart';
import '../ui/common/keys.dart';
import '../ui/tv/focus_card.dart';
import 'play_request.dart';
import 'player_keys.dart';
import 'player_route.dart' show formatPlayerTime;
import 'seek/scrub.dart';
import 'seek/seek_bar.dart';
import 'seek/storyboard_thumb.dart';

/// A live stream with at least this much behind the edge is a DVR window and
/// gets a seek bar.
const dvrMinimum = Duration(seconds: 60);

/// Within this of the end of a DVR window counts as "at the live edge".
const liveEdgeSlack = Duration(seconds: 15);

/// How fast the display comes up on a key, touch or mouse move.
const osdFadeIn = Duration(milliseconds: 150);

/// How slowly it fades away when idle.
const osdFadeOut = Duration(milliseconds: 500);

/// Title, status line, controls, seek bar and times. Always in the tree (the
/// position text is what tests read); it only fades. No blur, no shadows: the
/// TV this runs on has 2 GB.
class PlayerOsd extends StatelessWidget {
  const PlayerOsd({
    super.key,
    required this.visible,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.live,
    required this.playing,
    required this.scrubber,
    required this.extras,
    required this.onSeek,
    required this.onLive,
    required this.onToggle,
    this.onPrevious,
    this.onNext,
    this.previousFocus,
    this.nextFocus,
    this.onTracks,
    this.tracksFocus,
    this.aspect = VideoAspect.fit,
    this.onAspect,
    this.aspectFocus,
    this.sheetProvider = networkSheet,
  });

  final bool visible;
  final String title;
  final String? subtitle;
  final String? status;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool live;
  final bool playing;
  final Scrubber scrubber;
  final PlayExtras extras;
  final void Function(Duration to) onSeek;
  final VoidCallback onLive;
  final VoidCallback onToggle;

  /// Set when the item has a queue; Previous also needs an earlier item.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final FocusNode? previousFocus;
  final FocusNode? nextFocus;

  /// Opens the audio and subtitle menu; null hides the button (nothing to
  /// choose).
  final VoidCallback? onTracks;
  final FocusNode? tracksFocus;

  /// The picture shape; the button next to the track button steps through
  /// them. Null hides the button.
  final VideoAspect aspect;
  final VoidCallback? onAspect;
  final FocusNode? aspectFocus;
  final SheetProvider sheetProvider;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final dvr = live && duration >= dvrMinimum;
    final bar = !live || dvr;
    final atEdge = dvr && duration - position <= liveEdgeSlack;
    final preview = scrubber.preview;
    final line = [
      if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
      if (status != null && status!.isNotEmpty) status!,
    ].join('  ·  ');
    final dim = TextStyle(color: Colors.white70, fontSize: d.t(14));
    final controls =
        d.phone ||
        d.form == FormFactor.desktop ||
        onPrevious != null ||
        onNext != null ||
        onAspect != null ||
        onTracks != null;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: visible ? osdFadeIn : osdFadeOut,
        curve: Curves.easeOut,
        child: Container(
          alignment: Alignment.bottomCenter,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.center,
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            d.tv ? 64 : 24,
            0,
            d.tv ? 64 : 24,
            d.tv ? 40 : 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                key: PlayerKeys.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: d.t(22),
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (line.isNotEmpty)
                Text(
                  line,
                  key: PlayerKeys.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: d.t(14),
                    color: ChithramColors.of(context).textDim,
                  ),
                ),
              if (controls)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onPrevious != null) ...[
                        _RoundButton(
                          key: PlayerKeys.previous,
                          icon: Icons.skip_previous_rounded,
                          focusNode: previousFocus,
                          onTap: onPrevious!,
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (!d.tv) ...[
                        _RoundButton(
                          key: PlayerKeys.playPause,
                          icon: playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          onTap: onToggle,
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (onNext != null) ...[
                        _RoundButton(
                          key: PlayerKeys.next,
                          icon: Icons.skip_next_rounded,
                          focusNode: nextFocus,
                          onTap: onNext!,
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (onTracks != null)
                        _RoundButton(
                          key: PlayerKeys.tracks,
                          icon: Icons.subtitles_rounded,
                          focusNode: tracksFocus,
                          onTap: onTracks!,
                        ),
                      if (onTracks != null && onAspect != null)
                        const SizedBox(width: 12),
                      if (onAspect != null)
                        _RoundButton(
                          key: PlayerKeys.aspect,
                          icon: Icons.aspect_ratio_rounded,
                          label: aspect.label,
                          focusNode: aspectFocus,
                          onTap: onAspect!,
                        ),
                    ],
                  ),
                ),
              SizedBox(height: bar ? 6 : 10),
              if (bar)
                SeekBar(
                  position: position,
                  duration: duration,
                  buffered: buffered,
                  scrubber: scrubber,
                  onSeek: onSeek,
                  chapters: live ? const [] : extras.chapters,
                  heatmap: live ? const [] : extras.heatmap,
                  segments: live ? const [] : extras.segments,
                  storyboard: live ? const [] : extras.storyboard,
                  tv: d.tv,
                  sheetProvider: sheetProvider,
                ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    playing ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: Colors.white70,
                    size: d.t(20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatPlayerTime(preview ?? position),
                    key: Keys.playerPosition,
                    style: dim,
                  ),
                  if (!live && duration > Duration.zero)
                    Text(
                      ' / ${formatPlayerTime(duration)}',
                      key: PlayerKeys.duration,
                      style: dim.copyWith(color: Colors.white38),
                    ),
                  const Spacer(),
                  if (live)
                    _LivePill(
                      atEdge: atEdge || !dvr,
                      onTap: dvr ? onLive : null,
                    )
                  else if (duration > Duration.zero)
                    Text(
                      '-${formatPlayerTime(duration - (preview ?? position) < Duration.zero ? Duration.zero : duration - (preview ?? position))}',
                      key: PlayerKeys.remaining,
                      style: dim.copyWith(color: Colors.white38),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.label,
    this.focusNode,
  });

  final String? label;
  final IconData icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return FocusCard(
      focusNode: focusNode,
      radius: 40,
      onActivate: onTap,
      child: Container(
        color: ChithramColors.of(context).surfaceHigh,
        padding: EdgeInsets.all(d.u(8)),
        child: label == null
            ? Icon(icon, color: Colors.white, size: d.t(26))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: d.t(26)),
                  SizedBox(width: d.u(8)),
                  Text(
                    label!,
                    style: TextStyle(color: Colors.white, fontSize: d.t(15)),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "LIVE": filled at the live edge, an outline when behind it (tap to jump).
class _LivePill extends StatelessWidget {
  const _LivePill({required this.atEdge, required this.onTap});

  final bool atEdge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final color = atEdge ? ChithramColors.of(context).accent : Colors.white70;
    final pill = Container(
      key: PlayerKeys.livePill,
      padding: EdgeInsets.symmetric(horizontal: d.u(12), vertical: d.u(4)),
      decoration: BoxDecoration(
        color: atEdge ? color.withValues(alpha: 0.2) : Colors.transparent,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: d.t(10), color: color),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(
              color: color,
              fontSize: d.t(14),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? pill
        : GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: pill,
          );
  }
}
