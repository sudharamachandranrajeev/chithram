import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'transport.dart';

typedef _CreateC = Int32 Function();
typedef _CreateD = int Function();
typedef _SendC = Void Function(Int32, Pointer<Utf8>);
typedef _SendD = void Function(int, Pointer<Utf8>);
typedef _ReceiveC = Pointer<Utf8> Function(Double);
typedef _ReceiveD = Pointer<Utf8> Function(double);
typedef _ExecuteC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ExecuteD = Pointer<Utf8> Function(Pointer<Utf8>);

/// Thrown when TDLib's library is not in this build.
class TdUnavailable implements Exception {
  const TdUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Opens libtdjson for this platform. CHITHRAM_TDLIB_LIB overrides the path
/// (tests, dev). Throws [TdUnavailable] when it is not there.
DynamicLibrary openTdLibrary() {
  final override = Platform.environment['CHITHRAM_TDLIB_LIB'];
  try {
    if (override != null && override.isNotEmpty) return DynamicLibrary.open(override);
    if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('libtdjson.so');
    if (Platform.isWindows) return DynamicLibrary.open('tdjson.dll');
  } on ArgumentError catch (e) {
    throw TdUnavailable('This build has no TDLib: ${e.message}');
  }
  throw const TdUnavailable('Telegram is not available on this platform.');
}

/// Runs `td_receive` forever in its own isolate (it blocks) and forwards each
/// decoded JSON string. `td_send` is thread safe and is called from the
/// caller's isolate.
class NativeTdTransport implements TdTransport {
  NativeTdTransport._(this._clientId, this._send, this._isolate, this._stop) {
    _router = TdRequestRouter(_sendJson);
  }

  /// Starts the receive isolate and creates the TDLib client. [logVerbosity]
  /// is TDLib's own log level (1 = errors; it logs to stderr).
  static Future<NativeTdTransport> open({int logVerbosity = 1}) async {
    final lib = openTdLibrary();
    final create = lib.lookupFunction<_CreateC, _CreateD>('td_create_client_id');
    final send = lib.lookupFunction<_SendC, _SendD>('td_send');
    final execute = lib.lookupFunction<_ExecuteC, _ExecuteD>('td_execute');
    final verbosity = jsonEncode({'@type': 'setLogVerbosityLevel', 'new_verbosity_level': logVerbosity}).toNativeUtf8();
    try {
      execute(verbosity);
    } finally {
      malloc.free(verbosity);
    }
    final id = create();
    final inbox = ReceivePort();
    final ready = Completer<SendPort>();
    late final NativeTdTransport t;
    final isolate = await Isolate.spawn(_receiveLoop, (inbox.sendPort, Platform.environment['CHITHRAM_TDLIB_LIB']));
    inbox.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is String) {
        t._deliver(m);
      }
    });
    final stop = await ready.future;
    t = NativeTdTransport._(id, send, isolate, stop);
    t._inbox = inbox;
    return t;
  }

  final int _clientId;
  final _SendD _send;
  final Isolate _isolate;
  final SendPort _stop;
  late final ReceivePort _inbox;
  late final TdRequestRouter _router;
  bool _closed = false;

  @override
  Stream<Map<String, dynamic>> get updates => _router.updates;

  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> request) => _router.request(request);

  void _sendJson(Map<String, dynamic> request) {
    if (_closed) return;
    final p = jsonEncode(request).toNativeUtf8();
    try {
      _send(_clientId, p);
    } finally {
      malloc.free(p);
    }
  }

  void _deliver(String json) {
    try {
      final o = jsonDecode(json);
      if (o is Map<String, dynamic>) _router.handle(o);
    } on FormatException {
      // TDLib only sends JSON; ignore anything else.
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _stop.send('stop');
    _router.close();
    // The loop notices the flag within its 1 s poll; the kill is the backstop.
    Timer(const Duration(seconds: 3), () {
      _isolate.kill(priority: Isolate.immediate);
      _inbox.close();
    });
  }
}

/// The isolate: `td_receive(1.0)` in a loop. A null result is a timeout.
Future<void> _receiveLoop((SendPort, String?) args) async {
  final (out, override) = args;
  final lib = (override != null && override.isNotEmpty)
      ? DynamicLibrary.open(override)
      : (Platform.isWindows ? DynamicLibrary.open('tdjson.dll') : DynamicLibrary.open('libtdjson.so'));
  final receive = lib.lookupFunction<_ReceiveC, _ReceiveD>('td_receive');
  final control = ReceivePort();
  var running = true;
  control.listen((_) => running = false);
  out.send(control.sendPort);
  while (running) {
    final p = receive(1.0);
    if (p != nullptr) out.send(p.toDartString()); // valid until the next td_receive: copied now
    // Lets the stop message in.
    await Future<void>.delayed(Duration.zero);
  }
  control.close();
}
