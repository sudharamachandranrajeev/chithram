import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'dims.dart';
import 'focus_card.dart';

/// Search with an on-screen D-pad keyboard (a TextField is avoided on TV:
/// flutter/flutter#147772). On desktop, typing on a hardware keyboard also
/// works: letters, digits and Backspace.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  String _query = '';

  void _add(String c) => setState(() => _query += c);
  void _backspace() {
    if (_query.isNotEmpty) setState(() => _query = _query.substring(0, _query.length - 1));
  }

  void _clear() => setState(() => _query = '');

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && RegExp(r'^[a-zA-Z0-9]$').hasMatch(ch)) {
      _add(ch.toLowerCase());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final pad = d.phone ? 12.0 : 28.0;
    final key = d.phone ? 44.0 : d.u(52);
    const gap = 8.0;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, box) {
        final cols = ((box.maxWidth - pad * 2) / (key + 5 + gap)).floor().clamp(6, 12);
        final rows = <List<String>>[
          for (var i = 0; i < _chars.length; i += cols)
            [for (var j = i; j < i + cols && j < _chars.length; j++) _chars[j]],
        ];
        var first = true;
        Widget keyCard(Widget child, VoidCallback onTap, {double? width, String? id}) {
          final card = FocusCard(
            key: id == null ? null : ValueKey('key-$id'),
            focusNode: first ? widget.focus.entry : null,
            section: widget.focus,
            radius: 12,
            onActivate: onTap,
            child: Container(
              width: width ?? key,
              height: key,
              alignment: Alignment.center,
              color: ChithramColors.surfaceHigh,
              child: child,
            ),
          );
          first = false;
          return card;
        }

        final keyboard = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in row)
                      Padding(
                        padding: const EdgeInsets.only(right: gap),
                        child: keyCard(
                          Text(c, style: TextStyle(fontSize: d.t(16), fontWeight: FontWeight.w600)),
                          () => _add(c),
                          id: c,
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: gap),
                  child: keyCard(Icon(Icons.space_bar_rounded, size: d.t(24)), () => _add(' '),
                      width: key * 2 + gap + 5, id: 'space'),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: gap),
                  child: keyCard(Icon(Icons.backspace_outlined, size: d.t(24)), _backspace,
                      width: key * 2 + gap + 5, id: 'backspace'),
                ),
                keyCard(Text('Clear', style: TextStyle(fontSize: d.t(16), fontWeight: FontWeight.w600)), _clear,
                    width: key * 2 + gap + 5, id: 'clear'),
              ],
            ),
          ],
        );

        return SingleChildScrollView(
          key: const PageStorageKey<String>('search-scroll'),
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Search', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
              Text('Unified search across your sources.',
                  style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14))),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: ChithramColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ChithramColors.surfaceHigh),
                ),
                child: Stack(
                  children: [
                    if (_query.isEmpty)
                      Text('Type a title', style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(18))),
                    Text(_query,
                        key: const ValueKey('search-query'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: d.t(18), fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              keyboard,
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: ChithramColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _query.isEmpty ? 'Results appear here.' : 'Results for "$_query" appear here.',
                  style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
