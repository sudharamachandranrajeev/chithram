/// One audio or subtitle track of the playing media.
class MediaTrack {
  const MediaTrack({
    required this.id,
    this.language,
    this.label,
    this.codec,
    this.channels,
    this.selected = false,
    this.isDefault = false,
    this.forced = false,
  });

  /// The engine's id; hand it back to `selectAudioTrack` and friends. Only
  /// valid for the media it came with.
  final String id;

  /// Two-letter code where one exists ('en', 'ml'), else what the file says;
  /// see [normalizeLanguage]. Null when unknown.
  final String? language;

  /// The track's own title, e.g. "Commentary" or "English (SDH)".
  final String? label;

  /// Short codec name, see [shortCodec]: 'aac', 'ac3', 'srt', 'pgs', ...
  final String? codec;
  final int? channels;
  final bool selected;
  final bool isDefault;
  final bool forced;

  MediaTrack copyWith({bool? selected}) => MediaTrack(
    id: id,
    language: language,
    label: label,
    codec: codec,
    channels: channels,
    selected: selected ?? this.selected,
    isDefault: isDefault,
    forced: forced,
  );

  @override
  String toString() =>
      'MediaTrack($id, $language, $label, $codec, ch: $channels${selected ? ', selected' : ''})';
}

/// What the media offers. Empty until the engine knows (and between items).
class MediaTracks {
  const MediaTracks({this.audio = const [], this.subtitles = const []});

  static const none = MediaTracks();

  final List<MediaTrack> audio;
  final List<MediaTrack> subtitles;

  MediaTrack? get selectedAudio => _selected(audio);

  /// Null when subtitles are off.
  MediaTrack? get selectedSubtitle => _selected(subtitles);

  static MediaTrack? _selected(List<MediaTrack> list) {
    for (final t in list) {
      if (t.selected) return t;
    }
    return null;
  }

  @override
  String toString() => 'MediaTracks(audio: $audio, subtitles: $subtitles)';
}

/// What [PlayerEngine.open] should pick by itself. Languages are codes as in
/// [MediaTrack.language]; null means no preference.
class TrackPreferences {
  const TrackPreferences({
    this.audioLanguage,
    this.subtitleLanguage,
    this.subtitles = false,
  });

  final String? audioLanguage;
  final String? subtitleLanguage;

  /// Off: no subtitle track is picked.
  final bool subtitles;

  @override
  bool operator ==(Object other) =>
      other is TrackPreferences &&
      other.audioLanguage == audioLanguage &&
      other.subtitleLanguage == subtitleLanguage &&
      other.subtitles == subtitles;

  @override
  int get hashCode => Object.hash(audioLanguage, subtitleLanguage, subtitles);

  @override
  String toString() =>
      'TrackPreferences(audio: $audioLanguage, subtitles: ${subtitles ? subtitleLanguage ?? 'on' : 'off'})';
}

/// Another audio stream of the same video that the engine is not playing
/// (YouTube's dubbed tracks). The app switches by opening again with [url] as
/// the audio.
class AudioChoice {
  const AudioChoice({
    required this.url,
    this.language,
    this.label,
    this.isDefault = false,
  });

  final String url;
  final String? language;
  final String? label;

  /// The original-language track.
  final bool isDefault;
}

// ISO 639-2 (bibliographic and terminology) to 639-1, for the languages a
// file is likely to carry. Matroska and mpv report the three-letter form.
const _iso639_2 = <String, String>{
  'eng': 'en',
  'mal': 'ml',
  'tam': 'ta',
  'hin': 'hi',
  'tel': 'te',
  'kan': 'kn',
  'ben': 'bn',
  'mar': 'mr',
  'guj': 'gu',
  'pan': 'pa',
  'urd': 'ur',
  'ori': 'or',
  'asm': 'as',
  'san': 'sa',
  'sin': 'si',
  'nep': 'ne',
  'spa': 'es',
  'fre': 'fr',
  'fra': 'fr',
  'ger': 'de',
  'deu': 'de',
  'ita': 'it',
  'por': 'pt',
  'rus': 'ru',
  'jpn': 'ja',
  'kor': 'ko',
  'chi': 'zh',
  'zho': 'zh',
  'ara': 'ar',
  'tur': 'tr',
  'dut': 'nl',
  'nld': 'nl',
  'pol': 'pl',
  'swe': 'sv',
  'nor': 'no',
  'dan': 'da',
  'fin': 'fi',
  'gre': 'el',
  'ell': 'el',
  'heb': 'he',
  'tha': 'th',
  'vie': 'vi',
  'ind': 'id',
  'may': 'ms',
  'msa': 'ms',
  'per': 'fa',
  'fas': 'fa',
  'ukr': 'uk',
  'cze': 'cs',
  'ces': 'cs',
  'hun': 'hu',
  'rum': 'ro',
  'ron': 'ro',
  'fil': 'tl',
  'tgl': 'tl',
};

/// 'eng', 'en-US', 'EN' and 'en' all become 'en'. 'und', empty and null
/// (unknown) become null. Codes with no two-letter form stay as given.
String? normalizeLanguage(String? code) {
  if (code == null) return null;
  var c = code.trim().toLowerCase().replaceAll('_', '-');
  final dash = c.indexOf('-');
  if (dash > 0) c = c.substring(0, dash);
  if (c.isEmpty || c == 'und' || c == 'unknown' || c == 'mul' || c == 'zxx') {
    return null;
  }
  return _iso639_2[c] ?? c;
}

/// A short codec name from a MIME type (Media3) or a decoder name (mpv).
/// Null when unknown.
String? shortCodec(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final r = raw.toLowerCase();
  if (r.contains('mp4a') || r.endsWith('/aac') || r == 'aac') return 'aac';
  if (r.contains('eac3') || r.contains('ec-3')) return 'eac3';
  if (r.contains('ac3') || r.contains('ac-3')) return 'ac3';
  if (r.contains('opus')) return 'opus';
  if (r.contains('vorbis')) return 'vorbis';
  if (r.contains('flac')) return 'flac';
  if (r == 'audio/mpeg' || r == 'mp3' || r == 'mp2' || r == 'audio/mpeg-l2') {
    return 'mp3';
  }
  if (r == 'audio/raw' || r.startsWith('pcm')) return 'pcm';
  if (r.contains('dts') || r == 'dca') return 'dts';
  if (r.contains('true-hd') || r.contains('truehd') || r == 'mlp') {
    return 'truehd';
  }
  if (r.contains('subrip') || r == 'srt') return 'srt';
  if (r.contains('ssa') || r == 'ass') return 'ssa';
  if (r.contains('vtt')) return 'webvtt';
  if (r.contains('pgs')) return 'pgs';
  if (r.contains('vobsub') || r == 'dvd_subtitle') return 'vobsub';
  if (r.contains('dvb')) return 'dvbsub';
  if (r.contains('cea-608') || r.contains('cea-708') || r.contains('eia_608')) {
    return 'cc';
  }
  if (r.contains('ttml')) return 'ttml';
  if (r.contains('tx3g') || r == 'mov_text') return 'tx3g';
  return null;
}
