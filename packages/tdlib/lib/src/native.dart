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

/// TDLib over `td_json_client`. `td_send` is thread safe and is called from the
/// caller's isolate; answers arrive through the shared receive isolate.
class NativeTdTransport implements TdTransport {
  NativeTdTransport._(this._clientId, this._send, this._receiver) {
    _router = TdRequestRouter(_sendJson);
    _receiver.register(_clientId, _router.handle);
  }

  /// Creates a TDLib client. [logVerbosity] is TDLib's own log level
  /// (1 = errors; it logs to stderr).
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
    final receiver = await _SharedReceiver.get();
    return NativeTdTransport._(create(), send, receiver);
  }

  final int _clientId;
  final _SendD _send;
  final _SharedReceiver _receiver;
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

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _receiver.unregister(_clientId);
    _router.close();
  }
}

/// The one `td_receive` loop of the process. TDLib forbids two threads in
/// `td_receive` at once, so every client shares this isolate: it forwards each
/// JSON string, and the main isolate routes it by `@client_id`. It lives for
/// the rest of the process (the call blocks; an idle poll costs nothing).
class _SharedReceiver {
  _SharedReceiver._();

  static Future<_SharedReceiver>? _starting;
  static Future<_SharedReceiver> get() => _starting ??= _start();

  static Future<_SharedReceiver> _start() async {
    final r = _SharedReceiver._();
    final inbox = ReceivePort();
    await Isolate.spawn(_receiveLoop, (inbox.sendPort, Platform.environment['CHITHRAM_TDLIB_LIB']));
    inbox.listen((m) {
      if (m is String) r._route(m);
    });
    return r;
  }

  final _clients = <int, void Function(Map<String, dynamic>)>{};

  void register(int id, void Function(Map<String, dynamic>) sink) => _clients[id] = sink;
  void unregister(int id) => _clients.remove(id);

  void _route(String json) {
    try {
      final o = jsonDecode(json);
      if (o is! Map<String, dynamic>) return;
      _clients[(o['@client_id'] as num?)?.toInt()]?.call(o);
    } on FormatException {
      // TDLib only sends JSON; ignore anything else.
    }
  }
}

/// The isolate: `td_receive(1.0)` in a loop. A null result is a timeout.
Future<void> _receiveLoop((SendPort, String?) args) async {
  final (out, override) = args;
  final lib = (override != null && override.isNotEmpty)
      ? DynamicLibrary.open(override)
      : (Platform.isWindows ? DynamicLibrary.open('tdjson.dll') : DynamicLibrary.open('libtdjson.so'));
  final receive = lib.lookupFunction<_ReceiveC, _ReceiveD>('td_receive');
  while (true) {
    final p = receive(1.0);
    if (p != nullptr) out.send(p.toDartString()); // valid until the next td_receive: copied now
    await Future<void>.delayed(Duration.zero);
  }
}
