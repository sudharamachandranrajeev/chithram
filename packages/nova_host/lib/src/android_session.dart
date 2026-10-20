import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'session.dart';

/// Result of the Android service start-up, for the report.
class AndroidStartReport {
  AndroidStartReport(this.isolatedTried, this.isolatedStarted, this.isolatedDetail, this.mode, this.detail);
  final bool isolatedTried;
  final bool isolatedStarted;
  final String isolatedDetail;

  /// `isolated` or `same-uid`: the service that finally runs the plugins.
  final String mode;
  final String detail;

  String get line =>
      'NOVA_ISOLATED=${isolatedStarted ? 'yes' : 'no'} detail="$isolatedDetail" running=$mode "$detail"';
}

/// A runner inside the Android `:nova` service (Chaquopy). Same NDJSON as the
/// desktop process, carried over a Messenger instead of pipes.
class AndroidNovaSession implements NovaSession {
  AndroidNovaSession._(this.limits) {
    _timer = Timer(limits.wall + const Duration(seconds: 3), () => kill('wall-timeout'));
  }

  static const MethodChannel _ch = MethodChannel('dev.chithram/nova_host');
  static AndroidNovaSession? _active;
  static AndroidStartReport? lastReport;
  static bool? _isolatedWorks; // null = not tried yet
  static String _isolatedDetail = 'not tried';
  static bool _wired = false;

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

  /// Tries the isolated service once per app run, then falls back to the plain `:nova` one.
  static Future<AndroidNovaSession> start({NovaLimits limits = const NovaLimits(), bool tryIsolated = true}) async {
    _wire();
    Map<Object?, Object?>? r;
    var mode = 'same-uid';
    if (tryIsolated && _isolatedWorks != false) {
      r = await _ch.invokeMapMethod<Object?, Object?>('start', {'isolated': true});
      _isolatedWorks = r?['started'] == true;
      _isolatedDetail = '${r?['detail']}';
      if (_isolatedWorks!) mode = 'isolated';
    }
    if (mode != 'isolated') {
      r = await _ch.invokeMapMethod<Object?, Object?>('start', {'isolated': false});
    }
    final started = r?['started'] == true;
    lastReport = AndroidStartReport(tryIsolated, _isolatedWorks == true, _isolatedDetail, mode, '${r?['detail']}');
    if (!started) throw StateError('Android Python service did not start: ${r?['detail']}');
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
