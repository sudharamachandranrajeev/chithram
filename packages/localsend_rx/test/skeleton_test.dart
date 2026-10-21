import 'package:localsend_rx/localsend_rx.dart';
import 'package:test/test.dart';

void main() {
  test('receiver starts and stops', () async {
    final rx = LsReceiver(
      identity: const LsIdentity(fingerprint: 'AB', certificatePem: '', privateKeyPem: ''),
      config: const LsReceiverConfig(),
      onOffer: (_) async => false,
    );
    await rx.start();
    expect(rx.running, isTrue);
    await rx.dispose();
    expect(rx.running, isFalse);
  });
}
