// The phone Home hero and its status page at large text sizes: no overflow,
// and a rail card's label tells a screen reader how much was watched.
import 'dart:io';

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/youtube/feed/youtube_feed.dart';
import 'package:chithram/src/features/youtube/phone/phone_video_card.dart';
import 'package:chithram/src/features/youtube/youtube_fixture.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/phone/phone_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:innertube/innertube.dart' hide Page;

import 'fixed_feed.dart';

/// The app font: the test font (every glyph a wide box) would hide real
/// line heights.
Future<void> _loadPoppins() async {
  final loader = FontLoader('Poppins');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = await File('assets/fonts/Poppins-$w.ttf').readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

const _long = 'A very long video title that surely wraps onto a second line at any size';

Future<void> _pump(WidgetTester tester, Widget home, {double scale = 1, FeedState? feed}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(_loadPoppins);
  await tester.pumpWidget(AppServicesScope(
    services: AppServices.memory(feed: FixedFeed(feed ?? const FeedState())),
    child: FormScope(
      form: FormFactor.phone,
      child: MaterialApp(
        theme: buildChithramTheme(form: FormFactor.phone),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: home),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('hero with a two-line title at text scale $scale does not overflow', (tester) async {
      final video = VideoItem(
        videoId: 'h0000000001',
        title: _long,
        author: 'A channel with a long name',
        viewsText: '1.2M views',
      );
      await _pump(tester, const PhoneHome(), scale: scale, feed: FeedState(hero: [video, video]));
      expect(tester.takeException(), isNull);
      expect(find.text('Play'), findsOneWidget);
      // The card holds its text: the Play button is inside the hero page.
      final hero = tester.getRect(find.byKey(const ValueKey('phone-hero')));
      expect(hero.contains(tester.getCenter(find.text('Play'))), isTrue);
    });

    testWidgets('a long error on the status page at text scale $scale does not overflow', (tester) async {
      await _pump(
        tester,
        const PhoneHome(),
        scale: scale,
        feed: FeedState(error: 'Could not reach YouTube. ' * 8),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Retry'), findsOneWidget);
    });
  }

  testWidgets('a rail card says how much was watched', (tester) async {
    final semantics = tester.ensureSemantics();
    final item = FixtureBrowse.videos('c', 1).single;
    await _pump(tester, Center(child: SizedBox(width: 240, child: PhoneVideoCard(item: item, progress: 0.4, onOpen: () {}))));
    expect(find.bySemanticsLabel(RegExp(r'^Play Fixture c 1.*, 40% watched$')), findsOneWidget);
    await _pump(tester, Center(child: SizedBox(width: 240, child: PhoneVideoCard(item: item, onOpen: () {}))));
    expect(find.bySemanticsLabel(RegExp('watched')), findsNothing);
    semantics.dispose();
  });
}
