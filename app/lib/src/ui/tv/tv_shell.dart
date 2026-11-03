import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/dims.dart';
import '../common/glass.dart';
import '../common/section_shell.dart';
import '../common/sections.dart';
import '../common/tokens.dart';
import 'focus_card.dart';

/// The TV design: a floating frosted pill of icons on the left that opens
/// into labels while it has focus, the current section on the right, all
/// inside the overscan-safe area. Focus is remembered per section; Back goes
/// content -> rail -> Home -> exit (see [SectionShellState]).
///
/// Also the desktop's "10-foot TV mode"; a normal desktop uses `DesktopShell`.
class TvShell extends StatefulWidget {
  const TvShell({super.key});

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends SectionShellState<TvShell> {
  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    return wrapBack(
      Scaffold(
        body: ColoredBox(
          // The design's flat Night background: no glow on a TV.
          color: c.background,
          child: RailScope(
            focusRail: focusRail,
            // TV: keep everything inside the 5% overscan-safe area.
            child: Overscan(
              child: Row(children: [buildNav(_buildRail(d)), Expanded(child: buildContent())]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRail(Dims d) {
    final c = ChithramColors.of(context);
    return Center(
      child: AnimatedContainer(
        duration: Motion.of(context).expandTime,
        curve: Motion.curve,
        width: railHasFocus ? d.railOpen : d.railClosed,
        margin: const EdgeInsets.only(left: Space.s4, right: Space.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The brand mark above the pill.
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: _markSize,
                height: _markSize,
                margin: EdgeInsets.only(left: (d.railClosed - _markSize) / 2, bottom: Space.s12),
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(Radii.button)),
              ),
            ),
            Glass(
              radius: Radii.pill,
              color: c.surface,
              padding: const EdgeInsets.symmetric(vertical: Space.s12, horizontal: Space.s8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The Media item sits between the sources and Settings, only
                  // while `media.enabled` is on (the enum order does it).
                  for (final section in Section.values)
                    if (section != Section.media || mediaOn)
                    RailItemBehavior(
                      section: section,
                      node: railNodes[section.index],
                      onFocused: () => show(section),
                      onEnter: enterContent,
                      builder: (context, focused, _) => _RailItem(
                        section: section,
                        focused: focused,
                        selected: section.index == index,
                        expanded: railHasFocus,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const double _markSize = 32;

/// One icon of the pill: accent-filled while focused; the current section
/// gets a soft tint and an accent bar on its left while focus is elsewhere.
class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.section,
    required this.focused,
    required this.selected,
    required this.expanded,
  });

  final Section section;
  final bool focused;
  final bool selected;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final motion = Motion.of(context);
    final spec = d.focus;
    final color = focused ? c.onAccent : (selected ? c.text : c.textDim);
    return AnimatedContainer(
      duration: motion.focusTime,
      curve: Motion.curve,
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: Space.s4 / 2),
      decoration: BoxDecoration(
        color: focused
            ? c.accent
            : (selected ? c.accent2.withValues(alpha: 0.18) : Colors.transparent),
        borderRadius: BorderRadius.circular(Radii.pill),
        boxShadow: focused
            ? [BoxShadow(color: c.accent.withValues(alpha: spec.glowAlpha), blurRadius: spec.glowBlur)]
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
              // The current section's marker.
              AnimatedContainer(
                duration: motion.hoverPressTime,
                width: 3,
                height: selected && !focused ? 22 : 0,
                margin: const EdgeInsets.only(left: 2, right: 10),
                decoration: BoxDecoration(color: c.accent2, borderRadius: BorderRadius.circular(2)),
              ),
              Icon(section.icon, color: color, size: d.u(26)),
              if (expanded) ...[
                const SizedBox(width: Space.s12),
                Text(
                  section.label,
                  maxLines: 1,
                  softWrap: false,
                  style: d.type.card.copyWith(
                    color: color,
                    fontWeight: focused || selected ? FontWeight.w600 : FontWeight.w500,
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
