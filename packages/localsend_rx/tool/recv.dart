// Loopback receiver for the interop job and manual checks:
//   dart run tool/recv.dart (--loopback | --bind <private ip>) --auto-accept [--port 53317] [--pin 1234]
// With neither flag it listens on every private address and announces itself.
// Prints one line per received item (`TEXT <text>` or `FILE <name> <bytes>`) and
// `READY <fingerprint>` once it listens. Test tool; not part of the app.
import 'dart:io';

import 'package:localsend_rx/localsend_rx.dart';

Future<void> main(List<String> args) async {
  final loopback = args.contains('--loopback');
  final auto = args.contains('--auto-accept');
  String? opt(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final bind = opt('--bind');
  final port = int.tryParse(opt('--port') ?? '') ?? 53317;
  final dir = Directory(opt('--identity-dir') ?? '${Directory.systemTemp.path}/localsend_rx_tool');
  final identity = await LsIdentity.loadOrCreate(dir);
  final rx = LsReceiver(
    identity: identity,
    config: LsReceiverConfig(
      alias: 'Chithram test receiver',
      port: port,
      pin: opt('--pin'),
      allowLoopback: loopback,
      bindAddresses: loopback
          ? [InternetAddress.loopbackIPv4]
          : bind == null
              ? null
              : [InternetAddress(bind)],
      multicast: !loopback && bind == null,
    ),
    onOffer: (offer) async {
      stdout.writeln('OFFER from ${offer.senderAlias} (${offer.senderAddress}): '
          '${offer.files.map((f) => f.name).join(', ')}');
      return auto;
    },
  );
  rx.received.listen((i) {
    switch (i) {
      case TextIncoming(:final text):
        stdout.writeln('TEXT $text');
      case FileIncoming(:final name, :final bytes):
        stdout.writeln('FILE $name ${bytes.length}');
    }
  });
  await rx.start();
  stdout.writeln('READY ${identity.fingerprint} ${rx.addresses.map((a) => a.address).join(',')}:${rx.port}');
  await ProcessSignal.sigint.watch().first;
  await rx.dispose();
}
