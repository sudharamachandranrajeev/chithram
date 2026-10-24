import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui/common/dims.dart';
import '../ui/tv/focus_card.dart';
import '../ui/tv/home_page.dart' show ActionLabel;
import 'play_request.dart';
import 'player_keys.dart';

/// How long the card counts down before it plays the next video.
const upNextCountdown = Duration(seconds: 8);

/// The next video is picked this long before the end, so the card is instant.
const upNextLead = Duration(seconds: 30);

/// "Up next": thumbnail, title and channel of [next] with a ring that runs
/// out in [upNextCountdown]. Play now plays it at once, Cancel stays on the
/// ended video. The ring is the only thing that animates.
class UpNextCard extends StatefulWidget {
  const UpNextCard({
    super.key,
    required this.next,
    required this.onPlay,
    required this.onCancel,
    this.countdown = upNextCountdown,
  });

  final PlayRequest next;
  final VoidCallback onPlay;
  final VoidCallback onCancel;
  final Duration countdown;

  @override
  State<UpNextCard> createState() => _UpNextCardState();
}

class _UpNextCardState extends State<UpNextCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: widget.countdown)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onPlay();
        })
        ..forward();
  final _playFocus = FocusNode(debugLabel: 'up next play');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ring.dispose();
    _playFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final next = widget.next;
    final art = next.artwork;
    final thumbW = d.tv ? 300.0 : (d.phone ? 140.0 : 220.0);
    final ring = d.tv ? 64.0 : 44.0;
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, d.tv ? 64 : 24, d.tv ? 48 : 24),
        child: Container(
          key: PlayerKeys.upNext,
          constraints: BoxConstraints(maxWidth: d.phone ? 360 : 640),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xEE16161E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  RepaintBoundary(
                    child: SizedBox(
                      width: ring,
                      height: ring,
                      child: AnimatedBuilder(
                        animation: _ring,
                        builder: (context, _) {
                          final left = widget.countdown * (1 - _ring.value);
                          return CustomPaint(
                            painter: _RingPainter(_ring.value, ChithramColors.of(context).accent),
                            child: Center(
                              child: Text(
                                '${(left.inMilliseconds / 1000).ceil()}',
                                key: PlayerKeys.upNextCount,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: d.t(16),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Up next',
                    style: TextStyle(
                      color: ChithramColors.of(context).textDim,
                      fontSize: d.t(16),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: thumbW,
                      height: thumbW * 9 / 16,
                      child: art == null
                          ? const ColoredBox(color: Color(0xFF22222D))
                          : Image.network(
                              art,
                              fit: BoxFit.cover,
                              cacheWidth: (thumbW * 2).round(),
                              errorBuilder: (_, _, _) =>
                                  const ColoredBox(color: Color(0xFF22222D)),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          next.title,
                          key: PlayerKeys.upNextTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: d.t(16),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (next.subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              next.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ChithramColors.of(context).textDim,
                                fontSize: d.t(14),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FocusCard(
                    key: PlayerKeys.upNextPlay,
                    focusNode: _playFocus,
                    radius: 28,
                    onActivate: widget.onPlay,
                    child: const ActionLabel(
                      icon: Icons.play_arrow_rounded,
                      text: 'Play now',
                      primary: true,
                    ),
                  ),
                  FocusCard(
                    key: PlayerKeys.upNextCancel,
                    radius: 28,
                    onActivate: widget.onCancel,
                    child: const ActionLabel(text: 'Cancel'),
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

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.accent);
  final Color accent;

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final rect = r.deflate(3);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white24;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * (1 - progress),
      false,
      base
        ..color = accent
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.accent != accent;
}
