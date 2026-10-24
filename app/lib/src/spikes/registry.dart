import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'player_page.dart';
import 'torrent_page.dart';

/// Debug-only spike pages.
///
/// Open on Android with `adb shell am start -n dev.chithram.chithram/.MainActivity
/// --es route /spike/<name>` (Flutter reads the `route` extra as the initial
/// route). On desktop run `flutter run --dart-define=SPIKE=<name>`.
///
/// Guard: everything is behind [kDebugMode], a compile-time constant, so release
/// and profile builds tree-shake the pages and the routes resolve to null.
const String _spikeDefine = String.fromEnvironment('SPIKE');

final Map<String, WidgetBuilder> _spikes = {
  'torrent': (_) => const TorrentSpikePage(),
  'player': (_) => const PlayerSpikePage(),
};

/// Initial route override for desktop (`--dart-define=SPIKE=name`), else null.
String? spikeInitialRoute() =>
    kDebugMode && _spikeDefine.isNotEmpty ? '/spike/$_spikeDefine' : null;

/// `MaterialApp.onGenerateRoute`: resolves `/spike/<name>` in debug builds only.
Route<dynamic>? spikeRoute(RouteSettings settings) {
  if (!kDebugMode) return null;
  final name = settings.name;
  if (name == null || !name.startsWith('/spike/')) return null;
  final builder = _spikes[name.substring('/spike/'.length)];
  if (builder == null) return null;
  return MaterialPageRoute<void>(settings: settings, builder: builder);
}
