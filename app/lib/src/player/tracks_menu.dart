import 'package:chithram_player/chithram_player.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui/common/dims.dart';
import '../ui/tv/focus_card.dart';
import 'player_keys.dart';
import 'tracks.dart';

/// Audio and subtitle choices: a panel at the right edge on a TV or desktop
/// (D-pad focus starts on the playing audio track), a bottom sheet's body on
/// a phone. Picking an entry calls back; the caller closes the menu.
class TracksMenu extends StatefulWidget {
  const TracksMenu({
    super.key,
    required this.audio,
    required this.subtitles,
    required this.onAudio,
    required this.onSubtitle,
    this.sheet = false,
  });

  final List<MediaTrack> audio;
  final List<MediaTrack> subtitles;
  final void Function(MediaTrack track) onAudio;

  /// Null turns subtitles off.
  final void Function(MediaTrack? track) onSubtitle;

  /// True inside a phone's bottom sheet: no panel chrome, no initial focus.
  final bool sheet;

  @override
  State<TracksMenu> createState() => _TracksMenuState();
}

class _TracksMenuState extends State<TracksMenu> {
  final _first = FocusNode(debugLabel: 'tracks menu first');

  @override
  void initState() {
    super.initState();
    if (!widget.sheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _first.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final audio = widget.audio, subs = widget.subtitles;
    final subOn = subs.any((t) => t.selected);
    // Focus starts on what plays now.
    final firstAudio = audio.indexWhere((t) => t.selected);
    final focusAudio = audio.isEmpty ? -1 : (firstAudio < 0 ? 0 : firstAudio);
    final list = ListView(
      key: PlayerKeys.tracksMenu,
      shrinkWrap: widget.sheet,
      padding: EdgeInsets.symmetric(vertical: d.u(16), horizontal: d.u(12)),
      children: [
        if (audio.isNotEmpty) ...[
          _Heading('Audio'),
          for (final (i, t) in audio.indexed)
            _Entry(
              key: PlayerKeys.audioTrack(t.id),
              title: trackTitle(t, i),
              detail: trackDetail(t),
              selected: t.selected,
              focusNode: i == focusAudio ? _first : null,
              onTap: () => widget.onAudio(t),
            ),
          SizedBox(height: d.u(12)),
        ],
        _Heading('Subtitles'),
        _Entry(
          key: PlayerKeys.subtitlesOff,
          title: 'Off',
          detail: '',
          selected: !subOn,
          focusNode: focusAudio < 0 ? _first : null,
          onTap: () => widget.onSubtitle(null),
        ),
        for (final (i, t) in subs.indexed)
          _Entry(
            key: PlayerKeys.subtitleTrack(t.id),
            title: trackTitle(t, i),
            detail: trackDetail(t),
            selected: t.selected,
            onTap: () => widget.onSubtitle(t),
          ),
        if (subs.isEmpty)
          Padding(
            padding: EdgeInsets.all(d.u(12)),
            child: Text(
              'None in this video',
              style: TextStyle(
                color: ChithramColors.of(context).textDim,
                fontSize: d.t(14),
              ),
            ),
          ),
      ],
    );
    if (widget.sheet) return SafeArea(child: list);
    return Align(
      alignment: Alignment.centerRight,
      // Taps on the panel stay on it (a tap beside it closes the menu).
      child: GestureDetector(
        onTap: () {},
        child: FocusScope(
          child: Container(
            width: d.tv ? 560 : 380,
            height: double.infinity,
            color: ChithramColors.of(context).surface.withValues(alpha: 0.96),
            child: list,
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(d.u(12), d.u(8), d.u(12), d.u(6)),
      child: Text(
        text,
        style: TextStyle(
          color: ChithramColors.of(context).textDim,
          fontSize: d.t(14),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.focusNode,
  });

  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: d.u(3)),
      child: FocusCard(
        focusNode: focusNode,
        radius: 12,
        onActivate: onTap,
        child: Container(
          color: selected ? ChithramColors.of(context).surfaceHigh : Colors.transparent,
          padding: EdgeInsets.symmetric(horizontal: d.u(12), vertical: d.u(9)),
          child: Row(
            children: [
              SizedBox(
                width: d.t(28),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        color: ChithramColors.of(context).accent,
                        size: d.t(22),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: d.t(16),
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ChithramColors.of(context).textDim,
                          fontSize: d.t(13),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
