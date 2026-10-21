import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/services.dart';
import 'focus_card.dart';
import 'form_factor.dart';
import 'home_page.dart' show ActionLabel;

/// Desktop only: "10-foot TV mode" lays the TV design out at TV sizes. It
/// applies at once and sends the app back to Home.
class InterfaceSettings extends StatelessWidget {
  const InterfaceSettings({super.key});

  static bool get available =>
      defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    if (!available) return const SizedBox.shrink();
    final prefs = AppServices.of(context).prefs;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final on = prefs.getBool(tenFootPref);
        return Padding(
          padding: const EdgeInsets.all(8),
          child: FocusCard(
            radius: 24,
            onActivate: () => prefs.set(tenFootPref, !on),
            child: ActionLabel(text: '10-foot TV mode: ${on ? 'on' : 'off'}'),
          ),
        );
      },
    );
  }
}
