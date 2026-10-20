import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'focus_card.dart';
import 'player_test_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    final desktop = Platform.isWindows || Platform.isLinux;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Settings', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
            'Chithram ships no sources. You add your own.',
            style: TextStyle(color: ChithramColors.textDim),
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
              child: Container(
                color: ChithramColors.surfaceHigh,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                child: Text(
                  desktop ? 'Player test (media_kit)' : 'About Chithram 0.1.0',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
