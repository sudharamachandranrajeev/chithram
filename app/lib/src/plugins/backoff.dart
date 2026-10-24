import 'dart:io' show HttpDate;
import 'dart:math';

/// Network etiquette for the background repo checks: exponential backoff with
/// +-20% jitter, capped at 6 h; a server's Retry-After is honoured; and a
/// minimum gap between requests (a token bucket of one).
class Backoff {
  Backoff({Random? random, this.base = const Duration(minutes: 5), this.cap = const Duration(hours: 6)})
      : _random = random ?? Random();

  final Random _random;
  final Duration base;
  final Duration cap;

  /// How long to wait after the [failures]-th failure in a row (1 for the
  /// first). [retryAfter] from a 429 or 503 wins when it is longer. Never over
  /// [cap], jitter included.
  Duration delay(int failures, {Duration? retryAfter}) {
    final exp = base.inSeconds * pow(2, max(0, failures - 1));
    final raw = min(exp, cap.inSeconds.toDouble());
    final jittered = raw * (0.8 + _random.nextDouble() * 0.4);
    var d = Duration(seconds: min(jittered, cap.inSeconds.toDouble()).round());
    if (retryAfter != null && retryAfter > d) d = retryAfter > cap ? cap : retryAfter;
    return d;
  }
}

/// Parses a `Retry-After` header: delay seconds, or an HTTP date.
Duration? parseRetryAfter(String? value, {DateTime? now}) {
  if (value == null) return null;
  final secs = int.tryParse(value.trim());
  if (secs != null) return Duration(seconds: max(0, secs));
  try {
    final at = HttpDate.parse(value.trim());
    final d = at.difference(now ?? DateTime.now().toUtc());
    return d.isNegative ? Duration.zero : d;
  } catch (_) {
    return null;
  }
}

/// Spaces calls at least [gap] apart.
class MinGap {
  MinGap(this.gap, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final Duration gap;
  final DateTime Function() _now;
  DateTime? _last;

  /// How long to wait before the next call; records the call as happening then.
  Duration take() {
    final now = _now();
    final last = _last;
    final wait = last == null ? Duration.zero : (last.add(gap).difference(now));
    final w = wait.isNegative ? Duration.zero : wait;
    _last = now.add(w);
    return w;
  }
}
