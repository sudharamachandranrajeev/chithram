import 'dart:io';
import 'dart:typed_data';

class LsReceiverConfig {
  const LsReceiverConfig({
    this.alias = 'Chithram',
    this.deviceModel,
    this.deviceType = 'desktop',
    this.port = 53317,
    this.pin,
    this.allowLoopback = false,
    this.multicast = true,
    this.bindAddresses,
    this.promptTimeout = const Duration(seconds: 60),
    this.sessionIdle = const Duration(minutes: 2),
    this.readTimeout = const Duration(seconds: 20),
  });

  final String alias;
  final String? deviceModel;

  /// "desktop" on TV and desktop, "mobile" on phones.
  final String deviceType;
  final int port;

  /// Optional 4-8 digit PIN; null means none.
  final String? pin;

  /// Tests only: also accept loopback peers.
  final bool allowLoopback;

  /// Join the multicast group and announce. Off for tests that only need HTTP.
  final bool multicast;

  /// Tests only: bind exactly these addresses instead of the private
  /// interfaces.
  final List<InternetAddress>? bindAddresses;

  /// How long the user has to answer a transfer prompt before it is refused.
  final Duration promptTimeout;

  /// An accepted transfer ends when no upload arrives for this long.
  final Duration sessionIdle;

  /// Longest pause tolerated while a request body is being read.
  final Duration readTimeout;
}

/// What a sender wants to deliver, shown to the user before anything is stored.
/// Lists only the files Chithram is willing to take.
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

/// The receiver could not start (no private address, or the port is in use).
class LsBindException implements Exception {
  const LsBindException(this.message);

  final String message;

  @override
  String toString() => message;
}
