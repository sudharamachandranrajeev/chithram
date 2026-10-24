import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../common/dims.dart';
import '../common/sfx.dart';
import 'dpad.dart';

/// What the keyboard is for: the keys and the action key follow it.
enum KeyboardLayout {
  /// Lower-case letters and a symbols page; the action key searches.
  search,

  /// Names, passwords, PINs: a digits row, letters with Shift, symbols.
  text,

  /// Links, magnets, keys: a digits row, letters with Shift and the URL
  /// characters `:/.?=&-_` on the main page.
  url,

  /// Phone numbers and login codes: a number pad with `+`.
  number,
}

/// One suggestion, labelled with where it came from (`YouTube`, `Live TV`).
/// Suggestions of one source share a row under the keys.
class KeyboardSuggestion {
  const KeyboardSuggestion(
    this.text, {
    this.source = '',
    this.icon = Icons.search_rounded,
  });

  final String text;
  final String source;
  final IconData icon;
}

/// Opens the on-screen keyboard: a frosted panel that drops down from
/// [anchor] (the search bar's or text field's rect on screen). Typing changes
/// [query] at once. Suggestions for the text so far come from [suggest] and
/// sit in rows under the keys; picking one, or the action key, closes the
/// panel and calls [onSubmit]. Back closes it and keeps the text. Returns
/// whether it was submitted.
///
/// Key ids (what the tests tap): `key-<char>`, `key-space`, `key-backspace`,
/// `key-clear`, `key-shift`, `key-mode` (letters / symbols), the action key
/// `search-go` ([KeyboardLayout.search]) or `key-ok` (the others), and
/// `suggestion-<i>`.
Future<bool> showSearchKeyboard(
  BuildContext context, {
  required Rect anchor,
  required ValueNotifier<String> query,
  Future<List<KeyboardSuggestion>> Function(String prefix)? suggest,
  VoidCallback? onSubmit,
  KeyboardLayout layout = KeyboardLayout.search,
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
      layout: layout,
      child: _KeyboardPanel(query: query, suggest: suggest, layout: layout),
    ),
    // The panel unrolls downwards from the bar and fades in.
    transitionBuilder: (context, animation, _, child) {
      final t = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: t,
        child: AnimatedBuilder(
          animation: t,
          builder: (context, child) => ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 0.6 + 0.4 * t.value,
              child: child,
            ),
          ),
          child: child,
        ),
      );
    },
  );
  if (!context.mounted) return submitted == true;
  if (submitted == true) {
    playSfx(context, Sfx.submit);
    onSubmit?.call();
  } else {
    playSfx(context, Sfx.close);
  }
  return submitted == true;
}

/// Places the panel under the bar, starting at its left edge, in the room
/// between the bar and the bottom of the screen. The panel is only as wide as
/// its keys need (a number pad is narrow), never wider than the bar.
class _KeyboardLayout extends StatelessWidget {
  const _KeyboardLayout({
    required this.anchor,
    required this.layout,
    required this.child,
  });

  final Rect anchor;
  final KeyboardLayout layout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final screen = MediaQuery.sizeOf(context);
    final number = layout == KeyboardLayout.number;
    final double most = number ? (d.tv ? 240 : 300) : (d.tv ? 520 : 680);
    final double width = math
        .min(math.max(anchor.width, math.min(320.0, most)), most)
        .clamp(0, screen.width - 16);
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

enum _Act { char, backspace, shift, mode, space, clear, go }

/// One key of a layout: [span] columns wide.
class _K {
  const _K.char(String this.char) : act = _Act.char, span = 1;
  const _K(this.act, [this.span = 1]) : char = null;

  final _Act act;
  final String? char;
  final int span;
}

List<_K> _chars(String s) => [for (final c in s.split('')) _K.char(c)];

class _KeyboardPanel extends StatefulWidget {
  const _KeyboardPanel({
    required this.query,
    required this.suggest,
    required this.layout,
  });

  final ValueNotifier<String> query;
  final Future<List<KeyboardSuggestion>> Function(String prefix)? suggest;
  final KeyboardLayout layout;

  @override
  State<_KeyboardPanel> createState() => _KeyboardPanelState();
}

class _KeyboardPanelState extends State<_KeyboardPanel> {
  static const _gap = 6.0;
  static const _symbols = [
    '1234567890',
    '@#&*()"\':;',
    '!?/+=_.,-%',
    r'~$<>[]{}',
  ];

  bool _symbolsPage = false;
  bool _shift = false;
  List<KeyboardSuggestion> _suggestions = const [];
  Timer? _debounce;
  int _asked = 0;

  KeyboardLayout get _layout => widget.layout;

