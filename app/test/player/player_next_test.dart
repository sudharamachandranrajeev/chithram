import 'dart:convert';

import 'package:chithram/src/core/resume_store.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/player/play_request.dart';
import 'package:chithram/src/player/player_keys.dart';
import 'package:chithram/src/player/player_osd.dart';
import 'package:chithram/src/player/player_route.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart';

import 'fake_engine.dart';

class FakeQueue implements PlayQueue {
  FakeQueue({this.next, this.previous});

  PlayRequest? next;
  PlayRequest? previous;
  @override
  bool autoplay = true;
  int prepared = 0, taken = 0, wentBack = 0;

  @override
  Future<PlayRequest?> prepareNext() async {
    prepared++;
    return next;
  }

  @override
  PlayRequest? takeNext() {
    taken++;
    return next;
  }

  @override
  bool get hasPrevious => previous != null;

  @override
  PlayRequest? takePrevious() {
    wentBack++;
    return previous;
  }
}

PlayRequest _req(
  String id, {
  PlayQueue? queue,
  bool live = false,
  Future<PlayExtras> Function(Duration)? extras,
  void Function(Duration, Duration)? onWatched,
}) => PlayRequest(
  itemId: id,
  title: 'Title $id',
  subtitle: 'Channel of $id',
  isLive: live,
  queue: queue,
  extras: extras,
  onWatched: onWatched,
  resolve: () async => MediaSpec(videoUrl: 'http://x/$id.mp4', isLive: live),
);

