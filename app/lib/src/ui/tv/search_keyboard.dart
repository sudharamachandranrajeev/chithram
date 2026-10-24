import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../common/dims.dart';
import '../common/sfx.dart';
import 'dpad.dart';

/// Opens the search keyboard: a frosted panel that drops down from [anchor]
/// (the search bar's rect on screen). Typing changes [query] at once.
/// Suggestions for the text so far come from [suggest]; picking one, or the
/// Search key, closes the panel and calls [onSubmit]. Back closes it and keeps
/// the text.
///
/// Key ids (what the tests tap): `key-<char>`, `key-space`, `key-backspace`,
/// `key-clear`, `key-mode` (letters / symbols), `search-go` and
/// `suggestion-<i>`.
Future<void> showSearchKeyboard(
  BuildContext context, {
  required Rect anchor,
  required ValueNotifier<String> query,
  required Future<List<String>> Function(String prefix) suggest,
  required VoidCallback onSubmit,
}) async {
  unawaited(preloadSfx(context));
  playSfx(context, Sfx.open);
  final submitted = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close keyboard',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, _, _) => _KeyboardLayout(
      anchor: anchor,
      child: _KeyboardPanel(query: query, suggest: suggest),
    ),
    // The panel unrolls downwards from the bar and fades in.
    transitionBuilder: (context, animation, _, child) {
      final t = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: t,
        child: AnimatedBuilder(
          animation: t,
          builder: (context, child) => ClipRect(
            child: Align(alignment: Alignment.topCenter, heightFactor: 0.6 + 0.4 * t.value, child: child),
          ),
          child: child,
        ),
      );
    },
  );
  if (!context.mounted) return;
  if (submitted == true) {
    playSfx(context, Sfx.submit);
    onSubmit();
  } else {
    playSfx(context, Sfx.close);
  }
}

/// Places the panel under the bar, as wide as the bar, in the room between
/// the bar and the bottom of the screen.
class _KeyboardLayout extends StatelessWidget {
  const _KeyboardLayout({required this.anchor, required this.child});

  final Rect anchor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final double width = anchor.width.clamp(math.min(420.0, screen.width - 16), screen.width - 16);
    final left = anchor.left.clamp(8.0, screen.width - width - 8);
    return Stack(
      children: [
        Positioned(
          left: left,
          top: anchor.bottom + 8,
          bottom: 8,
          width: width,
          child: Align(alignment: Alignment.topCenter, child: child),
        ),
      ],
    );
  }
}

class _KeyboardPanel extends StatefulWidget {
  const _KeyboardPanel({required this.query, required this.suggest});

  final ValueNotifier<String> query;
  final Future<List<String>> Function(String prefix) suggest;

  @override
  State<_KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends State<_KeyboardPanel> {
  static const _suggestionHeight = 34.0;
  static const _letters = ['qwertyuiop', "asdfghjkl'", 'zxcvbnm-'];
  static const _symbols = ['1234567890', '@#&*()"\':;', '!?/+=_.,'];

  bool _symbolsPage = false;
  List<String> _suggestions = const [];
  Timer? _debounce;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    widget.query.addListener(_queryChanged);
    _queryChanged();
  }

  @override
  void dispose() {
    widget.query.removeListener(_queryChanged);
    _debounce?.cancel();
    super.dispose();
  }

