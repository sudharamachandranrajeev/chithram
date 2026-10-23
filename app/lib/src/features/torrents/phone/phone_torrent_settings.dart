import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services.dart';

/// The torrent network choice as a list tile (changing it restarts the engine).
class PhoneTorrentSettings extends StatelessWidget {
  const PhoneTorrentSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).torrents;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => ListTile(
        minTileHeight: 56,
        leading: const Icon(Icons.shield_outlined),
        title: const Text('Torrent network'),
        subtitle: Text(service.guard.choice.label),
        onTap: () => unawaited(service.changeNetworkChoice(context)),
      ),
    );
  }
}
