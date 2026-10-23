import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/receive/phone/phone_receive_settings.dart';
import '../../features/torrents/phone/phone_torrent_settings.dart';
import 'phone_widgets.dart';

/// Settings on a phone: Material 3 list tiles in titled groups.
class PhoneSettings extends StatelessWidget {
  const PhoneSettings({super.key});

  static Future<String> _version() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const PhoneNote('Chithram ships no sources. You add your own.'),
        const PhoneSectionTitle('Torrents'),
        const PhoneTorrentSettings(),
        const PhoneSectionTitle('Receive'),
        const PhoneReceiveSettings(),
        const PhoneSectionTitle('About'),
        FutureBuilder<String>(
          future: _version(),
          builder: (context, snap) => ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('About Chithram'),
            subtitle: Text(snap.data == null || snap.data!.isEmpty ? 'Version unknown' : 'Version ${snap.data}'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Chithram',
              applicationVersion: snap.data,
            ),
          ),
        ),
      ],
    );
  }
}