  // Suggestions follow the text after a short pause; a late answer for older
  // text is dropped.
  void _queryChanged() {
    _debounce?.cancel();
    final text = widget.query.value;
    if (text.trim().isEmpty) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      final ask = ++_asked;
      final found = await widget.suggest(text);
      if (!mounted || ask != _asked) return;
      setState(() => _suggestions = found.take(6).toList());
    });
  }

  void _type(String c) {
    playSfx(context, Sfx.key);
    widget.query.value += c;
  }

  void _backspace() {
    playSfx(context, Sfx.delete);
    final q = widget.query.value;
    if (q.isNotEmpty) widget.query.value = q.substring(0, q.length - 1);
  }

  void _clear() {
    playSfx(context, Sfx.delete);
    widget.query.value = '';
  }

  void _pick(String suggestion) {
    widget.query.value = suggestion;
    Navigator.of(context).pop(true);
  }

  void _submit() {
    if (widget.query.value.trim().isEmpty) return;
    Navigator.of(context).pop(true);
  }

  // A hardware or remote keyboard types too.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 0x20 && ch.codeUnitAt(0) != 0x7f) {
      _type(ch.toLowerCase());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    const gap = 8.0;
    final rows = _symbolsPage ? _symbols : _letters;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: _Acrylic(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, box) {
              final unit = (box.maxWidth - gap * 9) / 10;
              // Four rows of keys share what is left under the suggestions.
              final height = box.maxHeight.isFinite
                  ? ((box.maxHeight - _suggestionHeight - gap * 4.5) / 4).clamp(28.0, 44.0)
                  : 44.0;
              Widget key(
                String id,
                Widget label,
                VoidCallback onTap, {
                int span = 1,
                bool accent = false,
                bool first = false,
              }) {
                return _Key(
                  key: ValueKey(id),
                  width: unit * span + gap * (span - 1),
                  height: height,
                  autofocus: first,
                  accent: accent,
                  onActivate: onTap,
                  child: label,
                );
              }

              final label = TextStyle(fontSize: d.t(18), fontWeight: FontWeight.w600);
              final small = TextStyle(fontSize: d.t(14), fontWeight: FontWeight.w600);
              Widget row(List<Widget> keys) => Padding(
                padding: const EdgeInsets.only(top: gap),
                child: Row(
                  children: [
                    for (var i = 0; i < keys.length; i++) ...[if (i > 0) const SizedBox(width: gap), keys[i]],
                  ],
                ),
              );

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Suggestions(
                    items: _suggestions,
                    empty: widget.query.value.trim().isEmpty,
                    height: _suggestionHeight,
                    onPick: _pick,
                  ),
                  const SizedBox(height: gap / 2),
                  for (var r = 0; r < rows.length; r++)
                    row([
                      for (var i = 0; i < rows[r].length; i++)
                        key(
                          'key-${rows[r][i]}',
                          Text(rows[r][i], style: label),
                          () => _type(rows[r][i]),
                          first: r == 0 && i == 0,
                        ),
                      if (r == rows.length - 1)
                        key(
                          'key-backspace',
                          Icon(Icons.backspace_outlined, size: d.t(22)),
                          _backspace,
                          span: 10 - rows[r].length,
                        ),
                    ]),
                  row([
                    key('key-mode', Text(_symbolsPage ? 'abc' : '&123', style: small), () {
                      playSfx(context, Sfx.key);
                      setState(() => _symbolsPage = !_symbolsPage);
                    }, span: 2),
                    key('key-space', Icon(Icons.space_bar_rounded, size: d.t(24)), () => _type(' '), span: 4),
                    key('key-clear', Text('Clear', style: small), _clear, span: 2),
                    key(
                      'search-go',
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_rounded, size: d.t(20)),
                          const SizedBox(width: 4),
                          Text('Search', style: small),
                        ],
                      ),
                      _submit,
                      span: 2,
                      accent: true,
                    ),
                  ]),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One line of suggestion chips over the keys; a hint while nothing is typed.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.items, required this.empty, required this.height, required this.onPick});

  final List<String> items;
  final bool empty;
  final double height;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final dim = TextStyle(color: ChithramColors.of(context).textDim, fontSize: d.t(14));
    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: items.isEmpty
            ? Align(
                key: ValueKey(empty),
                alignment: Alignment.centerLeft,
                child: Text(empty ? 'Start typing for suggestions' : '', style: dim),
              )
            : ListView.separated(
                key: ValueKey(items.join('\n')),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _Key(
                  key: ValueKey('suggestion-$i'),
                  height: height,
                  pill: true,
                  onActivate: () => onPick(items[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_rounded, size: d.t(16), color: ChithramColors.of(context).textDim),
                        const SizedBox(width: 6),
                        Text(
                          items[i],
                          style: TextStyle(fontSize: d.t(15), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Frosted glass: the page shows through, blurred, under a dark tint.
class _Acrylic extends StatelessWidget {
  const _Acrylic({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xA6343442), Color(0xC8121218)],
              ),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    );
  }
}

/// A key: glass at rest; white with a soft glow when focused; a quick dip
/// when pressed. Moving focus onto it ticks.
class _Key extends StatefulWidget {
  const _Key({
    super.key,
    required this.child,
    required this.onActivate,
    required this.height,
    this.width,
    this.autofocus = false,
    this.accent = false,
    this.pill = false,
  });

  final Widget child;
  final VoidCallback onActivate;
  final double height;
  final double? width;
  final bool autofocus;
  final bool accent;
  final bool pill;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  final _node = FocusNode(debugLabel: 'keyboard key');
  bool _focused = false;
  bool _pressed = false;
  Timer? _release;

  @override
  void dispose() {
    _release?.cancel();
    _node.dispose();
    super.dispose();
  }

  void _activate() {
    widget.onActivate();
    if (!mounted) return;
    setState(() => _pressed = true);
    _release?.cancel();
    _release = Timer(const Duration(milliseconds: 90), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  void _focusChanged(bool focused) {
    setState(() => _focused = focused);
    // The key focused when the panel opens does not tick.
    if (focused && !(widget.autofocus && _first)) playSfx(context, Sfx.move);
    _first = false;
  }

  bool _first = true;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.pill ? widget.height / 2 : 12);
    final Color fill;
    final Color ink;
    if (_focused) {
      fill = widget.accent ? ChithramColors.of(context).accent : Colors.white.withValues(alpha: 0.94);
      ink = const Color(0xFF111117);
    } else {
      fill = widget.accent ? ChithramColors.of(context).accent.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.07);
      ink = Colors.white.withValues(alpha: 0.9);
    }
    return FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      onFocusChange: _focusChanged,
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
        // Geometry, and the panel keeps focus at its edges.
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            moveFocus(_node, intent.direction);
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: () {
          _node.requestFocus();
          _activate();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.9 : (_focused ? 1.1 : 1.0),
          duration: Duration(milliseconds: _pressed ? 60 : 140),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: widget.width,
            height: widget.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              border: Border.all(color: Colors.white.withValues(alpha: _focused ? 0 : 0.06)),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: (widget.accent ? ChithramColors.of(context).accent : Colors.white).withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: IconTheme.merge(
              data: IconThemeData(color: ink),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: ink),
                child: widget.pill
                    ? widget.child
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FittedBox(fit: BoxFit.scaleDown, child: widget.child),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
