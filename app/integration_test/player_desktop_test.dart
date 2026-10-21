// Desktop playback check (media_kit). CI runs it on Linux under Xvfb with the fixtures served on 127.0.0.1:8000
// (see .github/workflows/spike-player.yml).
import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _base = String.fromEnvironment('FIXTURES', defaultValue: 'http://127.0.0.1:8000');

Future<T> _within<T>(Future<T> f, String what, [int seconds = 30]) =>
    f.timeout(Duration(seconds: seconds), onTimeout: () => throw StateError('timeout waiting for $what'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('plays merged video + audio, pauses, seeks', (tester) async {
    final engine = await PlayerEngine.create();
    addTearDown(engine.dispose);
    final errors = <String>[];
    engine.error.listen(errors.add);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox.expand(child: engine.view))));

    await tester.runAsync(() async {
      final duration = engine.duration.firstWhere((d) => d > Duration.zero);
      final started = engine.position.firstWhere((p) => p >= const Duration(seconds: 2));
      final sw = Stopwatch()..start();
      await engine.open(const MediaSpec(videoUrl: '$_base/video.mp4', audioUrl: '$_base/audio.m4a'));
      final d = await _within(duration, 'duration');
      await _within(started, 'position >= 2 s');
      // ignore: avoid_print
      print('CHITHRAM_DESKTOP open->2s ${sw.elapsedMilliseconds} ms, duration $d');
      expect(d.inMilliseconds, inInclusiveRange(59000, 61000), reason: 'merged duration');

      final paused = engine.playing.firstWhere((p) => !p);
      await engine.pause();
      await _within(paused, 'paused');
      final resumed = engine.playing.firstWhere((p) => p);
      await engine.play();
      await _within(resumed, 'playing');

      final seeked = engine.position.firstWhere((p) => p >= const Duration(seconds: 30));
      await engine.seek(const Duration(seconds: 30));
      await _within(seeked, 'position >= 30 s after seek');
    });
    expect(errors, isEmpty);
  });

  testWidgets('plays an HLS ladder', (tester) async {
    final engine = await PlayerEngine.create();
    addTearDown(engine.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox.expand(child: engine.view))));
    await tester.runAsync(() async {
      final started = engine.position.firstWhere((p) => p >= const Duration(seconds: 2));
      await engine.open(const MediaSpec(videoUrl: '$_base/hls/master.m3u8'));
      await _within(started, 'HLS position >= 2 s');
    });
  });
}
