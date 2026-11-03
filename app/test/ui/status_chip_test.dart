import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:chithram/src/ui/common/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child, {FormFactor form = FormFactor.desktop}) =>
    tester.pumpWidget(FormScope(
      form: form,
      child: MaterialApp(
        theme: buildChithramTheme(form: form),
        home: Scaffold(body: Center(child: child)),
      ),
    ));

void main() {
  const expectedLabels = {
    RequestStatus.requested: 'Requested',
    RequestStatus.awaitingApproval: 'Awaiting approval',
    RequestStatus.searching: 'Searching',
    RequestStatus.downloading: 'Downloading',
    RequestStatus.importing: 'Importing',
    RequestStatus.available: 'Available',
    RequestStatus.failed: 'Failed',
  };
  const expectedIcons = {
    RequestStatus.requested: Icons.schedule,
    RequestStatus.awaitingApproval: Icons.hourglass_top,
    RequestStatus.searching: Icons.travel_explore,
    RequestStatus.downloading: Icons.downloading,
    RequestStatus.importing: Icons.move_to_inbox,
    RequestStatus.available: Icons.check_circle,
    RequestStatus.failed: Icons.error,
  };

  testWidgets('each status renders its label and icon', (tester) async {
    for (final s in RequestStatus.values) {
      await _pump(tester, StatusChip(s));
      expect(find.text(expectedLabels[s]!), findsOneWidget, reason: '$s label');
      expect(find.byIcon(expectedIcons[s]!), findsOneWidget, reason: '$s icon');
    }
  });

  testWidgets('downloading shows the percent', (tester) async {
    await _pump(tester, const StatusChip(RequestStatus.downloading, progress: 0.42));
    expect(find.text('Downloading 42%'), findsOneWidget);
  });

  testWidgets('height follows the form factor', (tester) async {
    for (final (form, h) in [
      (FormFactor.desktop, 24.0),
      (FormFactor.phone, 28.0),
      (FormFactor.tv, 36.0),
    ]) {
      await _pump(tester, const StatusChip(RequestStatus.available), form: form);
      expect(tester.getSize(find.byType(StatusChip)).height, h, reason: '$form');
    }
  });

  test('status colours read on the Night surface (WCAG 4.5:1)', () {
    const surface = Color(0xFF18141E);
    for (final s in RequestStatus.values) {
      final c = s.color(StatusColors.standard);
      expect(ChithramTheme.contrastRatio(c, surface), greaterThanOrEqualTo(4.5), reason: '$s');
    }
  });

  test('status colours read on the chip fill (colour at 16% over the surface) on every preset', () {
    for (final p in ThemePreset.all) {
      for (final s in RequestStatus.values) {
        final c = s.color(p.theme.status);
        final fill = Color.alphaBlend(c.withValues(alpha: 0.16), p.theme.surface);
        expect(ChithramTheme.contrastRatio(c, fill), greaterThanOrEqualTo(4.5), reason: '${p.id} $s');
      }
    }
  });
}
