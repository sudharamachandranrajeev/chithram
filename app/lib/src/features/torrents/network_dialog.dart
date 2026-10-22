import 'package:flutter/material.dart';

import '../../ui/text_entry.dart';
import 'torrent_logic.dart';

/// Widget keys for the network-choice dialog, for tests.
abstract final class NetworkDialogKeys {
  static const socks5 = ValueKey('torrent-network-socks5');
  static const direct = ValueKey('torrent-network-direct');
}

enum _Pick { socks5, direct }

/// Asks how torrent traffic should leave the device and stores the answer in
/// [guard]. SOCKS5 needs a valid `socks5://host:port` that answers a 2 s TCP
/// probe. The dialog itself carries the IP-exposure warning for "without protection".
/// True when a choice was made, false when cancelled.
Future<bool> chooseNetwork(
  BuildContext context,
  NetworkGuard guard, {
  Future<bool> Function(Socks5Address) probe = probeSocks5,
}) async {
  String? error;
  while (true) {
    if (!context.mounted) return false;
    final pick = await showDialog<_Pick>(
      context: context,
      builder: (ctx) => _NetworkDialog(error: error),
    );
    if (pick == null || !context.mounted) return false;
    switch (pick) {
      case _Pick.direct:
        await guard.useDirect();
        return true;
      case _Pick.socks5:
        final text = await askText(
          context,
          title: 'SOCKS5 address',
          hint: 'socks5://host:port',
          initial: guard.rememberedAddress ?? 'socks5://127.0.0.1:1080',
        );
        if (text == null || !context.mounted) {
          error = null;
          continue;
        }
        final address = Socks5Address.tryParse(text);
        if (address == null) {
          error = 'That is not a SOCKS5 address. Use socks5://host:port.';
          continue;
        }
        if (!await probe(address)) {
          error = 'Nothing answered at ${address.host}:${address.port} within 2 seconds.';
          continue;
        }
        await guard.useSocks5(address.url);
        return true;
    }
  }
}

class _NetworkDialog extends StatelessWidget {
  const _NetworkDialog({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Protect your torrent traffic'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (error != null) ...[
              Text(error!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
            ],
            const Text(
              'Torrenting shows your IP address to every peer. Send it through a SOCKS5 proxy, '
              'for example the one your VPN provides.',
            ),
            const SizedBox(height: 12),
            const Text(
              'With SOCKS5, DHT and UDP trackers are off, so a magnet link needs trackers of its own.',
            ),
            const SizedBox(height: 12),
            const Text('Without protection, peers and anyone watching the swarm can see your IP address.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: NetworkDialogKeys.socks5,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(_Pick.socks5),
          child: const Text('Use SOCKS5'),
        ),
        TextButton(
          key: NetworkDialogKeys.direct,
          onPressed: () => Navigator.of(context).pop(_Pick.direct),
          child: const Text('Continue without protection'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}
