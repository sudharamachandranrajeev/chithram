import 'package:chithram_player/chithram_player.dart';

import '../core/prefs.dart';

/// Keys of the player's track settings in `prefs.json`. They follow the
/// last choice in the audio and subtitle menu.
abstract final class PlayerPrefs {
  /// Language code of the last audio track picked by hand.
  static const audioLanguage = 'player.audio_language';

  /// Subtitles on or off. Off unless turned on.
  static const subtitles = 'player.subtitles';

  /// Language code of the last subtitle track picked.
  static const subtitleLanguage = 'player.subtitle_language';

  /// The picture shape, a `VideoAspect` name.
  static const aspect = 'player.aspect';

  static TrackPreferences read(Prefs? p) => TrackPreferences(
    audioLanguage: p?.getString(audioLanguage),
    subtitleLanguage: p?.getString(subtitleLanguage),
    subtitles: p?.getBool(subtitles) ?? false,
  );
}

const _languageNames = <String, String>{
  'en': 'English', 'ml': 'Malayalam', 'ta': 'Tamil', 'hi': 'Hindi',
  'te': 'Telugu', 'kn': 'Kannada', 'bn': 'Bengali', 'mr': 'Marathi',
  'gu': 'Gujarati', 'pa': 'Punjabi', 'ur': 'Urdu', 'or': 'Odia',
  'as': 'Assamese', 'sa': 'Sanskrit', 'si': 'Sinhala', 'ne': 'Nepali',
  'es': 'Spanish', 'fr': 'French', 'de': 'German', 'it': 'Italian',
  'pt': 'Portuguese', 'ru': 'Russian', 'ja': 'Japanese', 'ko': 'Korean',
  'zh': 'Chinese', 'ar': 'Arabic', 'tr': 'Turkish', 'nl': 'Dutch',
  'pl': 'Polish', 'sv': 'Swedish', 'no': 'Norwegian', 'da': 'Danish',
  'fi': 'Finnish', 'el': 'Greek', 'he': 'Hebrew', 'th': 'Thai',
  'vi': 'Vietnamese', 'id': 'Indonesian', 'ms': 'Malay', 'fa': 'Persian',
  'uk': 'Ukrainian', 'cs': 'Czech', 'hu': 'Hungarian', 'ro': 'Romanian',
  'tl': 'Filipino',
};

/// "Malayalam" for 'ml'; an unknown code in capitals; null for null.
String? languageName(String? code) {
  if (code == null || code.isEmpty) return null;
  return _languageNames[code] ?? code.toUpperCase();
}

// Open format names only; vendor formats show no codec.
const _codecNames = <String, String>{
  'aac': 'AAC', 'ac3': 'AC-3', 'eac3': 'E-AC-3', 'opus': 'Opus',
  'vorbis': 'Vorbis', 'flac': 'FLAC', 'mp3': 'MP3', 'pcm': 'PCM',
  'srt': 'SRT', 'ssa': 'SSA', 'webvtt': 'WebVTT', 'pgs': 'PGS',
  'vobsub': 'VobSub', 'dvbsub': 'DVB', 'cc': 'CC', 'ttml': 'TTML',
};

String? _channels(int? n) => switch (n) {
  null || <= 0 => null,
  1 => 'Mono',
  2 => 'Stereo',
  6 => '5.1',
  8 => '7.1',
  _ => '$n ch',
};

/// The first line of a track in the menu: its language, else its own title,
/// else "Track 2".
String trackTitle(MediaTrack t, int index) =>
    languageName(t.language) ?? _nonEmpty(t.label) ?? 'Track ${index + 1}';

/// The second line: title (when the first line is the language), codec,
/// channels, "Forced". Empty when nothing is known.
String trackDetail(MediaTrack t) {
  final label = _nonEmpty(t.label);
  return [
    if (label != null && languageName(t.language) != null && label != languageName(t.language)) label,
    ?_codecNames[t.codec],
    ?_channels(t.channels),
    if (t.forced) 'Forced',
  ].join(' · ');
}

String? _nonEmpty(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

/// The track to use for [language]: one in that language (not forced, when
/// there is a choice), else the default one, else the first. Null for an
/// empty list.
MediaTrack? preferredTrack(List<MediaTrack> tracks, String? language) {
  if (tracks.isEmpty) return null;
  if (language != null) {
    final same = tracks.where((t) => t.language == language).toList();
    if (same.isNotEmpty) {
      return same.firstWhere((t) => !t.forced, orElse: () => same.first);
    }
  }
  return tracks.firstWhere((t) => t.isDefault, orElse: () => tracks.first);
}

/// YouTube's dubbed tracks as menu entries; ids are `choice:<index>`.
List<MediaTrack> choiceTracks(MediaSpec spec) => [
  for (final (i, c) in spec.audioChoices.indexed)
    MediaTrack(
      id: '$choicePrefix$i',
      language: c.language,
      label: c.label,
      selected: c.url == spec.audioUrl,
      isDefault: c.isDefault,
    ),
];

const choicePrefix = 'choice:';