// A 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<FakeEngine> _open(WidgetTester t, PlayRequest request) async {
  final engine = FakeEngine();
  await t.pumpWidget(
    AppServicesScope(
      services: AppServices.memory(resume: MemoryResumeStore()),
      child: MaterialApp(
        home: PlayerRoute(
          request: request,
          engineFactory: () async => engine,
          sheetProvider: (_, _) => MemoryImage(_png),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
  return engine;
}

Future<void> _length(
  WidgetTester t,
  FakeEngine e,
  Duration d, [
  Duration at = Duration.zero,
]) async {
  e.durationC.add(d);
  e.positionC.add(at);
  await t.pump();
  await t.pump();
}

void main() {
  group('seek bar', () {
    testWidgets('chapters, heatmap and preview frame while scrubbing', (
      t,
    ) async {
      final storyboard = parseStoryboardSpec(
        r'https://i.ytimg.com/sb/A/storyboard3_L$L/$N.jpg?sqp=x|160#90#25#5#5#5000#M$M#rs$S',
      );
      final e = await _open(
        t,
        _req(
          'yt:a',
          extras: (d) async => PlayExtras(
            chapters: const [
              Chapter(Duration.zero, 'Intro'),
              Chapter(Duration(minutes: 1), 'Main part'),
            ],
            heatmap: const [
              HeatBin(Duration.zero, Duration(seconds: 30), 0.2),
              HeatBin(Duration(seconds: 30), Duration(seconds: 30), 1),
            ],
            segments: const [
              SponsorSegment(
                category: 'sponsor',
                actionType: 'skip',
                start: Duration(seconds: 70),
                end: Duration(seconds: 80),
              ),
            ],
            storyboard: storyboard,
          ),
        ),
      );
      expect(find.byKey(PlayerKeys.heatmap), findsNothing);
      await _length(
        t,
        e,
        const Duration(minutes: 3),
        const Duration(seconds: 55),
      );
      await t.pump();
      expect(find.byKey(PlayerKeys.heatmap), findsOneWidget);
      expect(
        find.byKey(PlayerKeys.bubbleTime),
        findsNothing,
        reason: 'no bubble until scrubbing',
      );
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(t.widget<Text>(find.byKey(PlayerKeys.bubbleTime)).data, '1:05');
      expect(
        t.widget<Text>(find.byKey(PlayerKeys.bubbleChapter)).data,
        'Main part',
      );
      expect(find.byKey(PlayerKeys.previewThumb), findsOneWidget);
      // Total and remaining time.
      expect(t.widget<Text>(find.byKey(PlayerKeys.duration)).data, ' / 3:00');
      expect(t.widget<Text>(find.byKey(PlayerKeys.remaining)).data, '-1:55');
      await t.pump(const Duration(seconds: 2));
      expect(e.seeks, [const Duration(seconds: 65)]);
      expect(find.byKey(PlayerKeys.bubbleTime), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('no storyboard, no thumbnail; OK commits at once', (t) async {
      final e = await _open(t, _req('yt:a'));
      await _length(
        t,
        e,
        const Duration(minutes: 3),
        const Duration(seconds: 55),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect(find.byKey(PlayerKeys.previewThumb), findsNothing);
      expect(find.byKey(PlayerKeys.bubbleChapter), findsNothing);
      expect(find.byKey(PlayerKeys.heatmap), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pump();
      expect(e.seeks, [const Duration(seconds: 45)]);
      expect(
        e.isPlaying,
        isTrue,
        reason: 'OK while scrubbing seeks, it does not pause',
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Back cancels the scrub and stays in the player', (t) async {
      final e = await _open(t, _req('yt:a'));
      await _length(
        t,
        e,
        const Duration(minutes: 3),
        const Duration(seconds: 55),
      );
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(t.widget<Text>(find.byKey(Keys.playerPosition)).data, '1:05');
      await t.binding.handlePopRoute();
      await t.pump();
      expect(t.widget<Text>(find.byKey(Keys.playerPosition)).data, '0:55');
      await t.pump(const Duration(seconds: 3));
      expect(e.seeks, isEmpty);
      expect(e.disposed, isFalse);
      expect(find.byKey(Keys.playerRoot), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets(
      'live: a pill, no bar; with a DVR window the bar and a jump to the edge',
      (t) async {
        final e = await _open(t, _req('iptv:a', live: true));
        await _length(t, e, Duration.zero);
        expect(find.byKey(PlayerKeys.livePill), findsOneWidget);
        expect(find.byKey(PlayerKeys.seekBar), findsNothing);
        await t.pumpWidget(const SizedBox());

        final dvr = await _open(t, _req('iptv:b', live: true));
        await _length(
          t,
          dvr,
          const Duration(minutes: 10),
          const Duration(minutes: 4),
        );
        expect(find.byKey(PlayerKeys.seekBar), findsOneWidget);
        await t.tap(find.byKey(PlayerKeys.livePill));
        await t.pump();
        expect(dvr.seeks, [const Duration(minutes: 10)]);
        // Scrubbing to within ten seconds of the end snaps to the edge.
        dvr.positionC.add(const Duration(minutes: 9, seconds: 40));
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump(const Duration(seconds: 2));
        expect(dvr.seeks.last, const Duration(minutes: 10));
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets('mouse: hover shows the bubble, a click seeks', (t) async {
      final e = await _open(t, _req('yt:a'));
      await _length(
        t,
        e,
        const Duration(minutes: 4),
        const Duration(seconds: 10),
      );
      final bar = find.byKey(PlayerKeys.seekBar);
      final box = t.getRect(bar);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(Offset(box.left + box.width / 2, box.center.dy));
      await t.pump();
      expect(t.widget<Text>(find.byKey(PlayerKeys.bubbleTime)).data, '2:00');
      await mouse.moveTo(Offset.zero);
      await t.pump();
      expect(find.byKey(PlayerKeys.bubbleTime), findsNothing);
      await t.tapAt(Offset(box.left + box.width * 0.25, box.center.dy));
      await t.pump();
      expect(e.seeks.single.inSeconds, inInclusiveRange(59, 61));
      await mouse.removePointer();
      await t.pumpWidget(const SizedBox());
    });

    testWidgets(
      'phone: tap shows and hides, double tap seeks 10 s a side, drag scrubs',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(420, 800);
        addTearDown(t.view.reset);
        final e = await _open(t, _req('yt:a'));
        await _length(
          t,
          e,
          const Duration(minutes: 4),
          const Duration(minutes: 1),
        );
        double opacity() => t
            .widget<AnimatedOpacity>(
              find
                  .descendant(
                    of: find.byType(PlayerOsd),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity;
        expect(opacity(), 1);
        await t.tapAt(const Offset(210, 300));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 300));
        expect(opacity(), 0, reason: 'a tap hides the controls');
        expect(e.isPlaying, isTrue, reason: 'and does not pause');
        await t.tapAt(const Offset(210, 300));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 300));
        expect(opacity(), 1);

        await t.tapAt(const Offset(380, 300));
        await t.pump(const Duration(milliseconds: 60));
        await t.tapAt(const Offset(380, 300));
        await t.pump(const Duration(milliseconds: 100));
        expect(e.seeks, [const Duration(minutes: 1, seconds: 10)]);
        await t.pump(const Duration(seconds: 1));
        await t.tapAt(const Offset(20, 300));
        await t.pump(const Duration(milliseconds: 60));
        await t.tapAt(const Offset(20, 300));
        await t.pump(const Duration(milliseconds: 100));
        expect(
          e.seeks.last,
          const Duration(seconds: 70) -
              const Duration(seconds: 10) +
              Duration.zero,
          reason: 'position still reads 1:10 after the first; minus ten',
        );
        await t.pump(const Duration(seconds: 2));

        final bar = t.getRect(find.byKey(PlayerKeys.seekBar));
        final drag = await t.startGesture(
          Offset(bar.left + bar.width * 0.25, bar.center.dy),
        );
        await drag.moveTo(Offset(bar.left + bar.width * 0.5, bar.center.dy));
        await t.pump();
        expect(t.widget<Text>(find.byKey(PlayerKeys.bubbleTime)).data, '2:00');
        final before = e.seeks.length;
        await drag.up();
        await t.pump();
        expect(e.seeks.length, before + 1);
        expect(e.seeks.last, const Duration(minutes: 2));
        await t.pump(const Duration(seconds: 5));
        await t.pumpWidget(const SizedBox());
      },
    );
  });

  group('up next', () {
    testWidgets(
      'prefetches 30 s before the end, counts down, plays the next one',
      (t) async {
        final watched = <(Duration, Duration)>[];
        final queue = FakeQueue(next: _req('yt:next'));
        final e = await _open(
          t,
          _req('yt:a', queue: queue, onWatched: (p, d) => watched.add((p, d))),
        );
        await _length(
          t,
          e,
          const Duration(minutes: 2),
          const Duration(seconds: 10),
        );
        expect(queue.prepared, 0);
        e.positionC.add(const Duration(seconds: 91));
        await t.pump();
        expect(queue.prepared, 1);
        e.positionC.add(const Duration(seconds: 100));
        await t.pump();
        expect(queue.prepared, 1, reason: 'once per video');
        expect(find.byKey(PlayerKeys.upNext), findsNothing);

        e.positionC.add(const Duration(minutes: 2));
        e.completedC.add(true);
        await t.pump();
        await t.pump();
        expect(find.byKey(PlayerKeys.upNext), findsOneWidget);
        expect(
          t.widget<Text>(find.byKey(PlayerKeys.upNextTitle)).data,
          'Title yt:next',
        );
        expect(find.text('Channel of yt:next'), findsOneWidget);
        expect(t.widget<Text>(find.byKey(PlayerKeys.upNextCount)).data, '8');
        await t.pump(const Duration(seconds: 3));
        expect(t.widget<Text>(find.byKey(PlayerKeys.upNextCount)).data, '5');
        expect(e.opened, hasLength(1));

        await t.pump(const Duration(seconds: 6));
        await t.pump();
        await t.pump();
        expect(queue.taken, 1);
        expect(e.opened.last.videoUrl, 'http://x/yt:next.mp4');
        expect(find.byKey(PlayerKeys.upNext), findsNothing);
        expect(watched, [
          (const Duration(minutes: 2), const Duration(minutes: 2)),
        ], reason: 'the ended video is reported');
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets('Play now skips the countdown', (t) async {
      final queue = FakeQueue(next: _req('yt:next'));
      final e = await _open(t, _req('yt:a', queue: queue));
      await _length(
        t,
        e,
        const Duration(minutes: 2),
        const Duration(minutes: 2),
      );
      e.completedC.add(true);
      await t.pump();
      await t.pump();
      await t.tap(find.byKey(PlayerKeys.upNextPlay));
      await t.pump();
      await t.pump();
      expect(e.opened.last.videoUrl, 'http://x/yt:next.mp4');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Cancel stays on the ended video and plays nothing', (t) async {
      final queue = FakeQueue(next: _req('yt:next'));
      final e = await _open(t, _req('yt:a', queue: queue));
      await _length(
        t,
        e,
        const Duration(minutes: 2),
        const Duration(minutes: 2),
      );
      e.completedC.add(true);
      await t.pump();
      await t.pump();
      await t.tap(find.byKey(PlayerKeys.upNextCancel));
      await t.pump();
      expect(find.byKey(PlayerKeys.upNext), findsNothing);
      await t.pump(const Duration(seconds: 12));
      expect(e.opened, hasLength(1));
      expect(queue.taken, 0);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Back cancels the countdown first, the next Back would close', (
      t,
    ) async {
      final queue = FakeQueue(next: _req('yt:next'));
      final e = await _open(t, _req('yt:a', queue: queue));
      await _length(
        t,
        e,
        const Duration(minutes: 2),
        const Duration(minutes: 2),
      );
      e.completedC.add(true);
      await t.pump();
      await t.pump();
      expect(find.byKey(PlayerKeys.upNext), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byKey(PlayerKeys.upNext), findsNothing);
      expect(find.byKey(Keys.playerRoot), findsOneWidget);
      await t.pump(const Duration(seconds: 12));
      expect(e.opened, hasLength(1));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the setting off: no prefetch, no card', (t) async {
      final queue = FakeQueue(next: _req('yt:next'))..autoplay = false;
      final e = await _open(t, _req('yt:a', queue: queue));
      await _length(
        t,
        e,
        const Duration(minutes: 2),
        const Duration(seconds: 100),
      );
      e.completedC.add(true);
      await t.pump();
      await t.pump();
      expect(queue.prepared, 0);
      expect(find.byKey(PlayerKeys.upNext), findsNothing);
      expect(queue.taken, 0);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('live streams never get an Up next', (t) async {
      final queue = FakeQueue(next: _req('yt:next'));
      final e = await _open(t, _req('yt:live', queue: queue, live: true));
      await _length(
        t,
        e,
        const Duration(minutes: 20),
        const Duration(minutes: 19, seconds: 50),
      );
      e.completedC.add(true);
      await t.pump();
      await t.pump();
      expect(queue.prepared, 0);
      expect(find.byKey(PlayerKeys.upNext), findsNothing);
      expect(find.byKey(PlayerKeys.next), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('nothing to play next: no card', (t) async {
      final queue = FakeQueue();
      final e = await _open(t, _req('yt:a', queue: queue));
      await _length(
        t,
        e,
        const Duration(minutes: 2),
        const Duration(minutes: 2),
      );
      e.completedC.add(true);
      await t.pump();
      await t.pump();
      expect(find.byKey(PlayerKeys.upNext), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Previous goes back; Next skips ahead', (t) async {
      final queue = FakeQueue();
      queue.next = _req('yt:next', queue: queue);
      queue.previous = _req('yt:prev', queue: queue);
      final e = await _open(t, _req('yt:a', queue: queue));
      await _length(
        t,
        e,
        const Duration(minutes: 2),
        const Duration(seconds: 20),
      );
      await t.tap(find.byKey(PlayerKeys.previous));
      await t.pump();
      await t.pump();
      expect(queue.wentBack, 1);
      expect(e.opened.last.videoUrl, 'http://x/yt:prev.mp4');
      await t.tap(find.byKey(PlayerKeys.next));
      await t.pump();
      await t.pump();
      await t.pump();
      expect(e.opened.last.videoUrl, 'http://x/yt:next.mp4');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('no Previous button on the first video', (t) async {
      final queue = FakeQueue(next: _req('yt:next'));
      await _open(t, _req('yt:a', queue: queue));
      expect(find.byKey(PlayerKeys.previous), findsNothing);
      expect(find.byKey(PlayerKeys.next), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });
}
