import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui/common/dims.dart';
import '../ui/tv/focus_card.dart';
import 'player_keys.dart';
import 'player_osd.dart' show playerSpeeds, speedLabel;

/// Playback speeds: a panel at the right edge on a TV or desktop (focus
/// starts on the current speed), a bottom sheet's body on a phone. Same
/// look and behaviour as the tracks menu; the caller closes it.
class SpeedMenu extends StatefulWidget {
  const SpeedMenu({super.key, required this.speed, required this.onPick, this.sheet = false});

  final double speed;
  final ValueChanged<double> onPick;

  /// True inside a phone's bottom sheet: no panel chrome, no initial focus.
  final bool sheet;

  @override
  State<SpeedMenu> createState() => _SpeedMenuState();
}

class _SpeedMenuState extends State<SpeedMenu> {
  final _current = FocusNode(debugLabel: 'speed menu current');

  @override
  void initState() {
    super.initState();
    if (!widget.sheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _current.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final list = ListView(
      key: PlayerKeys.speedMenu,
      shrinkWrap: widget.sheet,
      padding: EdgeInsets.symmetric(vertical: d.u(16), horizontal: d.u(12)),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(d.u(12), d.u(8), d.u(12), d.u(6)),
          child: Text(
            'Playback speed',
            style: TextStyle(color: c.textDim, fontSize: d.t(14), fontWeight: FontWeight.w700),
          ),
        ),
        for (final s in playerSpeeds)
          Padding(
            padding: EdgeInsets.symmetric(vertical: d.u(3)),
            child: FocusCard(
              key: PlayerKeys.speedOption(s),
              focusNode: s == widget.speed ? _current : null,
              radius: 12,
              onActivate: () => widget.onPick(s),
              child: Container(
                color: s == widget.speed ? c.surfaceHigh : Colors.transparent,
                padding: EdgeInsets.symmetric(horizontal: d.u(12), vertical: d.u(9)),
                child: Row(
                  children: [
                    SizedBox(
                      width: d.t(28),
                      child: s == widget.speed
                          ? Icon(Icons.check_rounded, color: c.accent, size: d.t(22))
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s == 1 ? 'Normal' : speedLabel(s),
                      style: TextStyle(fontSize: d.t(16), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    if (widget.sheet) return SafeArea(child: list);
    return Align(
      alignment: Alignment.centerRight,
      // Taps on the panel stay on it (a tap beside it closes the menu).
      child: GestureDetector(
        onTap: () {},
        child: FocusScope(
          child: Container(
            width: d.tv ? 420 : 300,
            height: double.infinity,
            color: c.surface.withValues(alpha: 0.96),
            child: list,
          ),
        ),
      ),
    );
  }
}
