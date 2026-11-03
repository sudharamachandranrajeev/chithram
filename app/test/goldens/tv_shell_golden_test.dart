@Tags(['golden'])
library;

import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/tv/tv_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../desktop/static_feed.dart';
import 'golden_support.dart';

/// The TV Home: the rail (focus on its first item), the hero and the rails,
/// at 1080p (960x540 dp at density 2) and at 960x540 px; and the same with the
/// first tile focused (ring, glow and the gap to its neighbour).
void main() {
  const surfaces = [
    ('1920x1080', Size(1920, 1080), 2.0),
    ('960x540', Size(960, 540), 1.0),
    // A desktop in 10-foot mode: 1920 dp wide, so the widest tiles.
    ('1920dp', Size(1920, 1080), 1.0),
  ];
  for (final (name, px, density) in surfaces) {
    for (final focusTile in [false, true]) {
      if (!focusTile && name == '1920dp') continue;
      final file = focusTile ? 'tv_home_focus_$name.png' : 'tv_home_$name.png';
      testWidgets('tv home${focusTile ? ' with the first tile focused' : ''}, $name',
          skip: goldenSkip, (tester) async {
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
        if (focusTile) {
          // D-pad: rail -> hero Play -> first tile of the first rail.
          for (final key in [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowDown]) {
            await tester.sendKeyEvent(key);
            await tester.pumpAndSettle();
          }
        }
        await expectLater(find.byType(TvShell), matchesGoldenFile(file));
      });
    }
  }
}
