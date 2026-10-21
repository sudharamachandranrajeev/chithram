import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'dims.dart';
import 'focus_card.dart';
import 'home_page.dart';
import 'placeholder_page.dart';
import 'search_page.dart';
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
    FocusManager.instance.addListener(_guardFocus);
  }

  bool _guardQueued = false;

  /// Focus is never lost: if nothing (or only a scope) is focused while the
  /// shell is the visible route, put it back on the current rail item.
  void _guardFocus() {
    if (_guardQueued) return;
    _guardQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guardQueued = false;
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      final f = FocusManager.instance.primaryFocus;
      if (f == null || f is FocusScopeNode || f.context == null) {
        _railNodes[_index].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_guardFocus);
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
      case Section.search:
        return SearchPage(focus: focus);
      case Section.settings:
        return SettingsPage(focus: focus);
      default:
        return PlaceholderPage(section: section, focus: focus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final content = Stack(
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
    );
    final nav = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) => setState(() => _railHasFocus = has),
      child: FocusScope(child: d.phone ? _buildBottomNav(d) : _buildRail(d)),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: RailScope(
          focusRail: _focusRail,
          // TV: keep everything inside the 5% overscan-safe area.
          child: Overscan(
            child: d.phone
                ? SafeArea(
                    child: Column(children: [Expanded(child: content), nav]),
                  )
                : Row(children: [nav, Expanded(child: content)]),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav(Dims d) {
    return Container(
      color: ChithramColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          for (final section in Section.values)
            Expanded(
              child: _RailItem(
                section: section,
                node: _railNodes[section.index],
                selected: section.index == _index,
                expanded: false,
                bottom: true,
                dims: d,
                onFocused: () {
                  if (_index != section.index) setState(() => _index = section.index);
                },
                onEnter: () {},
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRail(Dims d) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: _railHasFocus ? d.railOpen : d.railClosed,
      padding: EdgeInsets.symmetric(vertical: d.tv ? 8 : 24, horizontal: 8),
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
              dims: d,
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
    required this.dims,
    this.bottom = false,
    required this.onFocused,
    required this.onEnter,
  });

  final Section section;
  final FocusNode node;
  final bool selected;
  final bool expanded;
  final Dims dims;
  final bool bottom;
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
      shortcuts: widget.bottom
          ? const <ShortcutActivator, Intent>{}
          : const <ShortcutActivator, Intent>{
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
      child: MouseRegion(
        onEnter: (_) {
          if (!widget.node.hasFocus) widget.node.requestFocus();
        },
        child: GestureDetector(
          key: ValueKey('nav-${widget.section.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.node.requestFocus();
            widget.onEnter();
          },
          child: widget.bottom ? _bottomItem(color, active) : _railItem(color, active),
        ),
      ),
    );
  }

  Widget _bottomItem(Color color, bool active) {
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _focused ? ChithramColors.accent.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.section.icon, color: _focused ? ChithramColors.accent : color, size: 24),
          Text(
            widget.section.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: _focused ? ChithramColors.accent : color,
              fontSize: 10,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _railItem(Color color, bool active) {
    final d = widget.dims;
    return Container(
      height: d.tv ? 56 : 52,
      margin: EdgeInsets.symmetric(vertical: d.tv ? 2 : 4),
      padding: EdgeInsets.symmetric(horizontal: d.tv ? 26 : 16),
      decoration: BoxDecoration(
        color: _focused ? ChithramColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(d.u(26)),
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
          maxWidth: d.railOpen,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.section.icon, color: color, size: d.u(26)),
              if (widget.expanded) ...[
                const SizedBox(width: 16),
                Text(
                  widget.section.label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: color,
                    fontSize: d.t(16),
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
