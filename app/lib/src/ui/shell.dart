import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'focus_card.dart';
import 'home_page.dart';
import 'placeholder_page.dart';
import 'sections.dart';
import 'settings_page.dart';

class _EnterContentIntent extends Intent {
  const _EnterContentIntent();
}

/// Nav rail on the left, the current section on the right. Focus is
/// remembered per section; Back goes content -> rail -> Home -> exit.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  bool _railHasFocus = true;
  final _sections = [for (final _ in Section.values) SectionFocus()];
  final _railNodes = [for (final s in Section.values) FocusNode(debugLabel: 'rail ${s.label}')];

  @override
  void initState() {
    super.initState();
    // Start on the rail's Home item.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _railNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final s in _sections) {
      s.dispose();
    }
    for (final n in _railNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _focusRail() => _railNodes[_index].requestFocus();

  void _enterContent() => _sections[_index].focus();

  void _onBack() {
    if (!_railHasFocus) {
      _focusRail();
    } else if (_index != 0) {
      _railNodes[0].requestFocus();
    } else {
      SystemNavigator.pop();
    }
  }

  Widget _page(Section section) {
    final focus = _sections[section.index];
    switch (section) {
      case Section.home:
        return HomePage(focus: focus);
      case Section.settings:
        return SettingsPage(focus: focus);
      default:
        return PlaceholderPage(section: section, focus: focus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // TV-sized screens: keep everything inside the 5% overscan-safe area.
    final tv = size.width >= 960;
    final padding = tv
        ? EdgeInsets.symmetric(horizontal: size.width * 0.05, vertical: size.height * 0.05)
        : EdgeInsets.zero;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: RailScope(
          focusRail: _focusRail,
          child: Padding(
            padding: padding,
            child: Row(
              children: [
                Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (has) => setState(() => _railHasFocus = has),
                  child: FocusScope(child: _buildRail()),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      for (final section in Section.values)
                        Offstage(
                          offstage: section.index != _index,
                          child: ExcludeFocus(
                            excluding: section.index != _index,
                            // Its own scope: arrows stay inside the section.
                            child: FocusScope(child: _page(section)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRail() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: _railHasFocus ? 220 : 84,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in Section.values)
            _RailItem(
              section: section,
              node: _railNodes[section.index],
              selected: section.index == _index,
              expanded: _railHasFocus,
              onFocused: () {
                if (_index != section.index) setState(() => _index = section.index);
              },
              onEnter: _enterContent,
            ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.section,
    required this.node,
    required this.selected,
    required this.expanded,
    required this.onFocused,
    required this.onEnter,
  });

  final Section section;
  final FocusNode node;
  final bool selected;
  final bool expanded;
  final VoidCallback onFocused;
  final VoidCallback onEnter;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || widget.selected;
    final color = _focused
        ? Colors.black
        : widget.selected
            ? ChithramColors.accent
            : ChithramColors.textDim;
    return FocusableActionDetector(
      focusNode: widget.node,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) widget.onFocused();
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowRight): _EnterContentIntent(),
      },
      actions: <Type, Action<Intent>>{
        _EnterContentIntent: CallbackAction<_EnterContentIntent>(onInvoke: (_) {
          widget.onEnter();
          return null;
        }),
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onEnter();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: () {
          widget.node.requestFocus();
          widget.onEnter();
        },
        child: Container(
          height: 52,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _focused ? ChithramColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: _focused
                ? [BoxShadow(color: ChithramColors.accent.withValues(alpha: 0.4), blurRadius: 16)]
                : const [],
          ),
          // Clipped and unconstrained, so the label can't overflow while the
          // rail is still growing.
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: 220,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.section.icon, color: color, size: 26),
                  if (widget.expanded) ...[
                    const SizedBox(width: 16),
                    Text(
                      widget.section.label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
