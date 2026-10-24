import 'dart:async';

import 'models.dart';

/// TDLib's JSON interface: send a request object, get every response and
/// update back as objects. [NativeTdTransport] (native.dart) is the real one;
/// tests script a fake.
abstract interface class TdTransport {
  /// Every object TDLib sends that is not the answer to [request].
  Stream<Map<String, dynamic>> get updates;

  /// Sends [request] and completes with TDLib's answer; a TDLib `error`
  /// object throws a [TdError].
  Future<Map<String, dynamic>> request(Map<String, dynamic> request);

  /// Stops delivering and fails every request still waiting.
  void close();
}

/// Matches answers to requests by `@extra` over a raw send/receive pair.
/// Shared by the native transport and by tests.
class TdRequestRouter {
  TdRequestRouter(this._send);

  final void Function(Map<String, dynamic> request) _send;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _updates = StreamController<Map<String, dynamic>>.broadcast();
  int _next = 1;

  Stream<Map<String, dynamic>> get updates => _updates.stream;

  Future<Map<String, dynamic>> request(Map<String, dynamic> body) {
    final id = _next++;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _send({...body, '@extra': id});
    return c.future;
  }

  /// Feed every object TDLib produced.
  void handle(Map<String, dynamic> obj) {
    final extra = obj['@extra'];
    if (extra is int) {
      final c = _pending.remove(extra);
      if (c != null) {
        if (obj['@type'] == 'error') {
          c.completeError(TdError.fromJson(obj));
        } else {
          c.complete(obj);
        }
        return;
      }
    }
    if (!_updates.isClosed) _updates.add(obj);
  }

  void close() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(const TdError(500, 'TDLib closed'));
    }
    _pending.clear();
    _updates.close();
  }
}
