import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/receive/receive_page.dart';
import 'dims.dart';
import 'dpad.dart';
import 'focus_card.dart';
import 'keyboard.dart';
import 'keys.dart';

enum TextEntryKind { search, url, magnet, pin }

/// Asks for a line of text. Null when cancelled.
///
/// The TextField uses the system keyboard, so a phone keyboard, a remote app
/// or a USB keyboard can type into it. On a TV the on-screen link keyboard is
/// open from the start; elsewhere a Keyboard button opens it. Paste reads the
/// clipboard, and "Send from phone" (for links) opens the receive screen.
Future<String?> askText(
  BuildContext c, {
  required String title,
  String? hint,
  String? initial,
  TextEntryKind kind = TextEntryKind.url,
}) {
  return showDialog<String>(
    context: c,
    builder: (_) => _TextEntryDialog(opener: c, title: title, hint: hint, initial: initial, kind: kind),
  );
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({required this.opener, required this.title, this.hint, this.initial, required this.kind});

  final BuildContext opener;
  final String title;
  final String? hint;
  final String? initial;
  final TextEntryKind kind;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  final _keys = SectionFocus();
  bool? _showKeys;

  bool get _link => widget.kind == TextEntryKind.url || widget.kind == TextEntryKind.magnet;

  @override
  void dispose() {
    _controller.dispose();
    _keys.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null) _controller.text = text.trim();
  }

  void _type(String s) {
    final sel = _controller.selection;
    final text = _controller.text;
    final at = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _controller.value = TextEditingValue(
      text: text.replaceRange(at, end, s),
      selection: TextSelection.collapsed(offset: at + s.length),
    );
  }

  void _backspace() {
    final sel = _controller.selection;
    final text = _controller.text;
    if (text.isEmpty) return;
    final end = sel.isValid ? sel.end : text.length;
    final start = sel.isValid && !sel.isCollapsed ? sel.start : (end - 1).clamp(0, end);
    if (end == 0) return;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
    );
  }

  void _sendFromPhone() {
    final opener = widget.opener;
    Navigator.of(context).pop();
    if (opener.mounted) unawaited(openReceive(opener));
  }

  // flutter/flutter#147772: Up and Down stay inside a TextField on a TV. This
  // catches them first and moves focus by geometry instead.
  KeyEventResult _leaveField(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final TraversalDirection direction;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      direction = TraversalDirection.down;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      direction = TraversalDirection.up;
    } else {
      return KeyEventResult.ignored;
    }
    final current = FocusManager.instance.primaryFocus;
    if (current == null) return KeyEventResult.ignored;
    return moveFocus(current, direction) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final showKeys = _showKeys ?? d.tv;
    // Not an AlertDialog: its intrinsic sizing cannot lay out the keyboard.
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _leaveField,
                child: TextField(
                  key: Keys.textEntryField,
                  controller: _controller,
                  autofocus: true,
                  obscureText: widget.kind == TextEntryKind.pin,
                  keyboardType: switch (widget.kind) {
                    TextEntryKind.pin => TextInputType.number,
                    TextEntryKind.search => TextInputType.text,
                    _ => TextInputType.url,
                  },
                  decoration: InputDecoration(hintText: widget.hint),
                  onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
                ),
              ),
              if (showKeys && _link) ...[
                const SizedBox(height: 16),
                UrlKeyboard(focus: _keys, onChar: _type, onBackspace: _backspace, onClear: _controller.clear),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(key: Keys.textEntryPaste, onPressed: _paste, child: const Text('Paste')),
                  if (_link)
                    TextButton(
                      key: Keys.textEntryKeyboard,
                      onPressed: () => setState(() => _showKeys = !showKeys),
                      child: Text(showKeys ? 'Hide keyboard' : 'Keyboard'),
                    ),
                  if (_link)
                    TextButton(key: Keys.textEntrySend, onPressed: _sendFromPhone, child: const Text('Send from phone')),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  FilledButton(
                    key: Keys.textEntryOk,
                    onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
