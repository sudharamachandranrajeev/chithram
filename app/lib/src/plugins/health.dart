import '../data/database.dart';
import 'plugin_models.dart';

/// Reasons that make a plugin Blocked rather than just failing: the user has to
/// look at it (it names another site, its file changed, or its repo key did).
const blockingReasons = {'url-changed', 'hash-mismatch', 'key-changed'};

/// Health from the kept runs (newest first), per the 0.3.0 plan:
///
///  - Unavailable: no runtime here.
///  - Blocked: `url-changed`, `hash-mismatch` or a changed repo key.
///  - Failing: the last 3 runs all failed.
///  - Healthy: at least one ok in the last 3 runs and at least 70% ok overall.
///  - Degraded: everything else that has run.
///  - Untested: no runs.
PluginHealth classifyHealth(
  List<ProviderRunRow> runs, {
  bool unavailable = false,
  bool keyChanged = false,
}) {
  final ok = [for (final r in runs) r.status == 'ok'];
  final rate = runs.isEmpty ? null : ok.where((o) => o).length / runs.length;
  final times = [for (final r in runs.where((r) => r.status == 'ok')) r.ms]..sort();
  final median = times.isEmpty ? null : times[times.length ~/ 2];
  final lastFailure = runs.where((r) => r.status != 'ok').firstOrNull;
  final blocked = <String>{for (final r in runs.take(20)) ...r.blockedHosts}.toList()..sort();
  PluginHealth build(PluginHealthStatus s) => PluginHealth(
        status: s,
        successRate: rate,
        medianMs: median,
        lastError: lastFailure == null ? null : (lastFailure.reason ?? lastFailure.status),
        blockedHosts: blocked,
        runs: runs.length,
      );

  if (unavailable) return build(PluginHealthStatus.unavailable);
  if (keyChanged || (runs.isNotEmpty && blockingReasons.contains(runs.first.reason))) {
    return build(PluginHealthStatus.blocked);
  }
  if (runs.isEmpty) return PluginHealth.untested;
  final last3 = ok.take(3).toList();
  if (last3.length == 3 && !last3.contains(true)) return build(PluginHealthStatus.failing);
  if (last3.contains(true) && rate! >= 0.7) return build(PluginHealthStatus.healthy);
  return build(PluginHealthStatus.degraded);
}
