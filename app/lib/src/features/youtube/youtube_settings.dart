import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import 'youtube_prefs.dart';

/// Settings: autoplay, SponsorBlock on the seek bar, and forget what Home learnt from YouTube plays and searches. The
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
        final prefs = AppServices.of(context).prefs;
        return ListenableBuilder(
          listenable: prefs,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: FocusCard(
                  radius: 24,
                  onActivate: () => prefs.set(
                    YouTubePrefs.autoplay,
                    !YouTubePrefs.autoplayOn(prefs),
                  ),
                  child: ActionLabel(
                    text:
                        'Autoplay next video: ${YouTubePrefs.autoplayOn(prefs) ? 'On' : 'Off'}',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: FocusCard(
                  radius: 24,
                  onActivate: () => prefs.set(
                    YouTubePrefs.sponsorBlock,
                    !YouTubePrefs.sponsorBlockOn(prefs),
                  ),
                  child: ActionLabel(
                    text:
                        'SponsorBlock segments on the seek bar: ${YouTubePrefs.sponsorBlockOn(prefs) ? 'On' : 'Off'}',
                  ),
                ),
              ),
              _clearCard(plays),
            ],
          ),
        );
      },
    );
  }

  Widget _clearCard(int plays) {
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
  }
}
