import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui/common/dims.dart';
import '../ui/common/keys.dart';
import '../ui/common/tokens.dart';
import '../ui/desktop/title_bar.dart' show WindowButtons;
import '../ui/desktop/window_chrome.dart';
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

/// The playback speeds the speed menu offers.
const playerSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// "1×", "1.25×".
String speedLabel(double speed) {
  final text = speed == speed.roundToDouble() ? speed.toStringAsFixed(0) : '$speed';
  return '$text×';
}

/// The on-screen display, in three parts over the video:
///
/// * top: Back, title and status, then speed, tracks and fullscreen (and on
///   a custom-frame desktop the window buttons, which the player covers);
/// * centre: previous, back 10 s, play/pause, forward 10 s, next;
/// * bottom: seek bar, times, volume (desktop) and the LIVE pill.
///
/// Always in the tree (the position text is what tests read); it fades and
/// the bars slide a little. No blur, no shadows: the TV this runs on has
/// 2 GB. While [controls] is false (error panel, resume prompt) only the top
/// bar shows, so Back is always there.
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
    required this.onBack,
    this.controls = true,
    this.backFocus,
    this.playFocus,
    this.onRewind,
    this.onForward,
    this.rewindFocus,
    this.forwardFocus,
    this.onPrevious,
    this.onNext,
    this.previousFocus,
    this.nextFocus,
    this.onTracks,
    this.tracksFocus,
    this.speed = 1,
    this.onSpeed,
    this.speedFocus,
    this.fullscreen = false,
    this.onFullscreen,
    this.fullscreenFocus,
    this.windowChrome,
    this.volume,
    this.muted = false,
    this.onVolume,
    this.onMute,
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
  final VoidCallback onBack;

  /// False: only the top bar (an error or the resume prompt is up).
  final bool controls;
  final FocusNode? backFocus;
  final FocusNode? playFocus;

  /// Back and forward 10 s; null hides them (nothing to seek in).
  final VoidCallback? onRewind;
  final VoidCallback? onForward;
  final FocusNode? rewindFocus;
  final FocusNode? forwardFocus;

  /// Set when the item has a queue; Previous also needs an earlier item.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final FocusNode? previousFocus;
  final FocusNode? nextFocus;

  /// Opens the audio and subtitle menu; null hides the button (nothing to
  /// choose).
  final VoidCallback? onTracks;
  final FocusNode? tracksFocus;

  /// Opens the speed menu; null hides the button (live, or the engine cannot).
  final double speed;
  final VoidCallback? onSpeed;
  final FocusNode? speedFocus;

  /// Desktop: the window is fullscreen / toggles it; null hides the button.
  final bool fullscreen;
  final VoidCallback? onFullscreen;
  final FocusNode? fullscreenFocus;

  /// A custom-frame window: the top bar drags it and shows its buttons.
  final WindowChrome? windowChrome;

  /// Desktop volume, 0 to 1; null hides the control.
  final double? volume;
  final bool muted;
  final ValueChanged<double>? onVolume;
  final VoidCallback? onMute;
  final SheetProvider sheetProvider;

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    final slide = motion.reduced ? Duration.zero : (visible ? osdFadeIn : osdFadeOut) * 1.5;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: visible ? osdFadeIn : osdFadeOut,
        curve: Curves.easeOut,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, -0.25),
                duration: slide,
                curve: Motion.curve,
                child: _topBar(context),
              ),
            ),
            if (controls) Center(child: _centre(context)),
            if (controls)
              Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSlide(
                  offset: visible ? Offset.zero : const Offset(0, 0.25),
                  duration: slide,
                  curve: Motion.curve,
                  child: _bottomBar(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Side padding: TV overscan, else the usual gutter.
  static double _side(Dims d) => d.tv ? Space.s64 : (d.phone ? Space.s16 : Space.s24);

  Widget _topBar(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final size = _OsdSizes.of(d);
    final chrome = windowChrome;
    final line = [
      if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
      if (status != null && status!.isNotEmpty) status!,
    ].join('  ·  ');
    final gap = SizedBox(width: d.tv ? Space.s16 : Space.s8);
    final row = Row(
      children: [
        OsdButton(
          key: PlayerKeys.osdBack,
          icon: Icons.arrow_back_rounded,
          label: 'Back',
          tooltip: 'Back (Esc)',
          size: size.top,
          focusNode: backFocus,
          onPressed: onBack,
        ),
        SizedBox(width: d.tv ? Space.s24 : Space.s12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                key: PlayerKeys.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: d.t(d.tv ? 26 : 18), fontWeight: FontWeight.w700, color: Colors.white),
              ),
              if (line.isNotEmpty)
                Text(
                  line,
                  key: PlayerKeys.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: d.t(13), color: c.textDim),
                ),
            ],
          ),
        ),
        if (controls && onSpeed != null) ...[
          gap,
          OsdButton(
            key: PlayerKeys.speed,
            icon: Icons.speed_rounded,
            text: speed == 1 ? null : speedLabel(speed),
            label: 'Playback speed, ${speedLabel(speed)}',
            tooltip: 'Speed',
            size: size.top,
            focusNode: speedFocus,
            onPressed: onSpeed!,
          ),
        ],
        if (controls && onTracks != null) ...[
          gap,
          OsdButton(
            key: PlayerKeys.tracks,
            icon: Icons.subtitles_rounded,
            label: 'Audio and subtitles',
            tooltip: 'Audio and subtitles',
            size: size.top,
            focusNode: tracksFocus,
            onPressed: onTracks!,
          ),
        ],
        if (onFullscreen != null) ...[
          gap,
          OsdButton(
            key: PlayerKeys.fullscreen,
            icon: fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            label: fullscreen ? 'Exit full screen' : 'Full screen',
            tooltip: fullscreen ? 'Exit full screen (F)' : 'Full screen (F)',
            size: size.top,
            focusNode: fullscreenFocus,
            onPressed: onFullscreen!,
          ),
        ],
      ],
    );
    // The window buttons sit in the corner like a title bar's; the row keeps
    // clear of them.
    final buttons = chrome != null && chrome.custom && !fullscreen;
    final side = _side(d);
    Widget bar = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            side,
            d.tv ? Space.s32 : Space.s12,
            buttons ? 3 * 46 + Space.s8 : side,
            d.tv ? Space.s48 : Space.s32,
          ),
          child: row,
        ),
      ),
    );
    if (chrome != null && chrome.custom) {
      bar = Stack(
        children: [
          // The empty part of the bar moves the window, as the title bar does;
          // a click there does not reach the video (no accidental pause).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              onPanStart: (_) => chrome.startDrag(),
            ),
          ),
          bar,
          if (buttons)
            Positioned(top: 0, right: 0, child: WindowButtons(chrome: chrome, foreground: Colors.white)),
        ],
      );
    }
    return bar;
  }

  Widget _centre(BuildContext context) {
    final d = Dims.of(context);
    final size = _OsdSizes.of(d);
    final queue = onPrevious != null || onNext != null;
    final gap = SizedBox(width: d.tv ? Space.s32 : (d.phone ? Space.s16 : Space.s24));
    // Empty slots keep play/pause in the exact middle, where the loading
    // ring is drawn.
    Widget slot(Widget? button) => button ?? SizedBox.square(dimension: size.centre);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (queue) ...[
          slot(onPrevious == null
              ? null
              : OsdButton(
                  key: PlayerKeys.previous,
                  icon: Icons.skip_previous_rounded,
                  label: 'Previous',
                  tooltip: 'Previous',
                  size: size.centre,
                  focusNode: previousFocus,
                  onPressed: onPrevious!,
                )),
          gap,
        ],
        if (onRewind != null) ...[
          OsdButton(
            key: PlayerKeys.rewind,
            icon: Icons.replay_10_rounded,
            label: 'Back 10 seconds',
            tooltip: d.desktop ? 'Back 10 s (J)' : null,
            size: size.centre,
            focusNode: rewindFocus,
            onPressed: onRewind!,
          ),
          gap,
        ],
        OsdButton(
          key: PlayerKeys.playPause,
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          label: playing ? 'Pause' : 'Play',
          tooltip: d.desktop ? (playing ? 'Pause (Space)' : 'Play (Space)') : null,
          size: size.play,
          filled: true,
          focusNode: playFocus,
          onPressed: onToggle,
        ),
        if (onForward != null) ...[
          gap,
          OsdButton(
            key: PlayerKeys.forward,
            icon: Icons.forward_10_rounded,
            label: 'Forward 10 seconds',
            tooltip: d.desktop ? 'Forward 10 s (L)' : null,
            size: size.centre,
            focusNode: forwardFocus,
            onPressed: onForward!,
          ),
        ],
        if (queue) ...[
          gap,
          slot(onNext == null
              ? null
              : OsdButton(
                  key: PlayerKeys.next,
                  icon: Icons.skip_next_rounded,
                  label: 'Next',
                  tooltip: 'Next',
                  size: size.centre,
                  focusNode: nextFocus,
                  onPressed: onNext!,
                )),
        ],
      ],
    );
  }

  Widget _bottomBar(BuildContext context) {
    final d = Dims.of(context);
    final dvr = live && duration >= dvrMinimum;
    final bar = !live || dvr;
    final atEdge = dvr && duration - position <= liveEdgeSlack;
    final preview = scrubber.preview;
    final shown = preview ?? position;
    final dim = TextStyle(color: Colors.white70, fontSize: d.t(14));
    final left = duration - shown;
    final side = _side(d);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, d.tv ? Space.s48 : Space.s32, side, d.tv ? Space.s32 : Space.s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  Text(formatPlayerTime(shown), key: Keys.playerPosition, style: dim),
                  if (!live && duration > Duration.zero)
                    Text(
                      ' / ${formatPlayerTime(duration)}',
                      key: PlayerKeys.duration,
                      style: dim.copyWith(color: Colors.white38),
                    ),
                  const Spacer(),
                  if (volume != null && onVolume != null && onMute != null) ...[
                    _Volume(volume: volume!, muted: muted, onChanged: onVolume!, onMute: onMute!),
                    const SizedBox(width: Space.s16),
                  ],
                  if (live)
                    _LivePill(atEdge: atEdge || !dvr, onTap: dvr ? onLive : null)
                  else if (duration > Duration.zero)
                    Text(
                      '-${formatPlayerTime(left < Duration.zero ? Duration.zero : left)}',
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

/// Button sizes per form: TV buttons are big enough to read from the sofa.
class _OsdSizes {
  const _OsdSizes(this.top, this.centre, this.play);

  final double top;
  final double centre;
  final double play;

  static _OsdSizes of(Dims d) => switch (d.form) {
        FormFactor.tv => const _OsdSizes(56, 72, 96),
        FormFactor.phone => const _OsdSizes(44, 52, 68),
        FormFactor.desktop => const _OsdSizes(40, 52, 72),
      };
}

/// The play button's diameter, for the loading ring drawn around it.
double playButtonSize(Dims d) => _OsdSizes.of(d).play;

/// A round OSD button. Focusable for the D-pad and Tab, but a click does not
/// take focus: the player's keys (Space, arrows) keep working after a click.
/// Focus shows as the app's ring (and on a TV the usual scale).
class OsdButton extends StatefulWidget {
  const OsdButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.size = 44,
    this.filled = false,
    this.tooltip,
    this.text,
  });

  final IconData icon;

  /// For screen readers.
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final double size;

  /// White disc, dark icon: the main action (play/pause).
  final bool filled;

  /// Desktop hover hint, with the key when there is one.
  final String? tooltip;

  /// Shown instead of the icon (the speed when it is not 1×).
  final String? text;

  @override
  State<OsdButton> createState() => _OsdButtonState();
}

