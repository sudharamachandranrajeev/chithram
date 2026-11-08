import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services.dart';
import '../../../theme.dart';
import '../../../ui/common/dims.dart';
import '../../../ui/common/tokens.dart';
import 'youtube_home_keys.dart';

/// The YouTube search field for pointer and touch: a pill with live
/// suggestions dropping down under it as you type. Up and Down pick a
/// suggestion, Enter (or the IME's Search) opens results for it or for the
/// text, Escape closes the list. A TV uses its on-screen keyboard instead.
class YouTubeSearchField extends StatefulWidget {
  const YouTubeSearchField({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.focusNode,
    this.autofocus = false,
    this.height = 48,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final FocusNode? focusNode;
  final bool autofocus;
  final double height;

  /// How long typing must pause before suggestions are fetched.
  static const debounce = Duration(milliseconds: 180);

  @override
  State<YouTubeSearchField> createState() => _YouTubeSearchFieldState();
}

class _YouTubeSearchFieldState extends State<YouTubeSearchField> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  FocusNode? _own;
  Timer? _debounce;
  List<String> _suggestions = const [];
  int _highlight = -1;

  /// The prefix the shown suggestions are for; a late answer for an older
  /// prefix is dropped.
  String _asked = '';

  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'youtube search'));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_focusChanged);
    _own?.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _hide();
    if (mounted) setState(() {});
  }

  void _hide() {
    _debounce?.cancel();
    if (_portal.isShowing) _portal.hide();
    _highlight = -1;
  }

  void _changed(String text) {
    _debounce?.cancel();
    setState(() => _highlight = -1);
    final prefix = text.trim();
    if (prefix.isEmpty) {
      setState(() => _suggestions = const []);
      _hide();
      return;
    }
    _debounce = Timer(YouTubeSearchField.debounce, () => _fetch(prefix));
  }

  Future<void> _fetch(String prefix) async {
    _asked = prefix;
    final List<String> found;
    try {
      found = await AppServices.of(context).youtube.suggest(prefix);
    } catch (_) {
      return;
    }
    if (!mounted || prefix != _asked || prefix != widget.controller.text.trim()) return;
    setState(() => _suggestions = found.take(8).toList());
    if (_suggestions.isNotEmpty && _focus.hasFocus) {
      _portal.show();
    } else {
      _hide();
    }
  }

  void _submit(String text) {
    final q = text.trim();
    _hide();
    if (q.isEmpty) return;
    if (widget.controller.text != q) {
      widget.controller.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    }
    widget.onSubmit(q);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_portal.isShowing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      // Positions -1 (the typed text) and 0..n-1 (the suggestions), wrapping.
      final n = _suggestions.length;
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() => _highlight = (_highlight + 1 + step) % (n + 1) - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (_highlight >= 0) {
        _submit(_suggestions[_highlight]);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(_hide);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final d = Dims.of(context);
    final motion = Motion.of(context);
    final focused = _focus.hasFocus;
    final textStyle = d.type.body.copyWith(fontSize: d.phone ? 16 : 15);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _SuggestionList(
          link: _link,
          height: widget.height,
          suggestions: _suggestions,
          highlight: _highlight,
          onPick: _submit,
        ),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: AnimatedContainer(
            duration: motion.focusTime,
            curve: Motion.curve,
            height: widget.height,
            padding: const EdgeInsets.only(left: Space.s16, right: Space.s4),
            decoration: BoxDecoration(
              color: Color.alphaBlend(c.text.withValues(alpha: focused ? 0.1 : 0.06), c.surface),
              borderRadius: BorderRadius.circular(Radii.pill),
              boxShadow: [
                if (focused) BoxShadow(color: c.accent.withValues(alpha: 0.18), blurRadius: 18),
              ],
            ),
            // The border is painted over, not laid out: as padding it would
            // squeeze the Clear button under the 48 dp touch target.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: focused ? c.accent : c.text.withValues(alpha: 0.1), width: focused ? 2 : 1),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 22, color: focused ? c.accent : c.textDim),
                const SizedBox(width: Space.s12),
                Expanded(
                  child: TextField(
                    key: YouTubeHomeKeys.searchField,
                    controller: widget.controller,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    textInputAction: TextInputAction.search,
                    keyboardType: TextInputType.text,
                    style: textStyle,
                    cursorColor: c.accent,
                    decoration: InputDecoration.collapsed(
                      hintText: 'Search YouTube',
                      hintStyle: textStyle.copyWith(color: c.textDim),
                    ),
                    onChanged: _changed,
                    onSubmitted: _submit,
                  ),
                ),
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => widget.controller.text.isEmpty
                      ? const SizedBox(width: Space.s12)
                      : IconButton(
                          tooltip: 'Clear',
                          style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
                          onPressed: () {
                            widget.controller.clear();
                            _changed('');
                            _focus.requestFocus();
                          },
                          icon: Icon(Icons.close_rounded, size: 20, color: c.textDim),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.link,
    required this.height,
    required this.suggestions,
    required this.highlight,
    required this.onPick,
  });

  final LayerLink link;
  final double height;
  final List<String> suggestions;
  final int highlight;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final d = Dims.of(context);
    final width = link.leaderSize?.width ?? 480;
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      offset: Offset(0, height + Space.s8),
      child: Align(
        alignment: Alignment.topLeft,
        // Part of the field's tap region: a tap here must not unfocus the
        // field (which would close the list before the tap lands).
        child: TextFieldTapRegion(
          child: SizedBox(
            width: width,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Motion.of(context).expandTime,
              curve: Motion.curve,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, -8 * (1 - t)), child: child),
              ),
              child: Material(
                color: c.surfaceHigh,
                elevation: 12,
                shadowColor: Colors.black,
                borderRadius: BorderRadius.circular(Radii.panel),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, s) in suggestions.indexed)
                        InkWell(
                          key: YouTubeHomeKeys.suggestion(i),
                          onTap: () => onPick(s),
                          child: Container(
                            height: d.phone ? 48 : 40,
                            color: i == highlight ? c.text.withValues(alpha: 0.08) : null,
                            padding: const EdgeInsets.symmetric(horizontal: Space.s16),
                            child: Row(
                              children: [
                                Icon(Icons.search_rounded, size: 18, color: c.textDim),
                                const SizedBox(width: Space.s12),
                                Expanded(
                                  child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: d.type.body),
                                ),
                                Icon(Icons.north_west_rounded, size: 16, color: c.textDim),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
