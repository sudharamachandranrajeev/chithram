import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../ui/common/dims.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;

/// The switch for the Media section (`media.enabled`, off by default). It
/// only flips the flag: nothing connects until the user pairs a server.
class MediaFlagSettings extends StatelessWidget {
  const MediaFlagSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return ListenableBuilder(
      listenable: services.prefs,
      builder: (context, _) {
        final on = services.media.enabled;
        if (Dims.of(context).phone) {
          return SwitchListTile(
            key: const ValueKey('settings-media'),
            secondary: const Icon(Icons.perm_media_rounded),
            title: const Text('Media section'),
            subtitle: const Text('Search, request and watch from your own media server (Jellyfin, Seerr). Needs a Chithram media gateway.'),
            value: on,
            onChanged: (v) => unawaited(services.media.setEnabled(v)),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(8),
          child: FocusCard(
            key: const ValueKey('settings-media'),
            radius: 24,
            onActivate: () => unawaited(services.media.setEnabled(!on)),
            child: ActionLabel(text: 'Media section: ${on ? 'on' : 'off'}'),
          ),
        );
      },
    );
  }
}
