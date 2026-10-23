import 'package:flutter/material.dart';

import '../common/dims.dart';
import 'focus_card.dart';

/// A titled horizontal row of tiles. Reusable for every rail in the app.
///
/// - The row's scroll offset is kept (PageStorage), so it is where you left it
///   after switching sections or coming back from a details page.
/// - [lastIndex] is the tile that last had focus.
/// - Up / Down into and out of the row keep the nearest column (see
///   `moveFocus`); the section's [SectionFocus] returns to the last tile.
class FocusRail extends StatefulWidget {
  const FocusRail({
    super.key,
    required this.title,
    required this.count,
    required this.itemBuilder,
    required this.section,
    this.onSelect,
  });

  final String title;
  final int count;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final SectionFocus section;
  final void Function(int index)? onSelect;

  @override
  State<FocusRail> createState() => _FocusRailState();
}

class _FocusRailState extends State<FocusRail> {
  int lastIndex = 0;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final pad = d.phone ? 12.0 : 20.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
          child: Text(widget.title, style: TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w600)),
        ),
        // Vertical padding leaves room for the focus scale and glow.
        SingleChildScrollView(
          key: PageStorageKey<String>('rail-${widget.title}'),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
          child: Row(
            children: [
              for (var i = 0; i < widget.count; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: FocusCard(
                    section: widget.section,
                    onFocus: () => lastIndex = i,
                    onActivate: () => widget.onSelect?.call(i),
                    child: widget.itemBuilder(context, i),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A placeholder poster tile.
class PosterTile extends StatelessWidget {
  const PosterTile({super.key, required this.label, required this.hue});

  final String label;
  final double hue;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Container(
      width: d.u(220),
      height: d.u(124),
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue % 360, 0.35, 0.22).toColor(),
            HSLColor.fromAHSL(1, hue % 360, 0.30, 0.12).toColor(),
          ],
        ),
      ),
      child: Text(label, style: TextStyle(fontSize: d.t(16), fontWeight: FontWeight.w500)),
    );
  }
}
