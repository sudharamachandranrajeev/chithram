import 'package:flutter/material.dart';

import '../theme.dart';
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

/// A tile or button that works with a D-pad: grows ~8% and glows with the
/// accent when focused; Select / Enter / tap activates it.
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
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
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
          scale: _focused ? 1.08 : (_hovered ? 1.04 : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: _focused
                    ? ChithramColors.accent
                    : (_hovered ? ChithramColors.accent.withValues(alpha: 0.6) : Colors.transparent),
                width: 2.5,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: ChithramColors.accent.withValues(alpha: 0.45),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(borderRadius: radius, child: widget.child),
          ),
        ),
      ),
      ),
    );
  }
}
