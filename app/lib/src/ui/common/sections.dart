import 'package:flutter/material.dart';

/// The sections in the nav rail, in order.
enum Section {
  home('Home', Icons.home_rounded),
  search('Search', Icons.search_rounded),
  liveTv('Live TV', Icons.live_tv_rounded),
  torrents('Torrents', Icons.downloading_rounded),
  youtube('YouTube', Icons.smart_display_rounded),
  websites('Websites', Icons.public_rounded),
  settings('Settings', Icons.settings_rounded);

  const Section(this.label, this.icon);

  final String label;
  final IconData icon;
}
