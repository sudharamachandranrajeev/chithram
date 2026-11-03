import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/dims.dart';
import '../common/tokens.dart';
import 'dpad.dart';

/// Remembers where focus was in one section, so coming back to it (Right from
/// the nav rail) lands on the same tile.
class SectionFocus {
  /// The section's first tile; used when nothing was focused yet.
  final FocusNode entry = FocusNode(debugLabel: 'section entry');
  FocusNode? last;

  void remember(FocusNode node) => last = node;

  void focus() {
    final node = last;
    if (node != null && node.context != null && node.canRequestFocus) {
      node.requestFocus();
    } else {
      entry.requestFocus();
    }
  }

  void dispose() => entry.dispose();
}

/// Lets a tile at the left edge of a section hand focus back to the rail.
class RailScope extends InheritedWidget {
  const RailScope({super.key, required this.focusRail, required super.child});

  final VoidCallback focusRail;

  static RailScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RailScope>();

  @override
  bool updateShouldNotify(RailScope oldWidget) => false;
}

/// A tile or button that works with a D-pad; Select / Enter / tap activates it.
///
/// On a TV the focus is read from across the room ([FocusSpec.tv]): the tile
/// grows 6%, an accent ring floats just outside it and an accent glow spreads
/// around. Nothing depends on hover there. Elsewhere (phone, desktop) it grows
/// ~8% with a border and glow, and a hovering mouse highlights it.
class FocusCard extends StatefulWidget {
  const FocusCard({
    super.key,
    required this.child,
    this.onActivate,
    this.focusNode,
    this.section,
    this.onFocus,
    this.radius = 14,
  });

  final Widget child;
  final VoidCallback? onActivate;

  /// Optional external node (e.g. [SectionFocus.entry]).
  final FocusNode? focusNode;

  /// Records this tile as the section's last focused one.
  final SectionFocus? section;

  /// Called when this tile gains focus (rails use it to remember the index).
  final VoidCallback? onFocus;
  final double radius;

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  FocusNode? _own;
  bool _focused = false;
  bool _hovered = false;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'focus card'));

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    if (!mounted) return;
    setState(() => _focused = focused);
    if (focused) {
      widget.section?.remember(_node);
      widget.onFocus?.call();
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: Dims.of(context).tv ? Motion.of(context).focusTime : const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final motion = Motion.of(context);
    final radius = BorderRadius.circular(widget.radius);
    final tv = d.tv;
    final spec = d.focus;
    final hovered = _hovered && !tv;
    final Widget body;
    if (tv) {
      // The ring floats `gap` outside the tile and never changes its layout.
      final ringRadius = BorderRadius.circular(widget.radius + spec.gap + spec.ring / 2);
      final out = spec.gap + spec.ring;
      body = Stack(
        clipBehavior: Clip.none,
        // Keep the parent's constraints, as the plain container did.
        fit: StackFit.passthrough,
        children: [
          AnimatedContainer(
            duration: motion.focusTime,
            curve: Motion.curve,
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: c.accent.withValues(alpha: spec.glowAlpha),
                        blurRadius: spec.glowBlur,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(borderRadius: radius, child: widget.child),
          ),
          Positioned(
            left: -out,
            top: -out,
            right: -out,
            bottom: -out,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: motion.focusTime,
                curve: Motion.curve,
                decoration: BoxDecoration(
                  borderRadius: ringRadius,
                  border: Border.all(
                    color: _focused ? c.accent : Colors.transparent,
                    width: spec.ring,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      body = AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: _focused ? c.accent : (hovered ? c.accent.withValues(alpha: 0.6) : Colors.transparent),
            width: 2.5,
          ),
          boxShadow: _focused
              ? [BoxShadow(color: c.accent.withValues(alpha: 0.45), blurRadius: 20, spreadRadius: 1)]
              : const [],
        ),
        child: ClipRRect(borderRadius: radius, child: widget.child),
      );
    }
    return FocusableActionDetector(
      focusNode: _node,
      onFocusChange: _onFocusChange,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onActivate?.call();
          return null;
        }),
        // Like the default, but Left at a section's edge goes to the rail.
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(onInvoke: (intent) {
          final moved = moveFocus(_node, intent.direction);
          if (!moved && intent.direction == TraversalDirection.left) {
            RailScope.maybeOf(context)?.focusRail();
          }
          return null;
        }),
      },
      // Mouse hover highlights the tile but leaves focus where it is (the
      // arrows keep working from there); a click focuses and activates.
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        child: GestureDetector(
          onTap: () {
            _node.requestFocus();
            widget.onActivate?.call();
          },
          child: AnimatedScale(
            scale: _focused ? (tv ? spec.scale : 1.08) : (hovered ? 1.04 : 1.0),
            duration: tv ? motion.focusTime : const Duration(milliseconds: 150),
            curve: tv ? Motion.curve : Curves.easeOut,
            child: body,
          ),
        ),
      ),
    );
  }
}
