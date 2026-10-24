import 'package:flutter/material.dart';

import '../../theme.dart';

/// The phone's double-tap seek feedback: a half-screen ripple on the tapped
/// side with "+10 s" / "-10 s". Taps in a row add up (+20 s, +30 s ...).
class DoubleTapRipple extends StatefulWidget {
  const DoubleTapRipple({super.key, this.step = const Duration(seconds: 10)});

  final Duration step;

  @override
  State<DoubleTapRipple> createState() => DoubleTapRippleState();
}

class DoubleTapRippleState extends State<DoubleTapRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _forward = true;
  int _taps = 0;

  /// Another double tap on the right ([forward]) or left half.
  void bump(bool forward) {
    // A tap on the other side, or after the last one faded, starts again.
    if (forward != _forward || !_anim.isAnimating) _taps = 0;
    _forward = forward;
    _taps++;
    _anim.forward(from: 0);
    setState(() {});
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          if (!_anim.isAnimating && _anim.value == 0)
            return const SizedBox.shrink();
          final t = _anim.value;
          final fade = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3);
          return Align(
            alignment: _forward ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.4,
              heightFactor: 1,
              child: Opacity(
                opacity: fade.clamp(0.0, 1.0),
                child: CustomPaint(
                  painter: _RipplePainter(_forward, t, ChithramColors.of(context).accent),
                  child: Center(
                    child: Text(
                      '${_forward ? '+' : '-'}${widget.step.inSeconds * _taps} s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.forward, this.t, this.accent);
  final Color accent;

  final bool forward;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(forward ? size.width : 0, size.height / 2);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawCircle(
      origin,
      size.height * (0.4 + 0.8 * t),
      Paint()..color = accent.withValues(alpha: 0.22),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.t != t || old.forward != forward || old.accent != accent;
}
