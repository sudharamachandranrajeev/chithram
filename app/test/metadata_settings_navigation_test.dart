import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/features/metadata/attribution.dart';
import 'package:chithram/src/features/metadata/metadata_settings.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/settings_page.dart';
import 'package:chithram/src/ui/phone/phone_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop About opens attribution with the licensed logo', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildChithramTheme(form: FormFactor.desktop),
      home: const Scaffold(body: AboutSettings()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About Chithram'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutDialog), findsOneWidget);
    expect(find.text(tmdbNotice), findsOneWidget);
    expect(find.bySemanticsLabel('TMDB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone exposes metadata and About attribution at 360 dp', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final services = AppServices.memory();
    addTearDown(services.db.close);
    await tester.pumpWidget(AppServicesScope(
      services: services,
      child: FormScope(
        form: FormFactor.phone,
        child: MaterialApp(
          theme: buildChithramTheme(form: FormFactor.phone),
          home: const Scaffold(body: PhoneSettings()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(MetadataSettings), findsOneWidget);
    await tester.scrollUntilVisible(find.text('About Chithram'), 250);
    await tester.tap(find.text('About Chithram'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutDialog), findsOneWidget);
    expect(find.descendant(of: find.byType(AboutDialog), matching: find.text(tmdbNotice)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
