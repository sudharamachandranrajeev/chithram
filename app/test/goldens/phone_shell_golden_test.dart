@Tags(['golden'])
library;

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/youtube/feed/youtube_feed.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/phone/phone_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../desktop/static_feed.dart';
import '../phone/fixed_feed.dart';
import 'golden_support.dart';

Future<void> _pumpShell(
  WidgetTester tester,
  Size size, {
  YouTubeFeed? feed,
  ChithramTheme colors = ChithramTheme.night,
  double scale = 1,
}) async {
  await tester.runAsync(loadGoldenFonts);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  await tester.pumpWidget(AppServicesScope(
    services: AppServices.memory(feed: feed ?? StaticFeed()),
    child: FormScope(
      form: FormFactor.phone,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildChithramTheme(form: FormFactor.phone, colors: colors),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const PhoneShell(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const surfaces = [
    ('421x927', Size(421, 927), 'bottom bar'),
    ('360x640', Size(360, 640), 'bottom bar'),
    ('800x1280', Size(800, 1280), 'rail'),
  ];
  for (final (name, size, nav) in surfaces) {
    testWidgets('phone home, $nav, $name', skip: goldenSkip, (tester) async {
      await _pumpShell(tester, size);
      await expectLater(find.byType(PhoneShell), matchesGoldenFile('phone_home_$name.png'));
    });
  }

  testWidgets('phone home, 360x640 at text scale 1.3', skip: goldenSkip, (tester) async {
    await _pumpShell(tester, const Size(360, 640), scale: 1.3);
    await expectLater(find.byType(PhoneShell), matchesGoldenFile('phone_home_360x640_text1.3.png'));
  });

  testWidgets('phone home, error state, 421x927', skip: goldenSkip, (tester) async {
    await _pumpShell(
      tester,
      const Size(421, 927),
      feed: FixedFeed(const FeedState(error: 'Could not reach YouTube. Check the connection.')),
    );
    await expectLater(find.byType(PhoneShell), matchesGoldenFile('phone_home_error_421x927.png'));
  });

  testWidgets('phone home, Saffron look, 421x927', skip: goldenSkip, (tester) async {
    await _pumpShell(tester, const Size(421, 927), colors: ChithramTheme.saffron);
    await expectLater(find.byType(PhoneShell), matchesGoldenFile('phone_home_saffron_421x927.png'));
  });
}
