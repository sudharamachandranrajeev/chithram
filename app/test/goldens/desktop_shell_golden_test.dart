@Tags(['golden'])
library;

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/sections.dart';
import 'package:chithram/src/ui/desktop/desktop_home.dart';
import 'package:chithram/src/ui/desktop/desktop_shell.dart';
import 'package:chithram/src/ui/tv/focus_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../desktop/static_feed.dart';
import 'golden_support.dart';

Future<void> _pump(WidgetTester tester, Size size, Widget home) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // No keyboard focus ring: it depends on how the test was driven.
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  await tester.pumpWidget(AppServicesScope(
    services: AppServices.memory(feed: StaticFeed()),
    child: FormScope(
      form: FormFactor.desktop,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildChithramTheme(form: FormFactor.desktop),
        home: home,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const surfaces = [
    ('1440x900', Size(1440, 900), 'expanded'),
    ('1100x800', Size(1100, 800), 'collapsed'),
  ];
  for (final (size, dims, sidebar) in surfaces) {
    testWidgets('desktop shell, sidebar $sidebar, $size', skip: goldenSkip, (tester) async {
      await tester.runAsync(loadGoldenFonts);
      await _pump(tester, dims, const DesktopShell());
      await expectLater(find.byType(DesktopShell), matchesGoldenFile('desktop_shell_$size.png'));
    });

    testWidgets('desktop home, $size', skip: goldenSkip, (tester) async {
      await tester.runAsync(loadGoldenFonts);
      await _pump(
        tester,
        dims,
        Scaffold(body: DesktopHome(focus: SectionFocus(), onOpenSection: (Section _) {})),
      );
      await expectLater(find.byType(DesktopHome), matchesGoldenFile('desktop_home_$size.png'));
    });
  }
}
