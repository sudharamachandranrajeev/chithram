import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../features/youtube/feed/youtube_feed.dart';
import '../../features/youtube/youtube_results.dart';
import '../common/dims.dart';
import '../common/sections.dart';
import '../common/tokens.dart';
import '../common/video_billboard.dart';
import '../common/video_row.dart';
import '../tv/focus_card.dart';

export '../common/pill_button.dart' show DesktopPill;
export '../common/video_billboard.dart' show heroAutoAdvance;

/// How many cards a row shows at this window width: 4 from 1440, 3 from 1100.
int cardsPerRow(double width) => width >= 1440 ? 4 : (width >= 1100 ? 3 : 2);

/// Desktop Home: a hero billboard and rows of videos from the same feed the
/// TV and phone Home use (popular now, and, as Chithram learns, continue
/// watching and suggestions).
class DesktopHome extends StatefulWidget {
  const DesktopHome({super.key, required this.focus, required this.onOpenSection});

  final SectionFocus focus;

  /// "Browse YouTube" and "View all" go to a section.
  final void Function(Section) onOpenSection;

  @override
  State<DesktopHome> createState() => _DesktopHomeState();
}

class _DesktopHomeState extends State<DesktopHome> {
  @override
  void initState() {
    super.initState();
    // After the first frame: nothing on the startup path reads the network.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(AppServices.of(context).feed.open());
    });
  }

  @override
  Widget build(BuildContext context) {
    final feed = AppServices.of(context).feed;
    final d = Dims.of(context);
    final perRow = cardsPerRow(MediaQuery.sizeOf(context).width);
    return ValueListenableBuilder<FeedState>(
      valueListenable: feed.state,
      builder: (context, state, _) {
        final suggested = state.rails.any((r) => r.id == 'for-you');
        return SingleChildScrollView(
          key: const PageStorageKey<String>('desktop-home-scroll'),
          padding: EdgeInsets.fromLTRB(d.gutter, Space.s24, d.gutter, Space.s32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DesktopBillboard(
                key: const ValueKey('desktop-hero'),
                items: state.hero,
                kicker: suggested ? 'Recommended for you' : 'Popular on YouTube',
                kickerIcon: suggested ? Icons.auto_awesome_rounded : Icons.local_fire_department_rounded,
                error: state.error,
                playFocusNode: widget.focus.entry,
                onPlayFocused: () => widget.focus.remember(widget.focus.entry),
                onPlay: (v) => playVideo(context, v, source: suggested ? 'for-you' : null),
                onRetry: () => feed.refresh(force: true),
                secondaryLabel: 'Browse YouTube',
                secondaryIcon: Icons.arrow_forward_rounded,
                secondaryTrailing: true,
                onSecondary: (_) => widget.onOpenSection(Section.youtube),
              ),
              for (final rail in state.rails)
                VideoRow(
                  key: ValueKey('home-${rail.id}'),
                  rail: rail,
                  perRow: perRow,
                  focus: widget.focus,
                  onOpen: (v) => playVideo(context, v, source: rail.id),
                  onViewAll: () => widget.onOpenSection(Section.youtube),
                ),
            ],
          ),
        );
      },
    );
  }
}
