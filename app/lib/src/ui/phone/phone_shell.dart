import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/livetv/livetv_page.dart';
import '../../features/torrents/torrents_page.dart';
import '../../features/websites/websites_page.dart';
import '../../features/youtube/youtube_page.dart';
import '../tv/focus_card.dart';
import '../common/form_factor.dart';
import 'phone_home.dart';
import '../common/search_page.dart';
import '../common/sections.dart';
import '../common/settings_page.dart';

/// The sections in the bottom bar (or the tablet rail); Websites and Settings are
/// in the top bar. At most five: more go into a "More" sheet from 0.4.0.
const _tabs = [
  Section.home,
  Section.search,
  Section.liveTv,
  Section.youtube,
  Section.torrents,
];

/// Frame for a phone or tablet: a top bar with the Settings gear, the current
/// section, and a Material 3 navigation bar at the bottom (a rail on tablets).
/// Back goes to Home from another tab, and leaves the app from Home.
class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key});

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> {
  int _index = 0;
  final _sections = [for (final _ in Section.values) SectionFocus()];

  @override
  void dispose() {
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  Widget _page(Section section) {
    final focus = _sections[section.index];
    switch (section) {
      case Section.home:
        return const PhoneHome();
      case Section.search:
        return SearchPage(focus: focus);
      case Section.settings:
        return SettingsPage(focus: focus);
      case Section.liveTv:
        return LiveTvPage(focus: focus);
      case Section.torrents:
        return TorrentsPage(focus: focus);
      case Section.youtube:
        return YouTubePage(focus: focus);
      case Section.websites:
        return WebsitesPage(focus: focus);
    }
  }

  void _select(int i) => setState(() => _index = i);

  /// Websites has no tab (the bar holds five); it opens from the top bar.
  void _openWebsites() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Websites')),
          body: SafeArea(child: WebsitesPage(focus: _sections[Section.websites.index])),
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: SafeArea(child: SettingsPage(focus: _sections[Section.settings.index])),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tablet = OrientationPolicy.isTablet(MediaQuery.sizeOf(context).shortestSide);
    final content = Stack(
      children: [
        for (var i = 0; i < _tabs.length; i++)
          Offstage(
            offstage: i != _index,
            child: ExcludeFocus(
              excluding: i != _index,
              child: FocusScope(child: _page(_tabs[i])),
            ),
          ),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          _select(0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chithram'),
          actions: [
            IconButton(
              key: const ValueKey('nav-websites'),
              tooltip: 'Websites',
              icon: Icon(Section.websites.icon),
              onPressed: _openWebsites,
            ),
            IconButton(
              key: const ValueKey('nav-settings'),
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_rounded),
              onPressed: _openSettings,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: tablet
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: _select,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final s in _tabs)
                          NavigationRailDestination(
                            icon: Icon(s.icon, key: ValueKey('nav-${s.name}')),
                            label: Text(s.label),
                          ),
                      ],
                    ),
                    Expanded(child: content),
                  ],
                )
              : content,
        ),
        bottomNavigationBar: tablet
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: [
                  for (final s in _tabs)
                    NavigationDestination(
                      key: ValueKey('nav-${s.name}'),
                      icon: Icon(s.icon),
                      label: s.label,
                    ),
                ],
              ),
      ),
    );
  }
}
