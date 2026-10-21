/// LocalSend v2 receiver, implemented from the public protocol description.
///
/// R0 skeleton: the types below are the surface the app builds against. The
/// server, discovery and certificate generation arrive in the receive work
/// package.
library;

import 'dart:async';
import 'dart:typed_data';

/// This device's identity: a self-signed certificate whose SHA-256 is the
/// fingerprint peers pin.
class LsIdentity {
  const LsIdentity({required this.fingerprint, required this.certificatePem, required this.privateKeyPem});

  /// Uppercase hex SHA-256 of the DER certificate.
  final String fingerprint;
  final String certificatePem;
  final String privateKeyPem;
}

class LsReceiverConfig {
  const LsReceiverConfig({
    this.alias = 'Chithram',
    this.deviceModel,
    this.deviceType = 'desktop',
    this.port = 53317,
    this.pin,
    this.allowLoopback = false,
  });

  final String alias;
  final String? deviceModel;

  /// "desktop" on TV and desktop, "mobile" on phones.
  final String deviceType;
  final int port;

  /// Optional 4-8 digit PIN; null means none.
  final String? pin;

  /// Tests only.
  final bool allowLoopback;
}

/// What a sender wants to deliver, shown to the user before anything is stored.
class LsOffer {
  const LsOffer({
    required this.senderAlias,
    required this.senderAddress,
    this.senderModel,
    required this.files,
  });

  final String senderAlias;
  final String senderAddress;
  final String? senderModel;
  final List<LsOfferedFile> files;
}

class LsOfferedFile {
  const LsOfferedFile({required this.id, required this.name, required this.size, required this.type, this.preview});

  final String id;
  final String name;
  final int size;
  final String type;

  /// The text of a message sent as a text file.
  final String? preview;
}

sealed class LsIncoming {
  const LsIncoming(this.fromAlias, this.fromAddress);

  final String fromAlias;
  final String fromAddress;
}

final class TextIncoming extends LsIncoming {
  const TextIncoming(this.text, super.fromAlias, super.fromAddress);

  final String text;
}

final class FileIncoming extends LsIncoming {
  const FileIncoming(this.name, this.bytes, super.fromAlias, super.fromAddress);

  final String name;
  final Uint8List bytes;
}

/// Receives LocalSend transfers while it is running.
class LsReceiver {
  LsReceiver({required this.identity, required this.config, required this.onOffer});

  final LsIdentity identity;
  final LsReceiverConfig config;

  /// Asked for every transfer; return false to reject it.
  final Future<bool> Function(LsOffer offer) onOffer;

  final _received = StreamController<LsIncoming>.broadcast();
  bool _running = false;

  bool get running => _running;
  Stream<LsIncoming> get received => _received.stream;

  Future<void> start() async => _running = true;

  Future<void> stop() async => _running = false;

  /// Sends the multicast announce burst (0, 0.5 and 2 s after start).
  Future<void> announce() async {}

  Future<void> dispose() async {
    await stop();
    await _received.close();
  }
}
