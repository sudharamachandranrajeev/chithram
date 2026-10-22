import 'dart:io';

import 'package:chithram/src/core/resume_store_json.dart';
import 'package:chithram_player/src/media_kit_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mpv headers lose Range, any case, and keep the rest', () {
    expect(
      mpvHeaders({'User-Agent': 'ua', 'Range': 'bytes=0-', 'range': 'x', 'Referer': 'r'}),
      {'User-Agent': 'ua', 'Referer': 'r'},
    );
  });

  test('a failed hardware decoder is not a player error', () {
    expect(isFatalMpvError('Could not open codec.'), isFalse);
    expect(isFatalMpvError('Failed to recognize file format.'), isTrue);
  });

  group('JsonResumeStore', () {
    late Directory dir;
    late File file;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('resume');
      file = File('${dir.path}/resume.json');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('keeps positions across loads', () async {
      final a = await JsonResumeStore.load(file);
      await a.put('yt:1', const Duration(seconds: 40), const Duration(minutes: 5));
      final b = await JsonResumeStore.load(file);
      expect(await b.get('yt:1'), const Duration(seconds: 40));
      expect(await b.get('yt:2'), isNull);
    });

    test('forgets watched items (95% or more) and cleared ones', () async {
      final s = await JsonResumeStore.load(file);
      await s.put('a', const Duration(seconds: 40), const Duration(minutes: 5));
      await s.put('a', const Duration(seconds: 290), const Duration(minutes: 5));
      expect(await s.get('a'), isNull);
      await s.put('b', const Duration(seconds: 40), const Duration(minutes: 5));
      await s.clear('b');
      expect(await (await JsonResumeStore.load(file)).get('b'), isNull);
    });

    test('a corrupt file starts empty', () async {
      await file.writeAsString('{not json');
      expect(await (await JsonResumeStore.load(file)).get('a'), isNull);
    });

    test('keeps at most 500 items, dropping the oldest', () async {
      final s = await JsonResumeStore.load(file);
      for (var i = 0; i < JsonResumeStore.maxEntries + 3; i++) {
        await s.put('i$i', const Duration(minutes: 1), const Duration(minutes: 90));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(await s.get('i0'), isNull);
      expect(await s.get('i${JsonResumeStore.maxEntries + 2}'), isNotNull);
    });
  });
}
