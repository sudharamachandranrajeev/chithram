import 'package:flutter/material.dart';

import '../common/form_factor.dart';
import '../common/tokens.dart';

/// A touch tile: ripple on press, at least 48 dp, and one Semantics label for
/// screen readers (and for UI tests that find it by its content description).
class TouchCard extends StatelessWidget {
  const TouchCard({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.radius,
  });

  final String label;
  final VoidCallback? onTap;

  /// Long-press opens a context menu (from 0.4.0).
  final VoidCallback? onLongPress;
  final Widget child;

  /// Corner radius; the phone card radius when null.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius ?? Radii.card(FormFactor.phone));
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
