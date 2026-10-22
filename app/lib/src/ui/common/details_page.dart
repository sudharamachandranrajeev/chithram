import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'dims.dart';
import '../tv/focus_card.dart';
import '../tv/focus_rail.dart';
import '../tv/home_page.dart' show ActionLabel;

/// Opens the details placeholder over the shell. Back pops it, and focus
/// returns to the tile it was opened from.
Future<void> openDetails(BuildContext context, {required String title, required double hue}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => DetailsPage(title: title, hue: hue)),
  );
}

/// Details placeholder: backdrop, title, Play / Trailer / Add, episodes rail.
class DetailsPage extends StatefulWidget {
  const DetailsPage({super.key, required this.title, required this.hue});

  final String title;
  final double hue;

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  final _focus = SectionFocus();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.entry.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final hue = widget.hue % 360;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                HSLColor.fromAHSL(1, hue, 0.40, 0.28).toColor(),
                ChithramColors.surface,
                ChithramColors.background,
              ],
            ),
          ),
          child: Overscan(
            child: FocusScope(
              child: SingleChildScrollView(
                key: const PageStorageKey<String>('details-scroll'),
                padding: EdgeInsets.fromLTRB(d.phone ? 12 : 24, 24, d.phone ? 12 : 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: d.phone ? 40 : 56),
                    Text(widget.title, style: TextStyle(fontSize: d.t(40), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('2026  |  Placeholder  |  1 season',
                        style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14))),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Text(
                        'Synopsis placeholder. Metadata will come from your TMDB key.',
                        style: TextStyle(fontSize: d.t(14)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        FocusCard(
                          focusNode: _focus.entry,
                          section: _focus,
                          radius: 28,
                          onActivate: () {},
                          child: const ActionLabel(icon: Icons.play_arrow_rounded, text: 'Play', primary: true),
                        ),
                        FocusCard(
                          section: _focus,
                          radius: 28,
                          onActivate: () {},
                          child: const ActionLabel(icon: Icons.movie_outlined, text: 'Trailer'),
                        ),
                        FocusCard(
                          section: _focus,
                          radius: 28,
                          onActivate: () {},
                          child: const ActionLabel(icon: Icons.add_rounded, text: 'Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FocusRail(
                      title: 'Episodes',
                      count: 8,
                      section: _focus,
                      itemBuilder: (_, i) => PosterTile(label: 'S1 E${i + 1}', hue: hue + i * 8),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
