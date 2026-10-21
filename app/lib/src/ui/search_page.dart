import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'dims.dart';
import 'focus_card.dart';
import 'keyboard.dart';

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
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: SingleChildScrollView(
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
            OnScreenKeyboard(
              focus: widget.focus,
              onChar: _add,
              onBackspace: _backspace,
              onClear: _clear,
            ),
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
      ),
    );
  }
}
