import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'session.dart';

/// Plugins cannot run on this device. Search falls back to Torznab only.
/// There is deliberately no same-UID fallback: plugin code only ever runs in an
/// isolated-process service (separate uid, no network, no app data).
class PluginsUnavailable implements Exception {
  PluginsUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'PluginsUnavailable: $reason';
}

/// Result of starting the isolated plugin service, for the report.
class AndroidStartReport {
  AndroidStartReport(this.isolated, this.detail);
  final bool isolated;
  final String detail;
  String get line => 'NOVA_ISOLATED=${isolated ? 'yes' : 'no'} detail="$detail"';
}

/// A runner inside the Android isolated-process service (CPython's Android build,
/// embedded through JNI). Same NDJSON as the desktop process, carried over a
/// Messenger (chunked, to stay under the Binder limit) instead of pipes.
class AndroidNovaSession implements NovaSession {
  AndroidNovaSession._(this.limits) {
    _timer = Timer(limits.wall + const Duration(seconds: 3), () => kill('wall-timeout'));
  }

  static const MethodChannel _ch = MethodChannel('dev.chithram/nova_host');
  static AndroidNovaSession? _active;
  static AndroidStartReport? lastReport;
  static bool _wired = false;

  /// Set when the platform cannot run plugins (e.g. an ABI without CPython, or the isolated
  /// service failed to start). Cached: we do not retry into a weaker mode.
  static String? disabledReason;

  static void _wire() {
    if (_wired) return;
    _wired = true;
    _ch.setMethodCallHandler((call) async {
      final s = _active;
      if (s == null) return null;
      if (call.method == 'line') s._onLine(call.arguments as String);
      if (call.method == 'ended') s._end();
      return null;
    });
  }

  /// [audit] false runs with the kernel/uid isolation only (CI proves both).
  static Future<AndroidNovaSession> start({NovaLimits limits = const NovaLimits(), bool audit = true}) async {
    _wire();
    if (disabledReason != null) throw PluginsUnavailable(disabledReason!);
    final r = await _ch.invokeMapMethod<Object?, Object?>('start', {'audit': audit});
    final started = r?['started'] == true;
    final detail = '${r?['detail']}';
    lastReport = AndroidStartReport(started, detail);
    if (!started) {
      disabledReason = detail;
      throw PluginsUnavailable(detail);
    }
    final s = AndroidNovaSession._(limits);
    _active = s;
    return s;
  }

  final NovaLimits limits;
  late final Timer _timer;
  final _out = StreamController<Map<String, Object?>>();
  final _exit = Completer<int?>();
  String? _killed;
  int _bytes = 0;
  bool _closed = false;

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  String? get killedReason => _killed;

  @override
  String get stderrHead => lastReport?.line ?? '';

  @override
  Future<int?> get exitCode => _exit.future;

  void _onLine(String line) {
    if (_closed) return;
    _bytes += line.length + 1;
    if (line.length > limits.maxLineBytes) {
      kill('line-limit');
      return;
    }
    if (_bytes > limits.maxStdoutBytes) {
      kill('stdout-limit');
      return;
    }
    try {
      final m = jsonDecode(line);
      if (m is Map<String, Object?>) _out.add(m);
    } on FormatException {
      kill('protocol-violation');
    }
  }

  void _end() {
    if (_closed) return;
    _closed = true;
    _timer.cancel();
    if (identical(_active, this)) _active = null;
    _out.close();
    if (!_exit.isCompleted) _exit.complete(_killed == null || _killed == 'cleanup' ? 0 : 137);
  }

  @override
  void send(Map<String, Object?> message) {
    if (_closed) return;
    if (message['op'] == 'quit') {
      kill('cleanup');
      return;
    }
    _ch.invokeMethod<bool>('send', {'line': jsonEncode(message)});
  }

  @override
  Future<void> kill(String reason) async {
    if (_closed) return;
    _killed ??= reason;
    await _ch.invokeMethod<bool>('stop');
    _end();
  }
}
