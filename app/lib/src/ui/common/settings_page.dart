import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/images/cache_settings.dart';
import '../../features/metadata/metadata_settings.dart';
import '../../features/receive/receive_settings.dart';
import '../../features/torrents/torrent_settings.dart';
import '../../find/torznab/torznab_settings.dart';
import '../../plugins/ui/plugins_settings.dart';
import '../../theme.dart';
import 'dims.dart';
import '../tv/focus_card.dart';
import '../tv/home_page.dart' show ActionLabel;
import 'interface_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Padding(
      padding: EdgeInsets.all(d.phone ? 16 : 32),
      child: SingleChildScrollView(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Settings', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Chithram ships no sources. You add your own.',
            style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
          ),
          const SizedBox(height: 28),
          // The first section takes the page's entry node.
          TorrentSettings(entry: focus),
          const MetadataSettings(),
          const PluginsSettings(),
          const TorznabSettings(),
          const CacheSettings(),
          const ReceiveSettings(),
          const InterfaceSettings(),
          const AboutSettings(),
        ],
      ),
      ),
    );
  }
}

/// The version, read from the platform (blank where that is unavailable).
class AboutSettings extends StatelessWidget {
  const AboutSettings({super.key});

  static Future<String> _version() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FocusCard(
        radius: 24,
        onActivate: () {},
        child: FutureBuilder<String>(
          future: _version(),
          builder: (context, snap) => ActionLabel(text: 'About Chithram ${snap.data ?? ''}'.trim()),
        ),
      ),
    );
  }
}
