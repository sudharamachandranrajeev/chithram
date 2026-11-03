@Tags(['golden'])
library;

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/tv/tv_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../desktop/static_feed.dart';
import 'golden_support.dart';

/// The TV Home: the rail (focus on its first item), the hero and the rails,
/// at 1080p (960x540 dp at density 2) and at 960x540 px.
void main() {
  const surfaces = [
    ('1920x1080', Size(1920, 1080), 2.0),
    ('960x540', Size(960, 540), 1.0),
  ];
  for (final (name, px, density) in surfaces) {
    testWidgets('tv home, $name', skip: goldenSkip, (tester) async {
      await tester.runAsync(loadGoldenFonts);
      tester.view.physicalSize = px;
      tester.view.devicePixelRatio = density;
      addTearDown(tester.view.reset);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await tester.pumpWidget(AppServicesScope(
        services: AppServices.memory(feed: StaticFeed()),
        child: FormScope(
          form: FormFactor.tv,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildChithramTheme(form: FormFactor.tv),
            home: const TvShell(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byType(TvShell), matchesGoldenFile('tv_home_$name.png'));
    });
  }
}
