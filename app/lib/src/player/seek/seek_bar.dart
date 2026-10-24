import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:innertube/innertube.dart'
    show Chapter, HeatBin, SponsorSegment, StoryboardLevel, pickStoryboardLevel;

import '../../theme.dart';
import '../player_keys.dart';
import 'scrub.dart';
import 'storyboard_thumb.dart';

String _clock(Duration d) {
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  if (d.inHours == 0) return '${d.inMinutes}:$s';
  return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s';
}

/// The player's seek bar: played, buffered, chapters, SponsorBlock segments,
/// a "most replayed" graph above it, and a bubble with time, chapter and
/// preview frame over the thumb while scrubbing or hovering.
///
/// It only draws and reports. [scrubber] owns the preview position: a drag
/// feeds it, and the D-pad does through the player route. A tap or click
/// seeks at once through [onSeek]. No blur anywhere: this runs on a 2 GB TV.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.scrubber,
    required this.onSeek,
    this.buffered = Duration.zero,
    this.chapters = const [],
    this.heatmap = const [],
    this.segments = const [],
    this.storyboard = const [],
    this.tv = false,
    this.sheetProvider = networkSheet,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Scrubber scrubber;
  final void Function(Duration to) onSeek;
  final List<Chapter> chapters;
  final List<HeatBin> heatmap;
  final List<SponsorSegment> segments;
  final List<StoryboardLevel> storyboard;
  final bool tv;
  final SheetProvider sheetProvider;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _hover; // 0..1 while a mouse is over the bar
  bool _touching = false;

  double get _thumbWidth => widget.tv ? 240 : 160;
  double get _heatHeight => widget.heatmap.isEmpty ? 0 : (widget.tv ? 28 : 20);
  double get _barHeight => widget.tv ? 36 : 32;

  Duration _at(double fraction) => Duration(
    milliseconds: (widget.duration.inMilliseconds * fraction.clamp(0.0, 1.0))
        .round(),
  );

  @override
  void initState() {
    super.initState();
    widget.scrubber.addListener(_changed);
  }

  @override
  void didUpdateWidget(SeekBar old) {
    super.didUpdateWidget(old);
    if (old.scrubber != widget.scrubber) {
      old.scrubber.removeListener(_changed);
      widget.scrubber.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.scrubber.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final length = widget.duration;
    final known = length > Duration.zero;
    final preview = widget.scrubber.preview;
    final hovering = _hover != null && known;
    final shown = preview ?? (hovering ? _at(_hover!) : null);
    final active = preview != null || hovering || _touching;
    final level = pickStoryboardLevel(
      widget.storyboard,
      targetWidth: _thumbWidth.round(),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        double fractionAt(Offset p) => (p.dx / width).clamp(0.0, 1.0);
        return MouseRegion(
          onHover: (e) => setState(() => _hover = fractionAt(e.localPosition)),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: known
                ? (d) => widget.onSeek(_at(fractionAt(d.localPosition)))
                : null,
            onHorizontalDragStart: known
                ? (d) {
                    setState(() => _touching = true);
                    widget.scrubber.drag(
                      _at(fractionAt(d.localPosition)),
                      length,
                    );
                  }
                : null,
            onHorizontalDragUpdate: known
                ? (d) => widget.scrubber.drag(
                    _at(fractionAt(d.localPosition)),
                    length,
                  )
                : null,
            onHorizontalDragEnd: known
                ? (_) {
                    setState(() => _touching = false);
                    widget.scrubber.dragEnd();
                  }
                : null,
            onHorizontalDragCancel: () {
              if (!_touching) return;
              setState(() => _touching = false);
              widget.scrubber.cancel();
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_heatHeight > 0)
                      RepaintBoundary(
                        child: CustomPaint(
                          key: PlayerKeys.heatmap,
                          size: Size(width, _heatHeight),
                          painter: _HeatPainter(widget.heatmap, length),
                        ),
                      ),
                    RepaintBoundary(
                      child: CustomPaint(
                        key: PlayerKeys.seekBar,
                        size: Size(width, _barHeight),
                        painter: _BarPainter(
                          position: widget.position,
                          buffered: widget.buffered,
                          preview: preview,
                          hover: hovering ? shown : null,
                          duration: length,
                          chapters: widget.chapters,
                          segments: widget.segments,
                          active: active,
                          trackHeight: widget.tv ? 6 : 4,
                          thumbRadius: widget.tv ? 11 : 8,
                          accent: ChithramColors.of(context).accent,
                        ),
                      ),
                    ),
                  ],
                ),
                if (shown != null && known)
                  _bubble(
                    shown,
                    level,
                    width,
                    bottom: _barHeight + _heatHeight + 6,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bubble(
    Duration t,
    StoryboardLevel? level,
    double barWidth, {
    required double bottom,
  }) {
    final chapter = chapterAt(widget.chapters, t);
    final textW = widget.tv ? 300.0 : 180.0;
    final w = level != null
        ? math.max(_thumbWidth, 120.0)
        : math.min(textW, 220.0);
    final fraction = t.inMilliseconds / widget.duration.inMilliseconds;
    final left = (fraction * barWidth - w / 2)
        .clamp(0.0, math.max(0.0, barWidth - w))
        .toDouble();
    final style = TextStyle(
      color: Colors.white,
      fontSize: widget.tv ? 24 : 13,
      fontWeight: FontWeight.w600,
    );
    return Positioned(
      left: left,
      bottom: bottom,
      width: w,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (level != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: StoryboardThumb(
                    key: PlayerKeys.previewThumb,
                    level: level,
                    time: t,
                    width: _thumbWidth,
                    provider: widget.sheetProvider,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xCC000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_clock(t), key: PlayerKeys.bubbleTime, style: style),
                  if (chapter != null)
                    Text(
                      chapter.title,
                      key: PlayerKeys.bubbleChapter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: style.copyWith(
                        fontSize: style.fontSize! * 0.85,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chapter boundaries as x ranges across [width], with a gap between.
List<(double, double)> chapterSpans(
  List<Chapter> chapters,
  Duration duration,
  double width, {
  double gap = 2,
}) {
  if (duration <= Duration.zero) return [(0, width)];
  final cuts = <double>[
    for (final c in chapters)
      if (c.start > Duration.zero && c.start < duration)
        c.start.inMilliseconds / duration.inMilliseconds * width,
  ];
  final edges = [0.0, ...cuts, width];
  return [
    for (var i = 0; i < edges.length - 1; i++)
      (
        edges[i] + (i > 0 ? gap / 2 : 0),
        edges[i + 1] - (i < edges.length - 2 ? gap / 2 : 0),
      ),
  ];
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.position,
    required this.buffered,
    required this.preview,
    required this.hover,
    required this.duration,
    required this.chapters,
    required this.segments,
    required this.active,
    required this.trackHeight,
    required this.thumbRadius,
    required this.accent,
  });

  final Duration position;
  final Duration buffered;
  final Duration? preview;
  final Duration? hover;
  final Duration duration;
  final List<Chapter> chapters;
  final List<SponsorSegment> segments;
  final bool active;
  final double trackHeight;
  final double thumbRadius;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = duration.inMilliseconds;
    double x(Duration d) =>
        ms <= 0 ? 0 : (d.inMilliseconds / ms).clamp(0.0, 1.0) * size.width;
    final h = active ? trackHeight * 1.6 : trackHeight;
    final top = (size.height - h) / 2;
    final playX = x(position);
    final bufX = x(buffered);
    final previewX = preview == null ? null : x(preview!);
    final paint = Paint();
    for (final (l, r) in chapterSpans(chapters, duration, size.width)) {
      if (r <= l) continue;
      final rect = RRect.fromLTRBR(l, top, r, top + h, Radius.circular(h / 2));
      canvas.save();
      canvas.clipRRect(rect);
      paint.color = const Color(0x40FFFFFF);
      canvas.drawRect(rect.outerRect, paint);
      if (bufX > l) {
        paint.color = const Color(0x73FFFFFF);
        canvas.drawRect(
          Rect.fromLTRB(l, top, math.min(r, bufX), top + h),
          paint,
        );
      }
      for (final s in segments) {
        final sl = x(s.start), sr = x(s.end);
        if (sr <= l || sl >= r) continue;
        paint.color = sponsorColor(s.category).withValues(alpha: 0.9);
        canvas.drawRect(
          Rect.fromLTRB(math.max(l, sl), top, math.min(r, sr), top + h),
          paint,
        );
      }
      if (playX > l) {
        paint.color = accent;
        canvas.drawRect(
          Rect.fromLTRB(l, top, math.min(r, playX), top + h),
          paint,
        );
      }
      if (previewX != null && previewX != playX) {
        final a = math.min(playX, previewX), b = math.max(playX, previewX);
        if (b > l && a < r) {
          paint.color = previewX > playX
              ? const Color(0x99F5A300)
              : const Color(0xCCFFFFFF);
          canvas.drawRect(
            Rect.fromLTRB(math.max(l, a), top, math.min(r, b), top + h),
            paint,
          );
        }
      }
      canvas.restore();
    }
    if (active) {
      final thumbX = previewX ?? (hover != null ? x(hover!) : playX);
      paint.color = hover != null && preview == null
          ? Colors.white
          : accent;
      canvas.drawCircle(Offset(thumbX, size.height / 2), thumbRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.accent != accent ||
      o.position != position ||
      o.buffered != buffered ||
      o.preview != preview ||
      o.hover != hover ||
      o.duration != duration ||
      o.active != active ||
      !identical(o.chapters, chapters) ||
      !identical(o.segments, segments);
}

/// The "most replayed" graph: a soft filled curve, brighter where more
/// people replayed.
class _HeatPainter extends CustomPainter {
  _HeatPainter(this.bins, this.duration);

  final List<HeatBin> bins;
  final Duration duration;

  @override
  void paint(Canvas canvas, Size size) {
    final ms = duration.inMilliseconds;
    if (bins.isEmpty || ms <= 0) return;
    final path = Path()..moveTo(0, size.height);
    for (final b in bins) {
      final mid = (b.start + b.length * 0.5).inMilliseconds / ms * size.width;
      path.lineTo(
        mid.clamp(0.0, size.width),
        size.height - size.height * (0.12 + 0.88 * b.intensity),
      );
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0x59FFFFFF));
  }

  @override
  bool shouldRepaint(_HeatPainter o) =>
      !identical(o.bins, bins) || o.duration != duration;
}
