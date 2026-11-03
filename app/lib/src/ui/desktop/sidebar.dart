import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/dims.dart';
import '../common/section_shell.dart';
import '../common/sections.dart';
import '../common/tokens.dart';
import 'focus_ring.dart';

/// Prefs key: the user collapsed the sidebar to its icon rail (Ctrl+B).
const sidebarCollapsedPref = 'ui.sidebarCollapsed';

/// Below this window width the sidebar is always the icon rail.
const sidebarAutoCollapseWidth = 1200.0;

const sidebarExpandedWidth = 240.0;
const sidebarCollapsedWidth = 72.0;

/// A titled group of sidebar items.
class NavGroup {
  const NavGroup(this.title, this.sections);

  final String title;
  final List<Section> sections;
}

/// The sidebar's groups, top to bottom; Settings is pinned below them.
/// A Media group goes between these two when Media arrives (PR5).
const desktopNavGroups = [
  NavGroup('Browse', [Section.home, Section.search]),
  NavGroup('Sources', [Section.liveTv, Section.youtube, Section.torrents]),
];

/// The desktop navigation: 240 dp wide with labels, or a 72 dp icon rail.
/// Selection and focus come from [SectionShellState]; hovering never moves
/// focus and a click only shows the section (focus stays on the item).
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.collapsed,
    required this.selected,
    required this.nodes,
    required this.onFocused,
    required this.onEnter,
  });

  final bool collapsed;
  final Section selected;

  /// One node per [Section], by index.
  final List<FocusNode> nodes;
  final void Function(Section) onFocused;
  final VoidCallback onEnter;

  Widget _item(Section s) => RailItemBehavior(
        section: s,
        node: nodes[s.index],
        onFocused: () => onFocused(s),
        onEnter: onEnter,
        hoverFocuses: false,
        enterOnTap: false,
        builder: (context, focused, hovered) => _SidebarItem(
          section: s,
          selected: s == selected,
          focused: focused,
          hovered: hovered,
          collapsed: collapsed,
          onTap: () {
            onFocused(s);
            nodes[s.index].requestFocus();
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final motion = Motion.of(context);
    return AnimatedContainer(
      key: const ValueKey('desktop-sidebar'),
      duration: motion.expandTime,
      curve: Motion.curve,
      width: collapsed ? sidebarCollapsedWidth : sidebarExpandedWidth,
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.6),
        border: Border(right: BorderSide(color: c.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: Space.s12),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, g) in desktopNavGroups.indexed) ...[
                      if (collapsed)
                        (i == 0 ? const SizedBox.shrink() : _Divider(color: c.hairline))
                      else
                        _GroupTitle(g.title),
                      for (final s in g.sections) _item(s),
                    ],
                  ],
                ),
              ),
            ),
            _Divider(color: c.hairline),
            _item(Section.settings),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s16, vertical: Space.s8),
        child: Divider(height: 1, thickness: 1, color: color),
      );
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s24, Space.s16, Space.s16, Space.s8),
      child: Text(
        title.toUpperCase(),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: Dims.of(context).type.overline.copyWith(color: c.textDim),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.selected,
    required this.focused,
    required this.hovered,
    required this.collapsed,
    required this.onTap,
  });

  final Section section;
  final bool selected;
  final bool focused;
  final bool hovered;
  final bool collapsed;

  /// What a click does (also the screen reader's tap).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final type = Dims.of(context).type;
    final fg = selected || hovered ? c.text : c.textDim;
    final fill = selected
        ? c.accent2.withValues(alpha: 0.16)
        : (hovered ? c.text.withValues(alpha: 0.05) : Colors.transparent);
    final item = Semantics(
      container: true,
      button: true,
      selected: selected,
      label: section.label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: collapsed ? section.label : '',
        waitDuration: const Duration(milliseconds: 400),
        child: FocusRing(
          focused: focused,
          radius: Radii.button,
          child: Container(
            height: 44,
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(Radii.button)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.button),
              child: Stack(
                children: [
                  // The current section's bar.
                  Positioned(
                    left: 0,
                    top: 8,
                    bottom: 8,
                    child: Container(
                      key: selected ? ValueKey('nav-active-${section.name}') : null,
                      width: 3,
                      decoration: BoxDecoration(
                        color: selected ? c.accent2 : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                      ),
                    ),
                  ),
                  OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: sidebarExpandedWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(left: Space.s16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(section.icon, color: selected ? c.accent2 : fg, size: 22),
                          if (!collapsed) ...[
                            const SizedBox(width: Space.s12),
                            Text(
                              section.label,
                              maxLines: 1,
                              softWrap: false,
                              style: type.card.copyWith(
                                color: fg,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s12, vertical: 2),
      child: item,
    );
  }
}
