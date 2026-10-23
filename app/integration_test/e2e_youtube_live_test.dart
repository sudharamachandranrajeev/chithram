// Real network, non-blocking: search YouTube for "big buck bunny" and play the
// first result for 5 s. Needs a network that YouTube serves (CI runners often
// get LOGIN_REQUIRED). Run with no E2E_BASE:
//   flutter test integration_test/e2e_youtube_live_test.dart -d linux
import 'package:chithram/src/ui/common/app.dart';
import 'package:chithram/src/ui/common/keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_youtube.dart';
import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real search for "big buck bunny" plays to 5 s', (t) async {
    await t.pumpWidget(const ChithramApp());
    await t.pumpAndSettle();
    // The first tile of the grid, whatever video it is.
    final first = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('yt-result-'),
        )
        .first;
    await searchAndOpen(t, 'big buck bunny', first);
    expect(find.byKey(Keys.playerRoot), findsOneWidget);
    final position = await waitForPlayback(
      t,
      atLeast: const Duration(seconds: 5),
      timeout: const Duration(seconds: 90),
    );
    // ignore: avoid_print
    print('CHITHRAM_E2E youtube-live reached $position');
  });
}
