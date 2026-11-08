import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/dims.dart';
import '../common/keys.dart';
import '../common/tokens.dart';
import 'focus_ring.dart';
import 'window_chrome.dart';

const titleBarHeight = 40.0;

/// The 40 dp bar on top of the desktop window: logo and name on the left, the
/// search field in the middle, the window buttons on the right.
///
/// With a custom frame ([WindowChrome.custom], Windows) the empty part of the
/// bar drags the window (double-click maximises) and the window buttons show.
/// With the native frame (Linux) it is only a toolbar.
///
/// [onBack] set (a page is open over the shell) puts a Back button before the
/// logo, so a mouse user always has a way back without knowing Esc.
class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({
    super.key,
    required this.chrome,
    required this.searchFocus,
    required this.searchController,
    required this.onSearchSubmitted,
    this.onBack,
  });

  final WindowChrome chrome;
  final FocusNode searchFocus;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final custom = chrome.custom;
    return SizedBox(
      height: titleBarHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.background.withValues(alpha: 0.9),
          border: Border(bottom: BorderSide(color: c.hairline)),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final searchWidth = math.min(520.0, math.max(240.0, box.maxWidth * 0.4));
            return Stack(
              children: [
                // The drag area: the whole bar; what sits on top takes its own clicks.
                if (custom)
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('titlebar-drag'),
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (_) => chrome.startDrag(),
                      onDoubleTap: chrome.toggleMaximize,
                    ),
                  ),
                Positioned.fill(
                  child: Row(
                    children: [
                      _BackSlot(onBack: onBack),
                      const IgnorePointer(child: _Brand()),
                      const Spacer(),
                      if (custom) WindowButtons(chrome: chrome),
                    ],
                  ),
                ),
                Center(
                  child: SizedBox(
                    width: searchWidth,
                    child: _SearchField(
                      focus: searchFocus,
                      controller: searchController,
                      onSubmitted: onSearchSubmitted,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The Back button's place: it grows in when a page opens over the shell and
/// takes no room on the shell itself.
class _BackSlot extends StatelessWidget {
  const _BackSlot({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    return AnimatedSize(
      duration: Motion.of(context).expandTime,
      curve: Motion.curve,
      child: back == null
          ? const SizedBox(height: titleBarHeight)
          : Padding(
              padding: const EdgeInsets.only(left: Space.s4),
              child: TitleBarButton(
                key: Keys.titleBarBack,
                label: 'Back',
                tooltip: 'Back (Esc)',
                icon: Icons.arrow_back_rounded,
                width: 40,
                onPressed: back,
              ),
            ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: Space.s16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(5)),
          ),
          const SizedBox(width: Space.s8),
          Text('Chithram', style: Dims.of(context).type.card.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.focus, required this.controller, required this.onSubmitted});

  final FocusNode focus;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.focus.removeListener(_changed);
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final type = Dims.of(context).type;
    final focused = widget.focus.hasFocus;
    return Semantics(
      textField: true,
      label: 'Search',
      child: FocusRing(
        focused: focused,
        radius: 15,
        child: AnimatedContainer(
          duration: Motion.of(context).hoverPressTime,
          height: 30,
          padding: const EdgeInsets.only(left: Space.s12, right: Space.s8),
          decoration: BoxDecoration(
            color: c.surfaceHigh.withValues(alpha: focused ? 0.9 : 0.6),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: focused ? c.accent.withValues(alpha: 0.6) : c.hairline),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 16, color: c.textDim),
              const SizedBox(width: Space.s8),
              Expanded(
                child: TextField(
                  key: const ValueKey('titlebar-search'),
                  focusNode: widget.focus,
                  controller: widget.controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: widget.onSubmitted,
                  cursorColor: c.accent,
                  style: type.body.copyWith(color: c.text, fontSize: 13),
                  decoration: InputDecoration.collapsed(
                    hintText: 'Search movies, channels, videos…',
                    hintStyle: type.body.copyWith(color: c.textDim, fontSize: 13),
                  ),
                ),
              ),
              if (widget.controller.text.isEmpty && !focused)
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: c.text.withValues(alpha: 0.2)),
                    ),
                    child: Text('Ctrl K', style: type.meta.copyWith(color: c.textDim, fontSize: 11)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimise, maximise and close. Public for the player, which covers the
/// title bar and draws these in its own top bar ([foreground] over video).
class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key, required this.chrome, this.foreground, this.height = titleBarHeight});

  final WindowChrome chrome;
  final Color? foreground;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: chrome.maximized,
      builder: (context, maximized, _) => Row(
        children: [
          TitleBarButton(
            label: 'Minimize',
            icon: Icons.remove_rounded,
            onPressed: chrome.minimize,
            foreground: foreground,
            height: height,
          ),
          TitleBarButton(
            label: maximized ? 'Restore' : 'Maximize',
            icon: maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            onPressed: chrome.toggleMaximize,
            foreground: foreground,
            height: height,
          ),
          TitleBarButton(
            label: 'Close',
            icon: Icons.close_rounded,
            onPressed: chrome.close,
            danger: true,
            foreground: foreground,
            height: height,
          ),
        ],
      ),
    );
  }
}

/// A flat title-bar button: a window button, or Back.
class TitleBarButton extends StatefulWidget {
  const TitleBarButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.foreground,
    this.tooltip,
    this.width = 46,
    this.height = titleBarHeight,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;
  final Color? foreground;

  /// Shown on hover; null shows none (the window buttons are self-evident).
  final String? tooltip;
  final double width;
  final double height;

  @override
  State<TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<TitleBarButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final hot = _hovered && widget.danger;
    final fg = widget.foreground ?? c.text;
    final button = Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: FocusableActionDetector(
        onFocusChange: (f) => setState(() => _focused = f),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onPressed();
            return null;
          }),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: FocusRing(
              focused: _focused,
              radius: 4,
              child: Container(
                width: widget.width,
                height: widget.height,
                color: hot
                    ? const Color(0xFFE81123)
                    : (_hovered ? fg.withValues(alpha: 0.08) : Colors.transparent),
                child: Icon(widget.icon, size: 16, color: hot ? Colors.white : fg),
              ),
            ),
          ),
        ),
      ),
    );
    final tip = widget.tooltip;
    return tip == null
        ? button
        : Tooltip(message: tip, waitDuration: const Duration(milliseconds: 500), child: button);
  }
}
