import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'dims.dart';
import 'focus_card.dart';
import 'home_page.dart' show ActionLabel;
import 'player_test_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    final desktop = Platform.isWindows || Platform.isLinux;
    final d = Dims.of(context);
    return Padding(
      padding: EdgeInsets.all(d.phone ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Settings', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Chithram ships no sources. You add your own.',
            style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.all(8),
            child: FocusCard(
              focusNode: focus.entry,
              section: focus,
              radius: 24,
              onActivate: desktop
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const PlayerTestPage()),
                      )
                  : () {},
              child: ActionLabel(text: desktop ? 'Player test (media_kit)' : 'About Chithram 0.1.0'),
            ),
          ),
        ],
      ),
    );
  }
}
