import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'dims.dart';

/// A frosted panel: the page shows through, blurred, under a tinted fill with
/// a hairline edge. Sidebars, bars, chips and the hero's controls use it.
///
/// A TV gets the same fill without the blur: a backdrop filter costs too much
/// on 1-2 GB TV boxes, and from the sofa the difference does not show.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding,
    this.color,
    this.blur = 24,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  /// The fill; [ChithramTheme.glass] when null.
  final Color? color;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final shape = BorderRadius.circular(radius);
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.glass,
        borderRadius: shape,
        border: Border.all(color: c.glassEdge),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (Dims.of(context).tv || blur <= 0) return panel;
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: panel,
      ),
    );
  }
}

/// A small outlined pill with a label: genres, channels, "LIVE", the hero's
/// facts (the "Action", "Thriller" chips of the references).
class MetaPill extends StatelessWidget {
  const MetaPill({super.key, required this.text, this.icon, this.filled = false});

  final String text;
  final IconData? icon;

  /// Accent fill (the "Popular" badge) instead of an outline.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final d = Dims.of(context);
    final fg = filled ? c.onAccent : c.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? c.accent : c.background.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(99),
        border: filled ? null : Border.all(color: c.text.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: d.t(13) + 1, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: d.t(12), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin progress line under a tile (Continue watching).
class WatchProgress extends StatelessWidget {
  const WatchProgress({super.key, required this.fraction, this.height = 4});

  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: c.text.withValues(alpha: 0.18),
        valueColor: AlwaysStoppedAnimation(c.accent),
      ),
    );
  }
}
