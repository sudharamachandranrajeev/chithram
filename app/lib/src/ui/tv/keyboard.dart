import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/dims.dart';
import 'focus_card.dart';

/// On-screen D-pad keyboard (a TextField is avoided on TV:
/// flutter/flutter#147772). Key ids (`key-a`, `key-space`, `key-backspace`,
/// `key-clear`) are what the tests tap.
class OnScreenKeyboard extends StatelessWidget {
  const OnScreenKeyboard({
    super.key,
    required this.focus,
    required this.onChar,
    required this.onBackspace,
    required this.onClear,
  });

  static const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// The section whose entry node goes to the first key.
  final SectionFocus focus;
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final key = d.phone ? 44.0 : d.u(52);
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, box) {
        final cols = (box.maxWidth / (key + 5 + gap)).floor().clamp(6, 12);
        final rows = <List<String>>[
          for (var i = 0; i < _chars.length; i += cols)
            [for (var j = i; j < i + cols && j < _chars.length; j++) _chars[j]],
        ];
        var first = true;
        Widget keyCard(
          Widget child,
          VoidCallback onTap, {
          double? width,
          String? id,
        }) {
          final card = FocusCard(
            key: id == null ? null : ValueKey('key-$id'),
            focusNode: first ? focus.entry : null,
            section: focus,
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

        return Column(
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
                          Text(
                            c,
                            style: TextStyle(
                              fontSize: d.t(16),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          () => onChar(c),
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
                  child: keyCard(
                    Icon(Icons.space_bar_rounded, size: d.t(24)),
                    () => onChar(' '),
                    width: key * 2 + gap + 5,
                    id: 'space',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: gap),
                  child: keyCard(
                    Icon(Icons.backspace_outlined, size: d.t(24)),
                    onBackspace,
                    width: key * 2 + gap + 5,
                    id: 'backspace',
                  ),
                ),
                keyCard(
                  Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: d.t(16),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onClear,
                  width: key * 2 + gap + 5,
                  id: 'clear',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// On-screen D-pad keyboard for links: a-z (A-Z with shift), 0-9 and the
/// characters URLs and magnet links need. Key ids are `key-<char>`,
/// `key-shift`, `key-backspace` and `key-clear`.
class UrlKeyboard extends StatefulWidget {
  const UrlKeyboard({
    super.key,
    required this.focus,
    required this.onChar,
    required this.onBackspace,
    required this.onClear,
  });

  static const letters = 'abcdefghijklmnopqrstuvwxyz';
  static const digits = '0123456789';
  static const symbols = ':/.?=&-_%#@+~';

  final SectionFocus focus;
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  State<UrlKeyboard> createState() => _UrlKeyboardState();
}

class _UrlKeyboardState extends State<UrlKeyboard> {
  bool _shift = false;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final key = d.phone ? 40.0 : d.u(48);
    const gap = 6.0;
    final letters = _shift ? UrlKeyboard.letters.toUpperCase() : UrlKeyboard.letters;
    final chars = [...letters.split(''), ...UrlKeyboard.digits.split(''), ...UrlKeyboard.symbols.split('')];
    return LayoutBuilder(builder: (context, box) {
      final cols = (box.maxWidth / (key + gap)).floor().clamp(6, 13);
      var first = true;
      Widget keyCard(Widget child, VoidCallback onTap, {double? width, required String id}) {
        final card = FocusCard(
          key: ValueKey('key-$id'),
          focusNode: first ? widget.focus.entry : null,
          section: widget.focus,
          radius: 10,
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

      final label = TextStyle(fontSize: d.t(16), fontWeight: FontWeight.w600);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chars.length; i += cols)
            Padding(
              padding: const EdgeInsets.only(bottom: gap),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var j = i; j < i + cols && j < chars.length; j++)
                    Padding(
                      padding: const EdgeInsets.only(right: gap),
                      child: keyCard(Text(chars[j], style: label), () => widget.onChar(chars[j]), id: chars[j]),
                    ),
                ],
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: gap),
                child: keyCard(
                  Icon(_shift ? Icons.keyboard_capslock_rounded : Icons.arrow_upward_rounded, size: d.t(22)),
                  () => setState(() => _shift = !_shift),
                  width: key * 2 + gap,
                  id: 'shift',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: gap),
                child: keyCard(Icon(Icons.backspace_outlined, size: d.t(22)), widget.onBackspace,
                    width: key * 2 + gap, id: 'backspace'),
              ),
              keyCard(Text('Clear', style: label), widget.onClear, width: key * 2 + gap, id: 'clear'),
            ],
          ),
        ],
      );
    });
  }
}
