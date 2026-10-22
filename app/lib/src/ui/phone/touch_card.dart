import 'package:flutter/material.dart';

/// A touch tile: ripple on press, at least 48 dp, and one Semantics label for
/// screen readers (and for UI tests that find it by its content description).
class TouchCard extends StatelessWidget {
  const TouchCard({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.radius = 14,
  });

  final String label;
  final VoidCallback? onTap;

  /// Long-press opens a context menu (from 0.4.0).
  final VoidCallback? onLongPress;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: shape,
            onTap: onTap,
            onLongPress: onLongPress,
            child: ClipRRect(borderRadius: shape, child: child),
          ),
        ),
      ),
    );
  }
}