  int get _columns => _layout == KeyboardLayout.number ? 3 : 10;

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
    final suggest = widget.suggest;
    if (suggest == null) return;
    final text = widget.query.value;
    if (text.trim().isEmpty) {
      _asked++;
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      final ask = ++_asked;
      final found = await suggest(text);
      if (!mounted || ask != _asked) return;
      setState(() => _suggestions = found);
    });
  }

  /// The rows of the current page; each adds up to [_columns].
  List<List<_K>> _rows() {
    const back = _K(_Act.backspace, 2);
    const bottom = [
      _K(_Act.mode, 2),
      _K(_Act.space, 4),
      _K(_Act.clear, 2),
      _K(_Act.go, 2),
    ];
    if (_layout == KeyboardLayout.number) {
      return [
        _chars('123'),
        _chars('456'),
        _chars('789'),
        [..._chars('+0'), const _K(_Act.backspace)],
        const [_K(_Act.clear), _K(_Act.go, 2)],
      ];
    }
    if (_symbolsPage) {
      return [
        for (final r in _symbols.take(3)) _chars(r),
        [..._chars(_symbols[3]), back],
        if (_layout == KeyboardLayout.url)
          [
            const _K(_Act.mode, 2),
            ..._chars('.-_'),
            const _K(_Act.space, 1),
            const _K(_Act.clear, 2),
            const _K(_Act.go, 2),
          ]
        else
          bottom,
      ];
    }
    String cased(String s) => _shift ? s.toUpperCase() : s;
    switch (_layout) {
      case KeyboardLayout.search:
        return [
          _chars('qwertyuiop'),
          _chars("asdfghjkl'"),
          [..._chars('zxcvbnm-'), back],
          bottom,
        ];
      case KeyboardLayout.text:
        return [
          _chars('1234567890'),
          _chars(cased('qwertyuiop')),
          _chars(cased("asdfghjkl'")),
          [const _K(_Act.shift), ..._chars(cased('zxcvbnm')), back],
          bottom,
        ];
      case KeyboardLayout.url:
        return [
          _chars('1234567890'),
          _chars(cased('qwertyuiop')),
          _chars('${cased('asdfghjkl')}:'),
          [
            const _K(_Act.shift),
            ..._chars('${cased('zxcvbnm')}/'),
            const _K(_Act.backspace),
          ],
          [
            const _K(_Act.mode),
            ..._chars('.?=&-_'),
            const _K(_Act.clear),
            const _K(_Act.go, 2),
          ],
        ];
      case KeyboardLayout.number:
        return const [];
    }
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
    // A search needs words; a form field may be left empty on purpose.
    if (_layout == KeyboardLayout.search && widget.query.value.trim().isEmpty)
      return;
    Navigator.of(context).pop(true);
  }

  void _act(_K k) {
    switch (k.act) {
      case _Act.char:
        _type(k.char!);
      case _Act.backspace:
        _backspace();
      case _Act.space:
        _type(' ');
      case _Act.clear:
        _clear();
      case _Act.go:
        _submit();
      case _Act.shift:
        playSfx(context, Sfx.key);
        setState(() => _shift = !_shift);
      case _Act.mode:
        playSfx(context, Sfx.key);
        setState(() => _symbolsPage = !_symbolsPage);
    }
  }

  // A hardware or remote keyboard types too. Search is lower case; a number
  // pad takes digits and `+` only.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null &&
        ch.length == 1 &&
        ch.codeUnitAt(0) >= 0x20 &&
        ch.codeUnitAt(0) != 0x7f) {
      if (_layout == KeyboardLayout.number && !RegExp(r'[0-9+]').hasMatch(ch))
        return KeyEventResult.handled;
      _type(_layout == KeyboardLayout.search ? ch.toLowerCase() : ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _id(_K k) => switch (k.act) {
    _Act.char => 'key-${k.char}',
    _Act.backspace => 'key-backspace',
    _Act.shift => 'key-shift',
    _Act.mode => 'key-mode',
    _Act.space => 'key-space',
    _Act.clear => 'key-clear',
    _Act.go => _layout == KeyboardLayout.search ? 'search-go' : 'key-ok',
  };

  Widget _label(_K k, Dims d) {
    final label = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    final small = TextStyle(
      fontSize: d.tv ? 16 : 14,
      fontWeight: FontWeight.w600,
    );
    final icon = d.tv ? 20.0 : 22.0;
    return switch (k.act) {
      _Act.char => Text(k.char!, style: label),
      _Act.backspace => Icon(Icons.backspace_outlined, size: icon),
      _Act.shift => Icon(
        _shift ? Icons.keyboard_capslock_rounded : Icons.arrow_upward_rounded,
        size: icon,
      ),
      _Act.mode => Text(
        _symbolsPage ? 'abc' : (k.span > 1 ? '&123' : '#+'),
        style: small,
      ),
      _Act.space => Icon(Icons.space_bar_rounded, size: icon),
      _Act.clear => Text('Clear', style: small),
      _Act.go => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _layout == KeyboardLayout.search
                ? Icons.search_rounded
                : Icons.check_rounded,
            size: icon,
          ),
          const SizedBox(width: 4),
          Text(
            _layout == KeyboardLayout.search ? 'Search' : 'OK',
            style: small,
          ),
        ],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final keyHeight = d.tv ? 32.0 : 40.0;
    final rows = _rows();
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: _Acrylic(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: LayoutBuilder(
            builder: (context, box) {
              final unit = (box.maxWidth - _gap * (_columns - 1)) / _columns;
              final keysHeight = rows.length * (keyHeight + _gap) - _gap;
              // Suggestion rows fill what is left under the keys.
              final room = box.maxHeight.isFinite
                  ? box.maxHeight - keysHeight - 20
                  : 200.0;
              Widget row(int r) => Padding(
                padding: EdgeInsets.only(top: r == 0 ? 0 : _gap),
                child: Row(
                  children: [
                    for (final (i, k) in rows[r].indexed) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      _Key(
                        key: ValueKey(_id(k)),
                        width: unit * k.span + _gap * (k.span - 1),
                        height: keyHeight,
                        autofocus: r == 0 && i == 0,
                        accent:
                            k.act == _Act.go || (k.act == _Act.shift && _shift),
                        onActivate: () => _act(k),
                        child: _label(k, d),
                      ),
                    ],
                  ],
                ),
              );

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var r = 0; r < rows.length; r++) row(r),
                  if (widget.suggest != null)
                    _Suggestions(
                      items: _suggestions,
                      empty: widget.query.value.trim().isEmpty,
                      height: d.tv ? 30 : 34,
                      room: room,
                      onPick: _pick,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Suggestion pills under the keys, one row per source (YouTube, titles, Live
/// TV), each labelled; a hint while nothing is typed. Rows that do not fit in
/// [room] are left out.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.items,
    required this.empty,
    required this.height,
    required this.room,
    required this.onPick,
  });

  final List<KeyboardSuggestion> items;
  final bool empty;
  final double height;
  final double room;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final dim = TextStyle(color: colors.textDim, fontSize: d.tv ? 16 : 14);
    final sources = <String, List<int>>{};
    for (var i = 0; i < items.length; i++) {
      sources.putIfAbsent(items[i].source, () => []).add(i);
    }
    const gap = 8.0;
    final fit = math.max(1, ((room - 10) / (height + gap)).floor());
    final shown = sources.entries.take(fit).toList();
    final label = d.tv ? 80.0 : 84.0;
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: shown.isEmpty
            ? SizedBox(
                height: height,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    empty ? 'Start typing for suggestions' : '',
                    style: dim,
                  ),
                ),
              )
            : Column(
                key: const ValueKey('keyboard-suggestions'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (n, MapEntry(key: source, value: indexes))
                      in shown.indexed)
                    Padding(
                      padding: EdgeInsets.only(top: n == 0 ? 0 : gap),
                      child: SizedBox(
                        height: height,
                        child: Row(
                          children: [
                            if (source.isNotEmpty)
                              SizedBox(
                                width: label,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text(
                                    source,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: dim.copyWith(
                                      fontSize: d.tv ? 16 : 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              // Room above and below for the focused pill's
                              // scale; focus scrolls the row.
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                clipBehavior: Clip.none,
                                child: Row(
                                  children: [
                                    for (final i in indexes) ...[
                                      if (i != indexes.first)
                                        const SizedBox(width: gap),
                                      _Key(
                                        key: ValueKey('suggestion-$i'),
                                        height: height,
                                        pill: true,
                                        onActivate: () => onPick(items[i].text),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                items[i].icon,
                                                size: 16,
                                                color: colors.textDim,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                items[i].text,
                                                maxLines: 1,
                                                style: TextStyle(
                                                  fontSize: d.tv ? 16 : 15,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 40,
            offset: Offset(0, 16),
          ),
        ],
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
    // A suggestion off the side of its row scrolls in.
    if (focused && widget.pill) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 140),
      );
    }
  }

  bool _first = true;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.pill ? widget.height / 2 : 12);
    final Color fill;
    final Color ink;
    if (_focused) {
      fill = widget.accent
          ? ChithramColors.of(context).accent
          : Colors.white.withValues(alpha: 0.94);
      ink = const Color(0xFF111117);
    } else {
      fill = widget.accent
          ? ChithramColors.of(context).accent.withValues(alpha: 0.28)
          : Colors.white.withValues(alpha: 0.07);
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
              border: Border.all(
                color: Colors.white.withValues(alpha: _focused ? 0 : 0.06),
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color:
                            (widget.accent
                                    ? ChithramColors.of(context).accent
                                    : Colors.white)
                                .withValues(alpha: 0.35),
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
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: widget.child,
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
