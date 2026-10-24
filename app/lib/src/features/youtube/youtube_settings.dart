import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;

/// Settings: forget what Home learnt from YouTube plays and searches. The
/// first press arms, the second clears, so a stray press on a remote does not.
class YouTubeSettings extends StatefulWidget {
  const YouTubeSettings({super.key});

  @override
  State<YouTubeSettings> createState() => _YouTubeSettingsState();
}

class _YouTubeSettingsState extends State<YouTubeSettings> {
  bool _armed = false;

  Future<void> _press() async {
    if (!_armed) {
      setState(() => _armed = true);
      return;
    }
    await AppServices.of(context).youtube.taste.clear();
    if (mounted) setState(() => _armed = false);
  }

  @override
  Widget build(BuildContext context) {
    final taste = AppServices.of(context).youtube.taste;
    return ListenableBuilder(
      listenable: taste,
      builder: (context, _) {
        final plays = taste.profile.history.length;
        return Padding(
          padding: const EdgeInsets.all(8),
          child: FocusCard(
            radius: 24,
            onActivate: _press,
            child: ActionLabel(
              text: _armed
                  ? 'Press again to forget $plays YouTube plays'
                  : 'Clear YouTube watch history ($plays plays, kept on this device)',
            ),
          ),
        );
      },
    );
  }
}
