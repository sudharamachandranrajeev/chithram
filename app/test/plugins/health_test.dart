import 'dart:math';

import 'package:chithram/src/data/database.dart';
import 'package:chithram/src/plugins/backoff.dart';
import 'package:chithram/src/plugins/health.dart';
import 'package:chithram/src/plugins/plugin_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs newest first, e.g. `runs('ffo')` is fail, fail, ok (ok = oldest).
List<ProviderRunRow> runs(String s, {String? reason, int ms = 100}) {
  final base = DateTime.utc(2026, 10, 24);
  return [
    for (var i = 0; i < s.length; i++)
      ProviderRunRow(
        providerId: 'p',
        at: base.subtract(Duration(minutes: i)),
        status: s[i] == 'o' ? 'ok' : 'error',
        reason: s[i] == 'o' ? null : (i == 0 ? reason ?? 'timeout' : 'timeout'),
        ms: ms + i,
        results: s[i] == 'o' ? 3 : 0,
        requests: 1,
        blockedHosts: const [],
      ),
  ];
}

void main() {
  PluginHealthStatus status(String s, {String? reason, bool unavailable = false, bool keyChanged = false}) =>
      classifyHealth(runs(s, reason: reason), unavailable: unavailable, keyChanged: keyChanged).status;

  group('classifyHealth', () {
    test('table (newest run first: o = ok, f = failed)', () {
      const table = <String, PluginHealthStatus>{
        '': PluginHealthStatus.untested,
        'o': PluginHealthStatus.healthy,
        'ooo': PluginHealthStatus.healthy,
        'fo': PluginHealthStatus.degraded, // 50 %
        'ffo': PluginHealthStatus.degraded, // 33 %
        'fff': PluginHealthStatus.failing,
        'ffffoooo': PluginHealthStatus.failing, // the last 3 failed, whatever came before
        'ff': PluginHealthStatus.degraded, // fewer than 3 runs is not yet Failing
        'f': PluginHealthStatus.degraded,
        'ofoooooooo': PluginHealthStatus.healthy, // 90 %
        'ooffffffff': PluginHealthStatus.degraded, // an ok in the last 3, but 20 %
        'oooooooofff': PluginHealthStatus.healthy, // 8 of 11 = 73 %
      };
      for (final e in table.entries) {
        expect(status(e.key), e.value, reason: e.key);
      }
    });

    test('the 70 % boundary: 7 of 10 is Healthy, 6 of 10 is Degraded', () {
      expect(status('ooooooofff'), PluginHealthStatus.healthy);
      expect(status('oooffooffo'), PluginHealthStatus.degraded);
    });

    test('Blocked: url-changed, hash-mismatch, key change', () {
      expect(status('fo', reason: 'url-changed'), PluginHealthStatus.blocked);
      expect(status('f', reason: 'hash-mismatch'), PluginHealthStatus.blocked);
      expect(status('ooo', keyChanged: true), PluginHealthStatus.blocked);
      expect(status('', keyChanged: true), PluginHealthStatus.blocked);
      expect(status('ff', reason: 'timeout'), PluginHealthStatus.degraded);
    });

    test('Unavailable beats everything', () {
      expect(status('ooo', unavailable: true), PluginHealthStatus.unavailable);
      expect(status('', unavailable: true), PluginHealthStatus.unavailable);
      expect(status('fo', reason: 'url-changed', unavailable: true), PluginHealthStatus.unavailable);
    });

    test('details: success rate, median time of ok runs, last error', () {
      final h = classifyHealth(runs('fooof', ms: 100));
      expect(h.successRate, closeTo(0.6, 1e-9));
      expect(h.medianMs, 102); // ok runs took 101, 102, 103
      expect(h.lastError, 'timeout');
      expect(h.runs, 5);
    });
  });

  group('Backoff', () {
    test('doubles from the base, +-20 % jitter, never over the cap', () {
      final b = Backoff(random: Random(1));
      for (var n = 1; n <= 12; n++) {
        final d = b.delay(n);
        final nominal = min(5 * 60 * pow(2, n - 1), 6 * 3600).toDouble();
        expect(d.inSeconds, inInclusiveRange((nominal * 0.8).floor(), min((nominal * 1.2).ceil(), 6 * 3600)), reason: 'failure $n');
      }
      expect(b.delay(40).inSeconds, lessThanOrEqualTo(6 * 3600));
    });

    test('Retry-After wins when longer, but also stays under the cap', () {
      final b = Backoff(random: Random(2));
      expect(b.delay(1, retryAfter: const Duration(hours: 3)), const Duration(hours: 3));
      expect(b.delay(1, retryAfter: const Duration(days: 2)), const Duration(hours: 6));
      expect(b.delay(1, retryAfter: const Duration(seconds: 1)).inSeconds, greaterThan(200));
    });

    test('Retry-After header parsing', () {
      expect(parseRetryAfter('120'), const Duration(seconds: 120));
      expect(parseRetryAfter('nonsense'), isNull);
      expect(parseRetryAfter(null), isNull);
      final now = DateTime.utc(2026, 10, 24, 12);
      expect(parseRetryAfter('Sat, 24 Oct 2026 12:05:00 GMT', now: now), const Duration(minutes: 5));
      expect(parseRetryAfter('Sat, 24 Oct 2026 11:00:00 GMT', now: now), Duration.zero);
    });

    test('MinGap spaces requests', () {
      var t = DateTime.utc(2026, 1, 1);
      final g = MinGap(const Duration(seconds: 1), now: () => t);
      expect(g.take(), Duration.zero);
      expect(g.take(), const Duration(seconds: 1));
      t = t.add(const Duration(seconds: 5));
      expect(g.take(), Duration.zero);
    });
  });
}
