import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/dims.dart';
import '../common/glass.dart';
import '../common/section_shell.dart';
import '../common/sections.dart';
import 'focus_card.dart';

/// The TV design: a floating frosted pill of icons on the left that opens
/// into labels while it has focus, the current section on the right, all
/// inside the overscan-safe area. Focus is remembered per section; Back goes
/// content -> rail -> Home -> exit (see [SectionShellState]).
///
/// Also the desktop's "10-foot TV mode". Desktop has no shell of its own yet.
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
        body: DecoratedBox(
          // A faint accent glow in the top-left corner, behind everything.
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1.1, -1.2),
              radius: 1.3,
              colors: [c.heroTint.withValues(alpha: 0.18), c.background],
            ),
          ),
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
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: railHasFocus ? d.railOpen : d.railClosed,
        margin: const EdgeInsets.only(left: 4, right: 8),
        child: Glass(
          radius: 38,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final section in Section.values)
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
      ),
    );
  }
}

/// One icon of the pill: accent-filled while focused; the current section
/// gets an accent bar on its left while focus is elsewhere.
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
    final color = focused ? c.onAccent : (selected ? c.text : c.textDim);
    return Container(
      height: d.tv ? 44 : 52,
      margin: EdgeInsets.symmetric(vertical: d.tv ? 3 : 4),
      decoration: BoxDecoration(
        color: focused ? c.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(d.tv ? 22 : 26),
        boxShadow: focused ? [BoxShadow(color: c.accent.withValues(alpha: 0.45), blurRadius: 18)] : const [],
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
                duration: const Duration(milliseconds: 150),
                width: 3,
                height: selected && !focused ? 22 : 0,
                margin: const EdgeInsets.only(left: 2, right: 10),
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(2)),
              ),
              Icon(section.icon, color: color, size: d.u(26)),
              if (expanded) ...[
                SizedBox(width: d.tv ? 12 : 16),
                Text(
                  section.label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: color,
                    fontSize: d.t(16),
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
