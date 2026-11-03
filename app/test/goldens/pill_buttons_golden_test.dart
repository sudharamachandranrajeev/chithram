@Tags(['golden'])
library;

import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_support.dart';

/// Primary (accent fill) and secondary (hairline outline) pill buttons built
/// from the theme and the design tokens.
Widget _buttons(BuildContext context) {
  final c = ChithramColors.of(context);
  const shape = StadiumBorder();
  const pad = EdgeInsets.symmetric(horizontal: Space.s24, vertical: Space.s12);
  return Row(
    key: const Key('buttons'),
    mainAxisSize: MainAxisSize.min,
    children: [
      FilledButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.play_arrow),
        label: const Text('Play'),
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          shape: shape,
          padding: pad,
        ),
      ),
      const SizedBox(width: Space.s12),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('My list'),
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          backgroundColor: c.surface,
          side: BorderSide(color: c.text.withValues(alpha: 0.24)),
          shape: shape,
          padding: pad,
        ),
      ),
    ],
  );
}

void main() {
  for (final (name, size, form) in goldenSurfaces) {
    testWidgets('pill buttons, $name', skip: goldenSkip, (tester) async {
      await tester.runAsync(loadGoldenFonts);
      await pumpSurface(
        tester,
        Align(alignment: Alignment.topLeft, child: Builder(builder: _buttons)),
        size: size,
        form: form,
      );
      await expectLater(find.byKey(const Key('buttons')), matchesGoldenFile('pill_buttons_$name.png'));
    });
  }
}