class _OsdButtonState extends State<OsdButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final spec = FocusSpec.of(d.form);
    final motion = Motion.of(context);
    final fg = widget.filled ? Colors.black : Colors.white;
    final bg = widget.filled
        ? Colors.white.withValues(alpha: _hovered ? 1 : 0.92)
        : (_hovered || _focused ? const Color(0x40FFFFFF) : const Color(0x59000000));
    final text = widget.text;
    final button = Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (f) => setState(() => _focused = f),
        onShowHoverHighlight: (h) => setState(() => _hovered = h),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onPressed();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _focused ? spec.scale : 1,
            duration: motion.focusTime,
            curve: Motion.curve,
            child: AnimatedContainer(
              duration: motion.hoverPressTime,
              width: widget.size,
              height: widget.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
                border: _focused
                    ? Border.all(color: c.accent, width: spec.ring + spec.gap)
                    : Border.all(color: Colors.transparent, width: spec.ring + spec.gap),
              ),
              child: text != null
                  ? Text(
                      text,
                      maxLines: 1,
                      style: TextStyle(color: fg, fontSize: widget.size * 0.3, fontWeight: FontWeight.w700),
                    )
                  : Icon(widget.icon, color: fg, size: widget.size * 0.55),
            ),
          ),
        ),
      ),
    );
    final tip = widget.tooltip;
    return tip == null || !d.desktop
        ? button
        : Tooltip(message: tip, waitDuration: const Duration(milliseconds: 500), child: button);
  }
}

