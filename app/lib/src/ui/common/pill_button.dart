import 'package:flutter/material.dart';

import '../../theme.dart';
import '../desktop/focus_ring.dart';
import 'dims.dart';
import 'tokens.dart';

/// A pill button: accent ([primary]) or outlined; [icon] leads, [trailingIcon]
/// follows the label. [onPressed] null disables it. Pointer and keyboard
/// (desktop, phone); a TV uses a [FocusCard] with an `ActionLabel` instead.
class DesktopPill extends StatefulWidget {
  const DesktopPill({
    super.key,
    required this.label,
    this.icon,
    this.trailingIcon,
    this.primary = false,
    this.onPressed,
    this.focusNode,
    this.onFocused,
    this.height = 44,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool primary;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onFocused;
  final double height;

  @override
  State<DesktopPill> createState() => _DesktopPillState();
}

class _DesktopPillState extends State<DesktopPill> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final type = Dims.of(context).type;
    final motion = Motion.of(context);
    final enabled = widget.onPressed != null;
    final fg = widget.primary ? c.onAccent : c.text;
    final fill = widget.primary
        ? Color.lerp(c.accent, Colors.white, _hovered ? 0.12 : 0)!
        : c.background.withValues(alpha: _hovered ? 0.65 : 0.4);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: enabled,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) widget.onFocused?.call();
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
            child: FocusRing(
              focused: _focused,
              radius: Radii.pill,
              // A press sinks the pill 4%: the click is felt before the page reacts.
              child: AnimatedScale(
                scale: _pressed ? 0.96 : 1,
                duration: motion.hoverPressTime,
                curve: Motion.curve,
                child: AnimatedContainer(
                  duration: motion.hoverPressTime,
                  height: widget.height,
                  padding: const EdgeInsets.symmetric(horizontal: Space.s24),
                  decoration: BoxDecoration(
                    color: enabled ? fill : fill.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: widget.primary ? null : Border.all(color: c.text.withValues(alpha: 0.28)),
                    boxShadow: widget.primary && _hovered
                        ? [
                            BoxShadow(
                              color: c.accent.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : const [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 22, color: fg),
                        const SizedBox(width: Space.s8),
                      ],
                      Text(widget.label, style: type.card.copyWith(color: fg)),
                      if (widget.trailingIcon != null) ...[
                        const SizedBox(width: Space.s8),
                        Icon(widget.trailingIcon, size: 18, color: fg),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
