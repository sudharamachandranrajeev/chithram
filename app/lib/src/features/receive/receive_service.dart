import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:localsend_rx/localsend_rx.dart';

import '../../core/paths.dart';
import '../../core/prefs.dart';

enum ReceiveStatus { stopped, starting, listening, error }

class ReceiveState {
  const ReceiveState(this.status, {this.addresses = const [], this.error});

  final ReceiveStatus status;

  /// Private addresses the phone can type in when discovery is blocked.
  final List<String> addresses;
  final String? error;
}

/// Runs the LocalSend receiver while the Receive screen is open. Stub: no
/// server is started yet.
class ReceiveService {
  ReceiveService({required this.navigatorKey, required this.paths, required this.prefs});

  final GlobalKey<NavigatorState> navigatorKey;
  final AppPaths paths;
  final Prefs prefs;

  final _state = ValueNotifier(const ReceiveState(ReceiveStatus.stopped));
  LsReceiver? _receiver;

  ValueListenable<ReceiveState> get state => _state;

  Future<void> start() async {
    if (_receiver != null) return;
    // Placeholder identity until the certificate generation lands.
    _receiver = LsReceiver(
      identity: const LsIdentity(fingerprint: '', certificatePem: '', privateKeyPem: ''),
      config: const LsReceiverConfig(),
      onOffer: (_) async => false,
    );
    await _receiver!.start();
    _state.value = const ReceiveState(ReceiveStatus.listening);
  }

  Future<void> stop() async {
    await _receiver?.dispose();
    _receiver = null;
    _state.value = const ReceiveState(ReceiveStatus.stopped);
  }
}
