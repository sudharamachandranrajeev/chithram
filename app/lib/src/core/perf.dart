import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Performance markers for `perf.yml`. Compiled out unless built with
/// `--dart-define=PERF_PROBE=true`: then `mark('home_refreshed', {'rails': 9})`
/// prints `CHITHRAM_HOME_REFRESHED rails=9` for the harness to read from logcat.
abstract final class Perf {
  static const enabled = bool.fromEnvironment('PERF_PROBE');

  static void mark(String name, [Map<String, Object?> fields = const {}]) {
    if (!enabled) return;
    final tail = fields.entries.map((e) => ' ${e.key}=${e.value}').join();
    // ignore: avoid_print
    debugPrint('CHITHRAM_${name.toUpperCase()}$tail');
  }
}

/// Frame timing for `perf.yml` (only with PERF_PROBE). Prints
/// `CHITHRAM_JANK build_ms=.. raster_ms=..` for every frame whose UI-thread build
/// took more than 32 ms, and `CHITHRAM_FRAMES n=.. over16=.. max_build_ms=..`
/// for every 60 frames. CI gates the build time only: its emulator renders in
/// software, so raster time is report-only (the owner's device runs cover it).
abstract final class FrameProbe {
  static bool _installed = false;
  static int _n = 0, _over16 = 0, _maxBuildUs = 0;

  static void install() {
    if (!Perf.enabled || _installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final build = t.buildDuration.inMicroseconds;
        _n++;
        if (build > 16000) _over16++;
        if (build > _maxBuildUs) _maxBuildUs = build;
        if (build > 32000) {
          Perf.mark('jank', {
            'build_ms': (build / 1000).toStringAsFixed(1),
            'raster_ms': (t.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1),
          });
        }
        if (_n >= 60) {
          Perf.mark('frames', {
            'n': _n,
            'over16': _over16,
            'max_build_ms': (_maxBuildUs / 1000).toStringAsFixed(1),
          });
          _n = _over16 = _maxBuildUs = 0;
        }
      }
    });
  }
}
