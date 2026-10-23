import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/dims.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/phone/phone_shell.dart';
import 'package:chithram/src/ui/tv/tv_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAt(WidgetTester t, Size size, Widget app) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(app);
  await t.pumpAndSettle();
}

void main() {
  group('resolveFormFactor', () {
    test('Android: the launcher arg decides', () {
      expect(resolveFormFactor(platform: TargetPlatform.android, arg: 'tv'), FormFactor.tv);
      expect(resolveFormFactor(platform: TargetPlatform.android, arg: 'phone'), FormFactor.phone);
    });

    test('Android: no arg, or one that is not tv or phone, says nothing', () {
      expect(resolveFormFactor(platform: TargetPlatform.android), isNull);
      expect(resolveFormFactor(platform: TargetPlatform.android, arg: 'desktop'), isNull);
      expect(resolveFormFactor(platform: TargetPlatform.android, arg: 'junk'), isNull);
    });

    test('Windows and Linux are desktop', () {
      expect(resolveFormFactor(platform: TargetPlatform.windows), FormFactor.desktop);
      expect(resolveFormFactor(platform: TargetPlatform.linux), FormFactor.desktop);
      // An Android arg means nothing on a desktop.
      expect(resolveFormFactor(platform: TargetPlatform.linux, arg: 'tv'), FormFactor.desktop);
    });

    test('desktop with the 10-foot preference is the TV design', () {
      expect(resolveFormFactor(platform: TargetPlatform.linux, tenFoot: true), FormFactor.tv);
      expect(resolveFormFactor(platform: TargetPlatform.windows, tenFoot: true), FormFactor.tv);
    });

    test('the preference does not touch Android', () {
      expect(resolveFormFactor(platform: TargetPlatform.android, arg: 'phone', tenFoot: true), FormFactor.phone);
    });

    test('the define beats the preference and detection', () {
      expect(
        resolveFormFactor(platform: TargetPlatform.android, define: 'phone', arg: 'tv'),
        FormFactor.phone,
      );
      expect(
        resolveFormFactor(platform: TargetPlatform.linux, define: 'tv'),
        FormFactor.tv,
      );
      expect(
        resolveFormFactor(platform: TargetPlatform.linux, define: 'desktop', tenFoot: true),
        FormFactor.desktop,
      );
      expect(resolveFormFactor(platform: TargetPlatform.android, define: ''), isNull);
    });

    test('formFactorArg reads --form-factor= among other args', () {
      expect(formFactorArg(const ['--smoke', '--form-factor=tv']), 'tv');
      expect(formFactorArg(const ['--smoke']), isNull);
    });
  });

  group('Dims', () {
    test('without a form, the window size decides as before', () {
      expect(Dims.formFor(const Size(400, 800)), FormFactor.phone);
      expect(Dims.formFor(const Size(1920, 1080)), FormFactor.tv); // test platform is Android
      expect(Dims.formFor(const Size(927, 421)), FormFactor.tv);
    });

    testWidgets('a phone in a 927x421 window is still a phone', (t) async {
      late Dims dims;
      await pumpAt(
        t,
        const Size(927, 421),
        MaterialApp(
          home: FormScope(
            form: FormFactor.phone,
            child: Builder(builder: (c) {
              dims = Dims.of(c);
              return const SizedBox();
            }),
          ),
        ),
      );
      expect(dims.phone, isTrue);
      expect(dims.tv, isFalse);
    });

    testWidgets('no scope: the size fallback', (t) async {
      late Dims dims;
      await pumpAt(
        t,
        const Size(400, 800),
        MaterialApp(home: Builder(builder: (c) {
          dims = Dims.of(c);
          return const SizedBox();
        })),
      );
      expect(dims.phone, isTrue);
    });
  });

  group('ChithramApp', () {
    testWidgets('the form it is given picks the shell, whatever the window', (t) async {
      await pumpAt(t, const Size(927, 421), const ChithramApp(formFactor: FormFactor.phone));
      expect(find.byType(PhoneShell), findsOneWidget);
      expect(find.byType(TvShell), findsNothing);
    });

    testWidgets('a TV form in a phone-sized window is still the TV shell', (t) async {
      await pumpAt(t, const Size(400, 800), const ChithramApp(formFactor: FormFactor.tv));
      expect(find.byType(TvShell), findsOneWidget);
    });

    testWidgets('desktop with the 10-foot preference is the TV shell, and it applies at once', (t) async {
      final prefs = Prefs.memory();
      await pumpAt(
        t,
        const Size(1280, 800),
        ChithramApp(
          services: AppServices.memory(prefs: prefs),
          formFactor: FormFactor.desktop,
        ),
      );
      Dims dimsNow() => Dims.of(t.element(find.byType(TvShell)));
      expect(dimsNow().form, FormFactor.desktop);
      await prefs.set(tenFootPref, true);
      await t.pumpAndSettle();
      expect(dimsNow().form, FormFactor.tv);
      await prefs.set(tenFootPref, false);
      await t.pumpAndSettle();
      expect(dimsNow().form, FormFactor.desktop);
    });
  });

  group('OrientationPolicy', () {
    test('phones stay in portrait, tablets and the rest rotate', () {
      expect(OrientationPolicy.allowedFor(FormFactor.phone, 421), [DeviceOrientation.portraitUp]);
      expect(OrientationPolicy.allowedFor(FormFactor.phone, 800), DeviceOrientation.values);
      expect(OrientationPolicy.allowedFor(FormFactor.tv, 540), DeviceOrientation.values);
      expect(OrientationPolicy.allowedFor(FormFactor.desktop, 800), DeviceOrientation.values);
    });
  });
}