/// Desktop volume: the mute button and a short bar (click, drag or wheel).
/// Not focusable: the keyboard has Up, Down and M.
class _Volume extends StatelessWidget {
  const _Volume({required this.volume, required this.muted, required this.onChanged, required this.onMute});

  final double volume;
  final bool muted;
  final ValueChanged<double> onChanged;
  final VoidCallback onMute;

  static const _width = 96.0;

  void _at(double dx) => onChanged((dx / _width).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final shown = muted ? 0.0 : volume;
    final icon = shown == 0
        ? Icons.volume_off_rounded
        : (shown < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: muted ? 'Unmute (M)' : 'Mute (M)',
          waitDuration: const Duration(milliseconds: 500),
          child: Semantics(
            button: true,
            label: muted ? 'Unmute' : 'Mute',
            onTap: onMute,
            excludeSemantics: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: PlayerKeys.mute,
                behavior: HitTestBehavior.opaque,
                onTap: onMute,
                child: Padding(
                  padding: const EdgeInsets.all(Space.s4),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: Space.s4),
        Semantics(
          slider: true,
          label: 'Volume',
          value: '${(shown * 100).round()}%',
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                onChanged((volume + (e.scrollDelta.dy < 0 ? 0.05 : -0.05)).clamp(0.0, 1.0));
              }
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: PlayerKeys.volume,
                behavior: HitTestBehavior.opaque,
                onTapDown: (e) => _at(e.localPosition.dx),
                onHorizontalDragUpdate: (e) => _at(e.localPosition.dx),
                child: SizedBox(
                  width: _width,
                  height: 24,
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 4,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const ColoredBox(color: Colors.white24),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: shown,
                              child: const ColoredBox(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: d.t(10), color: color),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: TextStyle(color: color, fontSize: d.t(14), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return onTap == null
        ? pill
        : GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: pill);
  }
}
