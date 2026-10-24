import 'dart:ui';

import 'package:chithram/src/player/seek/scrub.dart';
import 'package:chithram/src/player/seek/seek_bar.dart';
import 'package:chithram/src/player/seek/storyboard_thumb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart';

const _len = Duration(minutes: 30);

Duration _ms(int ms) => Duration(milliseconds: ms);

void main() {
  test('scrubStep grows with the hold time and is capped on short videos', () {
    expect(scrubStep(Duration.zero), const Duration(seconds: 10));
    expect(scrubStep(_ms(799)), const Duration(seconds: 10));
    expect(scrubStep(_ms(800)), const Duration(seconds: 30));
    expect(scrubStep(_ms(1700)), const Duration(minutes: 1));
    expect(scrubStep(_ms(5000)), const Duration(minutes: 2));
    // A 2-minute clip never jumps more than a tenth of itself (5 s at least).
    expect(
      scrubStep(_ms(5000), length: const Duration(minutes: 2)),
      const Duration(seconds: 12),
    );
    expect(
      scrubStep(Duration.zero, length: const Duration(seconds: 20)),
      const Duration(seconds: 5),
    );
  });

  testWidgets('taps step 10 s each, a pause commits once', (t) async {
    final commits = <Duration>[];
    final s = Scrubber(onCommit: commits.add);
    s.key(
      1,
      repeat: false,
      now: Duration.zero,
      position: const Duration(minutes: 1),
      length: _len,
    );
    s.keyUp();
    s.key(
      1,
      repeat: false,
      now: _ms(300),
      position: const Duration(minutes: 1),
      length: _len,
    );
    expect(
      s.preview,
      const Duration(seconds: 80),
      reason: 'from the preview, not the position',
    );
    await t.pump(const Duration(seconds: 2));
    expect(commits, [const Duration(seconds: 80)]);
    expect(s.active, isFalse);
    s.dispose();
  });

  testWidgets('holding a key accelerates, at a limited rate', (t) async {
    final s = Scrubber(onCommit: (_) {});
    const start = Duration(minutes: 5);
    s.key(
      1,
      repeat: false,
      now: Duration.zero,
      position: start,
      length: const Duration(hours: 3),
    );
    expect(s.preview, start + const Duration(seconds: 10));
    // Repeats faster than the step rate are ignored.
    s.key(
      1,
      repeat: true,
      now: _ms(50),
      position: start,
      length: const Duration(hours: 3),
    );
    expect(s.preview, start + const Duration(seconds: 10));
    var now = 0;
    final seen = <int>[];
    var last = s.preview!;
    while (now < 4000) {
      now += 150;
      s.key(
        1,
        repeat: true,
        now: _ms(now),
        position: start,
        length: const Duration(hours: 3),
      );
      seen.add((s.preview! - last).inSeconds);
      last = s.preview!;
    }
    expect(seen.first, 10);
    expect(seen.last, 120);
    expect(seen, containsAllInOrder([10, 30, 60, 120]));
    s.dispose();
  });

  testWidgets('direction change starts slow again; clamps to the ends', (
    t,
  ) async {
    final s = Scrubber(onCommit: (_) {});
    s.key(
      1,
      repeat: false,
      now: Duration.zero,
      position: const Duration(minutes: 5),
      length: _len,
    );
    for (var i = 1; i < 30; i++) {
      s.key(
        1,
        repeat: true,
        now: _ms(i * 150),
        position: Duration.zero,
        length: _len,
      );
    }
    final before = s.preview!;
    s.key(
      -1,
      repeat: true,
      now: _ms(5000),
      position: Duration.zero,
      length: _len,
    );
    expect(before - s.preview!, const Duration(seconds: 10));
    s.key(
      -1,
      repeat: false,
      now: _ms(6000),
      position: Duration.zero,
      length: _len,
    );
    for (var i = 0; i < 200; i++) {
      s.key(
        -1,
        repeat: true,
        now: _ms(6000 + i * 150),
        position: Duration.zero,
        length: _len,
      );
    }
    expect(s.preview, Duration.zero);
    s.cancel();
    s.dispose();
  });

  testWidgets(
    'cancel drops the preview without seeking; commit with none does nothing',
    (t) async {
      final commits = <Duration>[];
      final s = Scrubber(onCommit: commits.add);
      s.commit();
      s.key(
        -1,
        repeat: false,
        now: Duration.zero,
        position: const Duration(minutes: 2),
        length: _len,
      );
      expect(s.active, isTrue);
      s.cancel();
      expect(s.active, isFalse);
      await t.pump(const Duration(seconds: 3));
      expect(commits, isEmpty);
      s.dispose();
    },
  );

  testWidgets('a drag commits at its end only, never on the idle timer', (
    t,
  ) async {
    final commits = <Duration>[];
    final s = Scrubber(onCommit: commits.add);
    s.drag(const Duration(minutes: 3), _len);
    await t.pump(const Duration(seconds: 5));
    expect(commits, isEmpty);
    s.drag(const Duration(minutes: 40), _len);
    expect(s.preview, _len, reason: 'clamped');
    s.dragEnd();
    expect(commits, [_len]);
    s.dispose();
  });

  test('chapterAt and chapter spans', () {
    const chapters = [
      Chapter(Duration.zero, 'A'),
      Chapter(Duration(seconds: 60), 'B'),
      Chapter(Duration(seconds: 90), 'C'),
    ];
    expect(chapterAt(chapters, const Duration(seconds: 59))!.title, 'A');
    expect(chapterAt(chapters, const Duration(seconds: 60))!.title, 'B');
    expect(chapterAt(chapters, const Duration(minutes: 9))!.title, 'C');
    expect(chapterAt(const [], Duration.zero), isNull);
    final spans = chapterSpans(chapters, const Duration(seconds: 120), 1200);
    expect(spans.length, 3);
    expect(spans[0], (0.0, 599.0));
    expect(spans[1], (601.0, 899.0));
    expect(spans[2], (901.0, 1200.0));
    expect(chapterSpans(const [], Duration.zero, 100), [(0.0, 100.0)]);
  });

  test('sponsor colours', () {
    expect(sponsorColor('sponsor'), const Color(0xFF00D400));
    expect(sponsorColor('nope'), const Color(0xFFB0B0B0));
  });

  test('storyboard crop rect follows the decoded size', () {
    final level = parseStoryboardSpec(
      r'https://i.ytimg.com/sb/A/storyboard3_L$L/$N.jpg?sqp=x|160#90#25#5#5#5000#M$M#rs$S',
    )[0];
    final frame = level.frameAt(const Duration(seconds: 37)); // col 2, row 1
    expect(
      storyboardSource(level, frame, const Size(800, 450)),
      const Rect.fromLTWH(320, 90, 160, 90),
    );
    // Decoded at half size: same cell, scaled.
    expect(
      storyboardSource(level, frame, const Size(400, 225)),
      const Rect.fromLTWH(160, 45, 80, 45),
    );
    expect(sheetDecodeWidth(level, 240, 1), 800, reason: 'never above native');
    expect(sheetDecodeWidth(level, 80, 1), 400);
  });
}
