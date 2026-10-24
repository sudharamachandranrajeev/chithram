import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/resume_store.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/player/play_request.dart';
import 'package:chithram/src/player/player_keys.dart';
import 'package:chithram/src/player/player_osd.dart';
import 'package:chithram/src/player/player_route.dart';
import 'package:chithram/src/player/tracks.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_engine.dart';

PlayRequest _request({MediaSpec? spec, String id = 'url:a'}) => PlayRequest(
  itemId: id,
  title: 'Title $id',
  resolve: () async => spec ?? MediaSpec(videoUrl: 'http://x/$id.mkv'),
);

const _tracks = MediaTracks(
  audio: [
    MediaTrack(
      id: '1:0',
      language: 'ml',
      codec: 'aac',
      channels: 6,
      selected: true,
      isDefault: true,
    ),
    MediaTrack(
      id: '2:0',
      language: 'ta',
      label: 'Theatre dub',
      codec: 'ac3',
      channels: 2,
    ),
  ],
  subtitles: [
    MediaTrack(id: '3:0', language: 'en', codec: 'srt'),
    MediaTrack(id: '3:1', language: 'ml', codec: 'ssa'),
  ],
);

Future<FakeEngine> _open(
  WidgetTester t,
  PlayRequest request, {
  Prefs? prefs,
  FormFactor form = FormFactor.tv,
}) async {
  final engine = FakeEngine();
  await t.pumpWidget(
    AppServicesScope(
      services: AppServices.memory(
        resume: MemoryResumeStore(),
        prefs: prefs ?? Prefs.memory(),
      ),
      child: FormScope(
        form: form,
        child: MaterialApp(
          home: PlayerRoute(
            request: request,
            engineFactory: () async => engine,
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
  return engine;
}

double _opacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(
      find
          .descendant(
            of: find.byType(PlayerOsd),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

String _position(WidgetTester t) =>
    t.widget<Text>(find.byKey(Keys.playerPosition)).data!;

/// True when focus is on the widget with [key] or inside it.
bool _focused(Key key) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var found = context.widget.key == key;
  context.visitAncestorElements((e) {
    if (e.widget.key == key) found = true;
    return !found;
  });
  return found;
}

Future<void> _key(WidgetTester t, LogicalKeyboardKey key) async {
  await t.sendKeyEvent(key);
  await t.pump();
}

Future<void> _closeRoute(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  group('display auto-hide', () {
    testWidgets('fades after 4 s of playback, slowly; stays while paused', (
      t,
    ) async {
      final engine = await _open(t, _request());
      expect(_opacity(t), 1);
      await t.pump(const Duration(seconds: 3));
      expect(_opacity(t), 1);
      await t.pump(const Duration(milliseconds: 1100));
      expect(_opacity(t), 0);
      final fade = t.widget<AnimatedOpacity>(
        find
            .descendant(
              of: find.byType(PlayerOsd),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      );
      expect(fade.duration, osdFadeOut);

      // Play/pause acts at once, even with the display hidden.
      await _key(t, LogicalKeyboardKey.mediaPlayPause);
      expect(engine.isPlaying, isFalse);
      expect(_opacity(t), 1);
      await t.pump(const Duration(seconds: 10));
      expect(_opacity(t), 1, reason: 'a paused video keeps its display');
      await _closeRoute(t);
    });

    testWidgets('the engine repeating "playing" does not keep it up', (
      t,
    ) async {
      final engine = await _open(t, _request());
      // Media3 sends its state four times a second.
      for (var i = 0; i < 20; i++) {
        engine.playingC.add(true);
        await t.pump(const Duration(milliseconds: 250));
      }
      expect(_opacity(t), 0);
      await _closeRoute(t);
    });

    testWidgets('the key that wakes it does nothing else', (t) async {
      final engine = await _open(t, _request());
      engine.durationC.add(const Duration(minutes: 5));
      engine.positionC.add(const Duration(seconds: 30));
      await t.pump();
      await t.pump(osdHideAfter + const Duration(seconds: 1));
      expect(_opacity(t), 0);

      await _key(t, LogicalKeyboardKey.arrowRight);
      expect(_opacity(t), 1);
      expect(_position(t), '0:30', reason: 'the waking Right does not scrub');
      // Now Right scrubs.
      await _key(t, LogicalKeyboardKey.arrowRight);
      expect(_position(t), '0:40');
      await t.pump(const Duration(seconds: 2));
      expect(engine.seeks, [const Duration(seconds: 40)]);

      // OK wakes without pausing; the next OK pauses.
      await t.pump(osdHideAfter + const Duration(seconds: 1));
      expect(_opacity(t), 0);
      await _key(t, LogicalKeyboardKey.enter);
      expect(engine.isPlaying, isTrue);
      expect(_opacity(t), 1);
      await _key(t, LogicalKeyboardKey.enter);
      expect(engine.isPlaying, isFalse);
      await _closeRoute(t);
    });

    testWidgets('holding the waking key does not scrub', (t) async {
      final engine = await _open(t, _request());
      engine.durationC.add(const Duration(minutes: 5));
      engine.positionC.add(const Duration(seconds: 30));
      await t.pump(osdHideAfter + const Duration(seconds: 1));
      await t.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      for (var i = 0; i < 5; i++) {
        await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
        await t.pump(const Duration(milliseconds: 150));
      }
      await t.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump(const Duration(seconds: 2));
      expect(_position(t), '0:30');
      expect(engine.seeks, isEmpty);
      await _closeRoute(t);
    });

    testWidgets('a mouse move brings it back', (t) async {
      await _open(t, _request(), form: FormFactor.desktop);
      await t.pump(osdHideAfter + const Duration(seconds: 1));
      expect(_opacity(t), 0);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(200, 200));
      await t.pump();
      expect(_opacity(t), 1);
      await mouse.removePointer();
      await _closeRoute(t);
    });
  });

  group('track menu', () {
    testWidgets('no choice, no button', (t) async {
      final engine = await _open(t, _request());
      engine.emitTracks(
        const MediaTracks(audio: [MediaTrack(id: '1:0', selected: true)]),
      );
      await t.pump();
      expect(find.byKey(PlayerKeys.tracks), findsNothing);
      await _closeRoute(t);
    });

    testWidgets('Down reaches the button; the menu shows language, codec and '
        'channels; it keeps the display up; Back closes only the menu', (
      t,
    ) async {
      final engine = await _open(t, _request());
      engine.emitTracks(_tracks);
      await t.pump();
      await _key(t, LogicalKeyboardKey.arrowDown);
      expect(_focused(PlayerKeys.tracks), isTrue);
      await _key(t, LogicalKeyboardKey.enter);
      await t.pump();
      expect(find.byKey(PlayerKeys.tracksMenu), findsOneWidget);
      expect(find.text('Malayalam'), findsNWidgets(2));
      expect(find.text('AAC · 5.1'), findsOneWidget);
      expect(find.text('Theatre dub · AC-3 · Stereo'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      // Focus starts on the playing audio track.
      expect(_focused(PlayerKeys.audioTrack('1:0')), isTrue);

      await t.pump(const Duration(seconds: 10));
      expect(_opacity(t), 1, reason: 'the menu keeps the display');
      expect(find.byKey(PlayerKeys.tracksMenu), findsOneWidget);

      await t.binding.handlePopRoute();
      await t.pump();
      expect(find.byKey(PlayerKeys.tracksMenu), findsNothing);
      expect(find.byKey(Keys.playerRoot), findsOneWidget);
      await _closeRoute(t);
    });

    testWidgets('picking audio with the D-pad selects and remembers it', (
      t,
    ) async {
      final prefs = Prefs.memory();
      final engine = await _open(t, _request(), prefs: prefs);
      engine.emitTracks(_tracks);
      await t.pump();
      await _key(t, LogicalKeyboardKey.contextMenu);
      await t.pump();
      await _key(t, LogicalKeyboardKey.arrowDown);
      await _key(t, LogicalKeyboardKey.enter);
      await t.pump();
      expect(engine.selections, ['audio:2:0']);
      expect(prefs.getString(PlayerPrefs.audioLanguage), 'ta');
      expect(find.byKey(PlayerKeys.tracksMenu), findsNothing);
      await _closeRoute(t);
    });

    testWidgets('subtitles on, then off: both remembered', (t) async {
      final prefs = Prefs.memory();
      final engine = await _open(t, _request(), prefs: prefs);
      engine.emitTracks(_tracks);
      await t.pump();
      await t.tap(find.byKey(PlayerKeys.tracks));
      await t.pump();
      await t.tap(find.byKey(PlayerKeys.subtitleTrack('3:1')));
      await t.pump();
      expect(engine.selections, ['sub:3:1']);
      expect(prefs.getBool(PlayerPrefs.subtitles), isTrue);
      expect(prefs.getString(PlayerPrefs.subtitleLanguage), 'ml');

      await t.tap(find.byKey(PlayerKeys.tracks));
      await t.pump();
      await t.tap(find.byKey(PlayerKeys.subtitlesOff));
      await t.pump();
      expect(engine.selections.last, 'sub:off');
      expect(prefs.getBool(PlayerPrefs.subtitles), isFalse);
      expect(prefs.getString(PlayerPrefs.subtitleLanguage), 'ml');
      await _closeRoute(t);
    });

    testWidgets('the captions key toggles subtitles', (t) async {
      final prefs = Prefs.memory({PlayerPrefs.subtitleLanguage: 'ml'});
      final engine = await _open(t, _request(), prefs: prefs);
      engine.emitTracks(_tracks);
      await t.pump();
      await _key(t, LogicalKeyboardKey.closedCaptionToggle);
      expect(engine.selections, ['sub:3:1']);
      await _key(t, LogicalKeyboardKey.closedCaptionToggle);
      expect(engine.selections.last, 'sub:off');
      await _closeRoute(t);
    });

    testWidgets('a phone gets a bottom sheet', (t) async {
      final engine = await _open(t, _request(), form: FormFactor.phone);
      engine.emitTracks(_tracks);
      await t.pump();
      await t.tap(find.byKey(PlayerKeys.tracks));
      // A phone's player also listens for double taps.
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await t.tap(find.byKey(PlayerKeys.audioTrack('2:0')));
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(engine.selections, ['audio:2:0']);
      await _closeRoute(t);
    });
  });

  group('preferences', () {
    testWidgets('handed to the engine before open, and applied when it did '
        'not match them itself', (t) async {
      final prefs = Prefs.memory({
        PlayerPrefs.audioLanguage: 'ta',
        PlayerPrefs.subtitles: true,
        PlayerPrefs.subtitleLanguage: 'ml',
      });
      final engine = await _open(t, _request(), prefs: prefs);
      expect(
        engine.preferences.single,
        const TrackPreferences(
          audioLanguage: 'ta',
          subtitleLanguage: 'ml',
          subtitles: true,
        ),
      );
      engine.emitTracks(_tracks);
      await t.pump();
      expect(engine.selections, ['audio:2:0', 'sub:3:1']);
      // Only once per item: a later change is the user's.
      engine.emitTracks(_tracks);
      await t.pump();
      expect(engine.selections, hasLength(2));
      await _closeRoute(t);
    });

    testWidgets('subtitles off by default; nothing is forced on', (t) async {
      final engine = await _open(t, _request());
      expect(engine.preferences.single, const TrackPreferences());
      engine.emitTracks(_tracks);
      await t.pump();
      expect(engine.selections, isEmpty);
      await _closeRoute(t);
    });
  });

  group('YouTube dubs', () {
    const choices = [
      AudioChoice(url: 'http://x/en.m4a', language: 'en', isDefault: true),
      AudioChoice(url: 'http://x/ml.m4a', language: 'ml', label: 'Malayalam'),
    ];
    const spec = MediaSpec(
      videoUrl: 'http://x/v.mp4',
      audioUrl: 'http://x/en.m4a',
      audioChoices: choices,
    );

    testWidgets('another language opens again at the same position', (t) async {
      final prefs = Prefs.memory();
      final engine = await _open(t, _request(spec: spec), prefs: prefs);
      engine.positionC.add(const Duration(seconds: 42));
      engine.emitTracks(
        const MediaTracks(audio: [MediaTrack(id: '1:0', selected: true)]),
      );
      await t.pump();
      await t.tap(find.byKey(PlayerKeys.tracks));
      await t.pump();
      expect(find.text('English'), findsOneWidget);
      await t.tap(find.byKey(PlayerKeys.audioTrack('${choicePrefix}1')));
      await t.pump();
      await t.pump();
      expect(engine.opened, hasLength(2));
      expect(engine.opened.last.audioUrl, 'http://x/ml.m4a');
      expect(engine.opened.last.startPosition, const Duration(seconds: 42));
      expect(engine.opened.last.audioChoices, hasLength(2));
      expect(prefs.getString(PlayerPrefs.audioLanguage), 'ml');
      await _closeRoute(t);
    });

    testWidgets('the preferred language plays from the start', (t) async {
      final engine = await _open(
        t,
        _request(spec: spec),
        prefs: Prefs.memory({PlayerPrefs.audioLanguage: 'ml'}),
      );
      expect(engine.opened.single.audioUrl, 'http://x/ml.m4a');
      await _closeRoute(t);
    });
  });

  group('labels', () {
    test('title and detail', () {
      expect(trackTitle(_tracks.audio[0], 0), 'Malayalam');
      expect(trackDetail(_tracks.audio[0]), 'AAC · 5.1');
      expect(
        trackTitle(const MediaTrack(id: 'x', label: 'Director'), 0),
        'Director',
      );
      expect(trackTitle(const MediaTrack(id: 'x'), 2), 'Track 3');
      expect(
        trackDetail(const MediaTrack(id: 'x', codec: 'dts', channels: 8)),
        '7.1',
      );
      expect(
        trackDetail(
          const MediaTrack(id: 'x', language: 'en', codec: 'pgs', forced: true),
        ),
        'PGS · Forced',
      );
      expect(languageName('xx'), 'XX');
    });

    test('preferredTrack: language, then default, then first', () {
      const list = [
        MediaTrack(id: 'a', language: 'en', forced: true),
        MediaTrack(id: 'b', language: 'en'),
        MediaTrack(id: 'c', language: 'ml', isDefault: true),
      ];
      expect(preferredTrack(list, 'en')!.id, 'b');
      expect(preferredTrack(list, 'ta')!.id, 'c');
      expect(preferredTrack(list, null)!.id, 'c');
      expect(preferredTrack(list.sublist(0, 2), null)!.id, 'a');
      expect(preferredTrack(const [], 'en'), isNull);
    });
  });

  group('picture shape', () {
    testWidgets('Down reaches the button; OK steps the shape and the engine '
        'follows', (t) async {
      final engine = await _open(t, _request());
      expect(engine.aspects, [VideoAspect.fit]);
      await _key(t, LogicalKeyboardKey.arrowDown);
      expect(_focused(PlayerKeys.aspect), isTrue);
      expect(find.text('Original'), findsOneWidget);
      await _key(t, LogicalKeyboardKey.enter);
      await t.pump();
      expect(engine.aspects.last, VideoAspect.stretch);
      expect(find.text('Stretch'), findsOneWidget);
      await _closeRoute(t);
    });

    test('the cycle visits every shape and returns', () {
      var a = VideoAspect.fit;
      final seen = <VideoAspect>[];
      do {
        seen.add(a);
        a = a.next;
      } while (a != VideoAspect.fit);
      expect(seen, VideoAspect.values);
      expect(VideoAspect.byName('r4x3'), VideoAspect.r4x3);
      expect(VideoAspect.byName('nope'), VideoAspect.fit);
    });
  });
}
