@Tags(['golden'])
library;

import 'package:chithram/src/ui/common/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_support.dart';

void main() {
  for (final (name, size, form) in goldenSurfaces) {
    testWidgets('StatusChip, all statuses, $name', skip: goldenSkip, (tester) async {
      await tester.runAsync(loadGoldenFonts);
      await pumpSurface(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            key: const Key('chips'),
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final s in RequestStatus.values)
                StatusChip(s, progress: s == RequestStatus.downloading ? 0.42 : null),
            ],
          ),
        ),
        size: size,
        form: form,
      );
      await expectLater(find.byKey(const Key('chips')), matchesGoldenFile('status_chip_$name.png'));
    });
  }
}
