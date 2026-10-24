import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../tv/focus_card.dart';
import 'form_factor.dart';
import 'sfx.dart';
import '../tv/home_page.dart' show ActionLabel;

/// Keyboard sounds on and off (where the app plays sounds), and, on desktop,
/// "10-foot TV mode", which lays the TV design out at TV sizes; it applies at
/// once and sends the app back to Home.
class InterfaceSettings extends StatelessWidget {
  const InterfaceSettings({super.key});

  static bool get available =>
      defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    if (!available && !sfxSupported) return const SizedBox.shrink();
    final prefs = AppServices.of(context).prefs;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final tenFoot = prefs.getBool(tenFootPref);
        final sounds = prefs.getBool(soundsPref, fallback: true);
        return Wrap(
          children: [
            if (sfxSupported)
              Padding(
                padding: const EdgeInsets.all(8),
                child: FocusCard(
                  key: const ValueKey('settings-sounds'),
                  radius: 24,
                  onActivate: () => prefs.set(soundsPref, !sounds),
                  child: ActionLabel(text: 'Keyboard sounds: ${sounds ? 'on' : 'off'}'),
                ),
              ),
            if (available)
              Padding(
                padding: const EdgeInsets.all(8),
                child: FocusCard(
                  radius: 24,
                  onActivate: () => prefs.set(tenFootPref, !tenFoot),
                  child: ActionLabel(text: '10-foot TV mode: ${tenFoot ? 'on' : 'off'}'),
                ),
              ),
          ],
        );
      },
    );
  }
}
