import 'package:chithram_player/chithram_player.dart';
import 'package:chithram_player/src/android_engine.dart';
import 'package:chithram_player/src/media_kit_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

void main() {
  test('languages: three-letter, regional and unknown codes', () {
    expect(normalizeLanguage('mal'), 'ml');
    expect(normalizeLanguage('tam'), 'ta');
    expect(normalizeLanguage('en-US'), 'en');
    expect(normalizeLanguage('EN'), 'en');
    expect(normalizeLanguage('pt_BR'), 'pt');
    expect(normalizeLanguage('ger'), 'de');
    expect(normalizeLanguage('und'), isNull);
    expect(normalizeLanguage(''), isNull);
    expect(normalizeLanguage(null), isNull);
    expect(normalizeLanguage('xyz'), 'xyz');
  });

  test('codecs from Media3 MIME types and mpv names', () {
    expect(shortCodec('audio/mp4a-latm'), 'aac');
    expect(shortCodec('audio/eac3-joc'), 'eac3');
    expect(shortCodec('audio/ac3'), 'ac3');
    expect(shortCodec('eac3'), 'eac3');
    expect(shortCodec('audio/opus'), 'opus');
    expect(shortCodec('application/x-subrip'), 'srt');
    expect(shortCodec('subrip'), 'srt');
    expect(shortCodec('text/x-ssa'), 'ssa');
    expect(shortCodec('ass'), 'ssa');
    expect(shortCodec('text/vtt'), 'webvtt');
    expect(shortCodec('hdmv_pgs_subtitle'), 'pgs');
    expect(shortCodec('application/cea-608'), 'cc');
    expect(shortCodec('audio/vnd.dts.hd'), 'dts');
    expect(shortCodec('video/whatever'), isNull);
    expect(shortCodec(null), isNull);
  });

  test('the Media3 tracks event', () {
    final t = androidTracks({
      't': 'tracks',
      'audio': [
        {
          'id': '0:0',
          'lang': 'ml',
          'label': null,
          'mime': 'audio/mp4a-latm',
          'ch': 6,
          'sel': true,
          'def': true,
        },
        {
          'id': '1:0',
          'lang': 'ta',
          'label': 'Dub',
          'mime': 'audio/ac3',
          'ch': 2,
          'sel': false,
        },
      ],
      'text': [
        // Subtitles parsed during extraction carry the source format in codecs.
        {
          'id': '2:0',
          'lang': 'en',
          'mime': 'application/x-media3-cues',
          'codecs': 'application/x-subrip',
          'forced': true,
        },
      ],
    });
    expect(t.audio.map((a) => a.id), ['0:0', '1:0']);
    expect(t.selectedAudio!.language, 'ml');
    expect(t.audio.first.codec, 'aac');
    expect(t.audio.first.channels, 6);
    expect(t.audio.first.isDefault, isTrue);
    expect(t.audio.last.label, 'Dub');
    expect(t.subtitles.single.codec, 'srt');
    expect(t.subtitles.single.forced, isTrue);
    expect(t.selectedSubtitle, isNull);
    expect(androidTracks({'t': 'tracks'}).audio, isEmpty);
  });

  test('mpv tracks: pseudo-tracks dropped, selection from aid and sid', () {
    final tracks = mk.Tracks(
      audio: [
        mk.AudioTrack.auto(),
        mk.AudioTrack.no(),
        const mk.AudioTrack(
          '1',
          'Main',
          'mal',
          codec: 'aac',
          audiochannels: 6,
          isDefault: true,
        ),
        const mk.AudioTrack('2', null, 'eng', codec: 'eac3', channelscount: 2),
      ],
      subtitle: [
        mk.SubtitleTrack.auto(),
        mk.SubtitleTrack.no(),
        const mk.SubtitleTrack('1', 'Full', 'eng', codec: 'subrip'),
      ],
    );
    final t = mpvTracks(tracks, aid: '2', sid: null);
    expect(t.audio.map((a) => a.id), ['1', '2']);
    expect(t.audio.first.language, 'ml');
    expect(t.audio.first.channels, 6);
    expect(t.audio.last.channels, 2);
    expect(t.selectedAudio!.id, '2');
    expect(t.subtitles.single.codec, 'srt');
    expect(t.selectedSubtitle, isNull);
    expect(mpvTracks(tracks, sid: '1').selectedSubtitle!.label, 'Full');
    expect(mpvTrackId('no'), isNull);
    expect(mpvTrackId('auto'), isNull);
    expect(mpvTrackId('3'), '3');
  });

  test('MediaSpec.withAudio keeps the rest', () {
    const spec = MediaSpec(
      videoUrl: 'v',
      audioUrl: 'a1',
      headers: {'User-Agent': 'u'},
      audioChoices: [
        AudioChoice(url: 'a1'),
        AudioChoice(url: 'a2'),
      ],
    );
    final other = spec.withAudio('a2', start: const Duration(seconds: 5));
    expect(other.audioUrl, 'a2');
    expect(other.videoUrl, 'v');
    expect(other.headers, {'User-Agent': 'u'});
    expect(other.startPosition, const Duration(seconds: 5));
    expect(other.audioChoices, hasLength(2));
  });
}
