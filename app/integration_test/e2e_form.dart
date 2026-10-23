// End-to-end: the device reports the form factor the job expects and the
// matching shell renders. Run through e2e_all_test.dart on the TV emulator
// (E2E_FORM=tv) and on Linux (E2E_FORM=desktop); skipped without E2E_FORM.
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/phone/phone_shell.dart';
import 'package:chithram/src/ui/tv/tv_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The form factor this job expects: tv, desktop or phone.
const e2eForm = String.fromEnvironment('E2E_FORM');

/// What the device says it is: the Android activity's answer, else the platform.
Future<FormFactor?> detectFormFactor() async =>
    await androidFormFactor() ?? resolveFormFactor(platform: defaultTargetPlatform);

void formE2e() {
  group('form factor', () {
    testWidgets('the device reports "$e2eForm" and its shell renders', (t) async {
      final detected = await detectFormFactor();
      // ignore: avoid_print
      print('CHITHRAM_E2E form factor: ${detected?.name}');
      expect(detected?.name, e2eForm);
      await t.pumpWidget(ChithramApp(formFactor: detected));
      await t.pumpAndSettle();
      expect(find.byType(detected == FormFactor.phone ? PhoneShell : TvShell), findsOneWidget);
    }, skip: e2eForm.isEmpty);
  });
}
