import 'dart:io';

import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Goldens are pixel-exact, so they are made and checked on Linux only
/// (`flutter test --tags golden`); elsewhere the tests are skipped.
final bool goldenSkip = !Platform.isLinux;

/// Loads the real Poppins and Material icon fonts, as screenshots_test does.
Future<void> loadGoldenFonts() async {
  final poppins = FontLoader('Poppins');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    poppins.addFont(
      Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$w.ttf').readAsBytesSync())),
    );
  }
  await poppins.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    fail('FLUTTER_ROOT is not set; goldens need it to find the Material icon font.');
  }
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!icons.existsSync()) {
    fail('Material icon font missing at ${icons.path}; goldens would draw blank icons.');
  }
  final l = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await l.load();
}

/// The surfaces the redesign is checked on: desktop, TV at 1080p (960x540 dp)
/// and a phone.
const goldenSurfaces = <(String, Size, FormFactor)>[
  ('desktop', Size(1440, 900), FormFactor.desktop),
  ('tv', Size(960, 540), FormFactor.tv),
  ('phone', Size(412, 915), FormFactor.phone),
];

/// Pumps [child] on a page of [size] in [form], in the [colors] look.
Future<void> pumpSurface(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required FormFactor form,
  ChithramTheme colors = ChithramTheme.night,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(FormScope(
    form: form,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildChithramTheme(form: form, colors: colors),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: child)),
    ),
  ));
  await tester.pumpAndSettle();
}
