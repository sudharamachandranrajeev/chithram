import 'package:chithram/src/intake/intake.dart';
import 'package:flutter_test/flutter_test.dart';

const _hex = '0123456789abcdef0123456789abcdef01234567';
const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

void main() {
  final cases = <(String, IntakeKind)>[
    // YouTube
    ('https://www.youtube.com/watch?v=dQw4w9WgXcQ', IntakeKind.youtube),
    ('https://youtube.com/watch?v=dQw4w9WgXcQ&t=10', IntakeKind.youtube),
    ('https://m.youtube.com/watch?v=dQw4w9WgXcQ', IntakeKind.youtube),
    ('https://music.youtube.com/watch?v=dQw4w9WgXcQ', IntakeKind.youtube),
    ('https://youtu.be/dQw4w9WgXcQ', IntakeKind.youtube),
    ('https://youtu.be/dQw4w9WgXcQ?si=abc', IntakeKind.youtube),
    ('https://www.youtube.com/shorts/abcdefghijk', IntakeKind.youtube),
    ('https://www.youtube.com/live/abcdefghijk', IntakeKind.youtube),
    ('  https://youtu.be/dQw4w9WgXcQ\n', IntakeKind.youtube),
    ('HTTPS://WWW.YOUTUBE.COM/watch?v=dQw4w9WgXcQ', IntakeKind.youtube),
    ('https://www.youtube.com/', IntakeKind.text),
    ('https://www.youtube.com/watch', IntakeKind.text),
    ('https://www.youtube.com/@somechannel', IntakeKind.text),
    ('https://youtu.be/', IntakeKind.text),
    ('https://notyoutube.com/watch?v=dQw4w9WgXcQ', IntakeKind.text),
    ('https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ', IntakeKind.text),
    // Magnets
    ('magnet:?xt=urn:btih:$_hex', IntakeKind.magnet),
    ('magnet:?xt=urn:btih:${_hex.toUpperCase()}&dn=Movie&tr=udp%3A%2F%2Ftracker.example%3A80', IntakeKind.magnet),
    ('magnet:?dn=x&xt=urn:btih:$_b32', IntakeKind.magnet),
    ('MAGNET:?xt=urn:btih:$_hex', IntakeKind.magnet),
    ('magnet:?xt=urn:btih:abc', IntakeKind.text),
    ('magnet:?xt=urn:sha1:$_hex', IntakeKind.text),
    ('magnet:?dn=only-a-name', IntakeKind.text),
    // Torrent files, playlists, media
    ('https://example.org/files/film.torrent', IntakeKind.torrentUrl),
    ('http://example.org/film.TORRENT?x=1', IntakeKind.torrentUrl),
    ('https://example.org/list.m3u', IntakeKind.playlistUrl),
    ('https://example.org/get.php?username=u&password=p&type=m3u_plus&output=ts', IntakeKind.playlistUrl),
    ('https://example.org/get.php?username=u&password=p&type=m3u', IntakeKind.playlistUrl),
    ('https://example.org/get.php?type=xml', IntakeKind.text),
    ('https://example.org/live/stream.m3u8', IntakeKind.ambiguousM3u8),
    ('https://example.org/video.mp4', IntakeKind.mediaUrl),
    ('https://example.org/video.MKV?token=1', IntakeKind.mediaUrl),
    ('https://example.org/manifest.mpd', IntakeKind.mediaUrl),
    ('https://example.org/song.flac', IntakeKind.mediaUrl),
    ('http://192.168.1.10:8096/movie.webm', IntakeKind.mediaUrl),
    ('https://example.org/page.html', IntakeKind.text),
    ('https://example.org/', IntakeKind.text),
    ('https://example.org', IntakeKind.text),
    // Never opened: code, local files, intents
    ('javascript:alert(1)', IntakeKind.text),
    ('JavaScript:alert(document.cookie)', IntakeKind.text),
    ('file:///etc/passwd', IntakeKind.text),
    ('file:///sdcard/video.mp4', IntakeKind.text),
    ('content://media/external/video/1.mp4', IntakeKind.text),
    ('intent://scan/#Intent;scheme=zxing;end', IntakeKind.text),
    ('intent:#Intent;action=android.intent.action.VIEW;end', IntakeKind.text),
    ('data:text/html;base64,PHNjcmlwdD4=', IntakeKind.text),
    ('vbscript:msgbox(1)', IntakeKind.text),
    ('ftp://example.org/video.mp4', IntakeKind.text),
    ('smb://nas/video.mp4', IntakeKind.text),
    ('//example.org/video.mp4', IntakeKind.text),
    ('https:///video.mp4', IntakeKind.text),
    // Plain text
    ('', IntakeKind.text),
    ('   ', IntakeKind.text),
    ('hello', IntakeKind.text),
    ('watch https://youtu.be/dQw4w9WgXcQ', IntakeKind.text),
    ('https://example.org/a.mp4 https://example.org/b.mp4', IntakeKind.text),
    ('https://example.org/a.mp4\nhttps://example.org/b.mp4', IntakeKind.text),
  ];

  test('has at least 30 cases', () => expect(cases.length, greaterThanOrEqualTo(30)));

  for (final (text, kind) in cases) {
    test('${text.replaceAll('\n', r'\n')} is ${kind.name}', () => expect(classify(text), kind));
  }

  test('every kind has a button label except plain text without a search hook', () {
    IntakeHooks.search = null;
    expect(intakeActionLabel(IntakeKind.youtube), 'Play YouTube video');
    expect(intakeActionLabel(IntakeKind.magnet), 'Open torrent');
    expect(intakeActionLabel(IntakeKind.torrentUrl), 'Open torrent');
    expect(intakeActionLabel(IntakeKind.playlistUrl), 'Add playlist');
    expect(intakeActionLabel(IntakeKind.mediaUrl), 'Play link');
    expect(intakeActionLabel(IntakeKind.ambiguousM3u8), 'Play link');
    expect(intakeActionLabel(IntakeKind.text), isNull);
    IntakeHooks.search = (_, _) async {};
    expect(intakeActionLabel(IntakeKind.text), 'Search for this text');
    IntakeHooks.search = null;
  });
}
