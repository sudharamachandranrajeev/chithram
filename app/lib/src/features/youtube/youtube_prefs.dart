import '../../core/prefs.dart';

/// Keys of the YouTube settings in `prefs.json`.
abstract final class YouTubePrefs {
  /// Play the next video when one ends. On unless turned off.
  static const autoplay = 'youtube.autoplay_next';

  /// Show SponsorBlock segments on the seek bar. Off unless turned on: it asks
  /// sponsor.ajay.app (with a hashed prefix of the video id) for each video.
  static const sponsorBlock = 'youtube.sponsorblock';

  static bool autoplayOn(Prefs? p) =>
      p?.getBool(autoplay, fallback: true) ?? true;
  static bool sponsorBlockOn(Prefs? p) => p?.getBool(sponsorBlock) ?? false;
}
