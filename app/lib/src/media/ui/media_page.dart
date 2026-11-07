import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/tokens.dart';
import '../../ui/tv/focus_card.dart';
import '../media_service.dart';
import '../models.dart';
import 'downloads_view.dart';
import 'library_view.dart';
import 'media_widgets.dart';
import 'pairing_view.dart';
import 'requests_view.dart';
import 'search_view.dart';

enum MediaTab {
  search('Search', Icons.search_rounded),
  requests('Requests', Icons.playlist_add_check_rounded),
  downloads('Downloads', Icons.downloading_rounded),
  library('Library', Icons.video_library_rounded),
  server('Server', Icons.dns_rounded);

  const MediaTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The tabs this role sees: Downloads is admin only on the server.
List<MediaTab> tabsFor(MediaRole? role) => [
      for (final t in MediaTab.values)
        if (t != MediaTab.downloads || (role?.canSeeDownloads ?? false)) t,
    ];

/// The Media section (desktop and TV: a page of the shell; phone: pushed from
/// the top bar). While the flag is off it builds nothing and starts nothing.
class MediaPage extends StatefulWidget {
  const MediaPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  MediaTab _tab = MediaTab.search;
  MediaService? _service;
  String? _meError;
  bool _meBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppServices.of(context).media;
    if (!identical(s, _service)) {
      _service?.removeListener(_changed);
      _service = s..addListener(_changed);
      if (s.enabled) unawaited(s.load());
    }
  }

  @override
  void dispose() {
    _service?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final s = _service!;
    if (s.enabled && !s.loaded) unawaited(s.load());
    if (!s.paired) _meError = null;
    if (mounted) setState(() {});
    _ensureMe();
  }

  void _ensureMe() {
    final s = _service!;
    // After a failure wait for the user's "Try again": no retry loop.
    if (!s.paired || s.me != null || _meBusy || _meError != null) return;
    _meBusy = true;
    s.refreshMe().then<void>((_) {
      _meError = null;
    }, onError: (Object e) {
      _meError = mediaErrorText(e);
    }).whenComplete(() {
      _meBusy = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _service!;
    // Flag off: nothing at all.
    if (!s.enabled) return const SizedBox.shrink();
    final d = Dims.of(context);
    Widget body;
    if (!s.loaded) {
      body = const MediaMessage(icon: Icons.hourglass_empty_rounded, text: 'Loading…', busy: true);
    } else if (!s.paired) {
      body = PairingView(service: s, focus: widget.focus);
    } else if (s.me == null) {
      if (_meError == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureMe();
        });
      }
      body = _meError == null
          ? const MediaMessage(icon: Icons.hourglass_empty_rounded, text: 'Contacting the media server…', busy: true)
          : MediaMessage(
              icon: Icons.error_outline_rounded,
              text: _meError!,
              actionLabel: 'Try again',
              focusNode: widget.focus.entry,
              onAction: () {
                _meError = null;
                _ensureMe();
                setState(() {});
              },
            );
    } else {
      return _Paired(
        service: s,
        focus: widget.focus,
        tab: _tab,
        onTab: (t) => setState(() => _tab = t),
      );
    }
    if (d.phone) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(d.gutter, d.gutter, d.gutter, 0),
          child: Text('Media', style: d.type.hero),
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _Paired extends StatelessWidget {
  const _Paired({required this.service, required this.focus, required this.tab, required this.onTab});

  final MediaService service;
  final SectionFocus focus;
  final MediaTab tab;
  final ValueChanged<MediaTab> onTab;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final tabs = tabsFor(service.role);
    final current = tabs.contains(tab) ? tab : MediaTab.search;
    final Widget view = KeyedSubtree(
      key: ValueKey('media-view-${current.name}'),
      child: switch (current) {
        MediaTab.search => SearchView(service: service, focus: focus),
        MediaTab.requests => RequestsView(service: service, focus: focus),
        MediaTab.downloads => DownloadsView(service: service, focus: focus),
        MediaTab.library => LibraryView(service: service, focus: focus),
        MediaTab.server => MediaServerView(service: service, focus: focus),
      },
    );
    if (d.phone) {
      // One hand: the tabs are at the bottom, within thumb reach.
      return Column(
        children: [
          Expanded(child: view),
          DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: ChithramColors.of(context).hairline))),
            child: NavigationBar(
              selectedIndex: tabs.indexOf(current),
              onDestinationSelected: (i) => onTab(tabs[i]),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final t in tabs)
                  NavigationDestination(
                    key: ValueKey('media-tab-${t.name}'),
                    icon: Icon(t.icon),
                    label: t.label,
                  ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(d.gutter, d.gutter, d.gutter, 0),
          child: Text('Media', style: d.type.hero),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: d.gutter - Space.s4),
          child: Wrap(
            children: [
              for (final (i, t) in tabs.indexed)
                MediaButton(
                  key: ValueKey('media-tab-${t.name}'),
                  label: t.label,
                  icon: t.icon,
                  primary: t == current,
                  focusNode: i == 0 ? focus.entry : null,
                  section: focus,
                  onPressed: () => onTab(t),
                ),
            ],
          ),
        ),
        Expanded(child: view),
      ],
    );
  }
}

/// The phone's page: pushed from the top bar's Media button. Closes itself
/// when Media is switched off.
class PhoneMediaRoute extends StatelessWidget {
  const PhoneMediaRoute({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    final media = AppServices.of(context).media;
    return ListenableBuilder(
      listenable: media,
      builder: (context, _) {
        if (!media.enabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Media')),
          body: SafeArea(child: MediaPage(focus: focus)),
        );
      },
    );
  }
}

/// The phone top bar's Media button. Nothing at all while the flag is off.
class MediaEntryButton extends StatelessWidget {
  const MediaEntryButton({super.key, required this.focus});

  final SectionFocus focus;

  @override
  Widget build(BuildContext context) {
    final prefs = AppServices.of(context).prefs;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        if (!AppServices.of(context).media.enabled) return const SizedBox.shrink();
        return IconButton(
          key: const ValueKey('nav-media'),
          tooltip: 'Media',
          icon: const Icon(Icons.perm_media_rounded),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => PhoneMediaRoute(focus: focus)),
          ),
        );
      },
    );
  }
}
