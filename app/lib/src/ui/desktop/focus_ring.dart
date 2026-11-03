import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/dims.dart';

/// The desktop keyboard focus ring: [FocusSpec.ring] thick in the accent,
/// [FocusSpec.gap] outside the control. It shows only while the keyboard is
/// driving (traditional highlight mode); clicking never leaves a ring.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.focused, required this.child, this.radius = 12});

  final bool focused;
  final Widget child;
  final double radius;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (!show) return widget.child;
    final spec = Dims.of(context).focus;
    final edge = spec.gap + spec.ring;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned(
          left: -edge,
          top: -edge,
          right: -edge,
          bottom: -edge,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius + edge),
                border: Border.all(color: ChithramColors.of(context).accent, width: spec.ring),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
