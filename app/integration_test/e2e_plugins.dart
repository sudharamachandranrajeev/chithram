// End-to-end: search plugins. Run through e2e_all_test.dart. Stub: no plugin
// is preinstalled, so the registry offers no providers (WP-D fills this in).
import 'package:chithram/src/plugins/plugin_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void pluginsE2e() {
  group('plugins', () {
    testWidgets('a fresh install has no plugins and no repo', (t) async {
      expect(PluginRegistry().providers.value, isEmpty);
      // The fixture repo URL is only a define; nothing is added by default.
      expect(e2ePluginRepo.isEmpty || e2ePluginRepo.startsWith('http'), isTrue);
    });
  });
}
