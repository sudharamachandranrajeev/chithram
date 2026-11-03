@Tags(['golden'])
library;

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/phone/phone_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../desktop/static_feed.dart';
import 'golden_support.dart';

void main() {
  const surfaces = [
    ('421x927', Size(421, 927), 'bottom bar'),
    ('360x640', Size(360, 640), 'bottom bar'),
    ('800x1280', Size(800, 1280), 'rail'),
  ];
  for (final (name, size, nav) in surfaces) {
    testWidgets('phone home, $nav, $name', skip: goldenSkip, (tester) async {
      await tester.runAsync(loadGoldenFonts);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await tester.pumpWidget(AppServicesScope(
        services: AppServices.memory(feed: StaticFeed()),
        child: FormScope(
          form: FormFactor.phone,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildChithramTheme(form: FormFactor.phone),
            home: const PhoneShell(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byType(PhoneShell), matchesGoldenFile('phone_home_$name.png'));
    });
  }
}
