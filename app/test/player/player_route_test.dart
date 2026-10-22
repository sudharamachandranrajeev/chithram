import 'package:chithram/src/core/resume_store.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/player/play_request.dart';
import 'package:chithram/src/player/player_keys.dart';
import 'package:chithram/src/player/player_route.dart';
import 'package:chithram/src/ui/keys.dart';
import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_engine.dart';

PlayRequest _request({
  String id = 'url:a',
  bool live = false,
  ZapList? zap,
  Future<MediaSpec> Function()? resolve,
  Future<void> Function()? onClose,
}) =>
    PlayRequest(
      itemId: id,
      title: 'Title $id',
      isLive: live,
      zap: zap,
      onClose: onClose,
      resolve: resolve ?? () async => MediaSpec(videoUrl: 'http://x/$id.mp4', isLive: live),
    );

class _Zap implements ZapList {
  @override
  int get length => 3;
  @override
  int get initialIndex => 0;
  @override
  String titleAt(int i) => 'Channel $i';
  @override
  PlayRequest requestAt(int i) => _request(id: 'iptv:$i', live: true);
}

Future<(FakeEngine, MemoryResumeStore)> _open(
  WidgetTester t,
  PlayRequest request, {
  MemoryResumeStore? resume,
}) async {
  final engine = FakeEngine();
  final store = resume ?? MemoryResumeStore();
  final services = AppServices.memory(resume: store);
  await t.pumpWidget(AppServicesScope(
    services: services,
    child: MaterialApp(home: PlayerRoute(request: request, engineFactory: () async => engine)),
  ));
  await t.pump();
  await t.pump();
  return (engine, store);
}

void main() {
  testWidgets('opens the resolved media and toggles on Select', (t) async {
    final (engine, _) = await _open(t, _request());
    expect(engine.opened.single.videoUrl, 'http://x/url:a.mp4');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    expect(engine.isPlaying, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    expect(engine.isPlaying, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Right and Left seek by ten seconds on VOD, not on live', (t) async {
    final (engine, _) = await _open(t, _request());
    engine.durationC.add(const Duration(minutes: 5));
    engine.positionC.add(const Duration(seconds: 30));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(engine.seeks, [const Duration(seconds: 40), const Duration(seconds: 30)]);
    await t.pumpWidget(const SizedBox());

    final (live, _) = await _open(t, _request(live: true));
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(live.seeks, isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Up and Down zap, wrap around, and close the channel left', (t) async {
    final closed = <String>[];
    final zap = _Zap();
    final first = zap.requestAt(0);
    final request = PlayRequest(
      itemId: first.itemId,
      title: first.title,
      isLive: true,
      zap: zap,
      onClose: () async => closed.add(first.itemId),
      resolve: first.resolve,
    );
    final (engine, _) = await _open(t, request);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    await t.pump();
    expect(engine.opened.last.videoUrl, 'http://x/iptv:1.mp4');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    await t.pump();
    expect(engine.opened.last.videoUrl, 'http://x/iptv:2.mp4');
    expect(closed, ['iptv:0']);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('offers Resume over 30 s and starts there', (t) async {
    final store = MemoryResumeStore();
    await store.put('url:a', const Duration(seconds: 40), const Duration(minutes: 5));
    final (engine, _) = await _open(t, _request(), resume: store);
    expect(find.byKey(PlayerKeys.resume), findsOneWidget);
    expect(find.text('Resume from 0:40'), findsOneWidget);
    expect(engine.opened, isEmpty, reason: 'nothing plays before the choice');
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    await t.pump();
    expect(engine.opened.single.startPosition, const Duration(seconds: 40));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Start over forgets the position; short positions and live are not offered', (t) async {
    final store = MemoryResumeStore();
    await store.put('url:a', const Duration(seconds: 40), const Duration(minutes: 5));
    final (engine, _) = await _open(t, _request(), resume: store);
    // The buttons wrap to two rows in the default 800x600 test window.
    await t.tap(find.byKey(PlayerKeys.startOver));
    await t.pump();
    await t.pump();
    expect(engine.opened.single.startPosition, Duration.zero);
    expect(await store.get('url:a'), isNull);
    await t.pumpWidget(const SizedBox());

    final short = MemoryResumeStore();
    await short.put('url:a', const Duration(seconds: 20), const Duration(minutes: 5));
    await short.put('url:b', const Duration(minutes: 3), const Duration(minutes: 5));
    final (e2, _) = await _open(t, _request(), resume: short);
    expect(find.byKey(PlayerKeys.resume), findsNothing);
    expect(e2.opened, hasLength(1));
    await t.pumpWidget(const SizedBox());
    final (e3, _) = await _open(t, _request(id: 'url:b', live: true), resume: short);
    expect(find.byKey(PlayerKeys.resume), findsNothing);
    expect(e3.opened, hasLength(1));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('saves the position on close', (t) async {
    final (engine, store) = await _open(t, _request());
    engine.durationC.add(const Duration(minutes: 5));
    engine.positionC.add(const Duration(seconds: 42));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(await store.get('url:a'), const Duration(seconds: 42));
    expect(engine.disposed, isTrue);
  });

  testWidgets('a resolve failure shows the error panel; Retry resolves again', (t) async {
    var calls = 0;
    final (engine, _) = await _open(
      t,
      _request(resolve: () async {
        calls++;
        if (calls == 1) throw StateError('HTTP 404 for http://host/secret?token=1');
        return const MediaSpec(videoUrl: 'http://x/ok.mp4');
      }),
    );
    final text = t.widget<Text>(find.byKey(Keys.playerError)).data!;
    expect(text, contains('404'));
    expect(text, isNot(contains('token')));
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    await t.pump();
    expect(calls, 2);
    expect(engine.opened.single.videoUrl, 'http://x/ok.mp4');
    expect(find.byKey(Keys.playerError), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('an engine error shows the panel with a DRM message', (t) async {
    final (engine, _) = await _open(t, _request());
    engine.errorC.add('ERROR_CODE_DRM_PROVISIONING_FAILED: nope');
    await t.pump();
    expect(t.widget<Text>(find.byKey(Keys.playerError)).data, contains('DRM'));
    expect(find.byKey(PlayerKeys.back), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  test('time and error text', () {
    expect(formatPlayerTime(const Duration(seconds: 5)), '0:05');
    expect(formatPlayerTime(const Duration(minutes: 61, seconds: 1)), '1:01:01');
    expect(describePlayerError('see http://a.b/c?d=1'), 'see http://a.b');
  });
}
