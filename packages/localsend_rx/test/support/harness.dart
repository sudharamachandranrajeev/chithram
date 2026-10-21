import 'dart:async';
import 'dart:io';

import 'package:localsend_rx/localsend_rx.dart';
import 'package:localsend_rx/testing.dart';

LsIdentity? _identity;

/// Key generation is slow: one identity for the whole test run.
Future<LsIdentity> sharedIdentity() async => _identity ??= await LsIdentity.generate();

/// A receiver on loopback with a scripted user.
class Harness {
  Harness._(this.rx, this.identity, this.offers, this.incoming);

  final LsReceiver rx;
  final LsIdentity identity;
  final List<LsOffer> offers;
  final List<LsIncoming> incoming;

  /// What the scripted user answers; may be replaced per test.
  static Future<Harness> start({
    String? pin,
    bool allowLoopback = true,
    Future<bool> Function(LsOffer)? onOffer,
    Duration promptTimeout = const Duration(seconds: 60),
    Duration sessionIdle = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) async {
    final identity = await sharedIdentity();
    final offers = <LsOffer>[];
    final incoming = <LsIncoming>[];
    final rx = LsReceiver(
      identity: identity,
      config: LsReceiverConfig(
        alias: 'Chithram test',
        deviceModel: 'Test box',
        pin: pin,
        port: 0,
        allowLoopback: allowLoopback,
        multicast: false,
        bindAddresses: [InternetAddress.loopbackIPv4],
        promptTimeout: promptTimeout,
        sessionIdle: sessionIdle,
        readTimeout: const Duration(seconds: 3),
      ),
      onOffer: (o) async {
        offers.add(o);
        return onOffer == null ? true : onOffer(o);
      },
      clock: clock,
    );
    rx.received.listen(incoming.add);
    await rx.start();
    return Harness._(rx, identity, offers, incoming);
  }

  LsTestSender sender({String? fingerprint}) =>
      LsTestSender(host: '127.0.0.1', port: rx.port!, fingerprint: fingerprint ?? identity.fingerprint);

  Future<void> close() => rx.dispose();
}
