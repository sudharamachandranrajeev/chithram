import 'package:flutter/foundation.dart';

import '../find/find_api.dart';

/// R0 stub (WP-D replaces it): no plugins, so no providers.
class PluginRegistry implements FindProviderSource {
  PluginRegistry();

  final _providers = ValueNotifier<List<FindProvider>>(const []);

  @override
  ValueListenable<List<FindProvider>> get providers => _providers;
}
