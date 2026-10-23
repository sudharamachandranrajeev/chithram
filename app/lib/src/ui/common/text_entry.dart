import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services.dart';
import '../../features/receive/receive_page.dart';
import '../../features/receive/receive_service.dart';
import 'dims.dart';
import '../tv/dpad.dart';
import '../tv/focus_card.dart';
import '../tv/keyboard.dart';
import 'keys.dart';

enum TextEntryKind { search, url, magnet, pin }

/// Asks for a line of text. Null when cancelled.
///
/// The TextField uses the system keyboard, so a phone keyboard, a remote app
/// or a USB keyboard can type into it. On a TV the on-screen link keyboard is
/// open from the start; elsewhere a Keyboard button opens it. Paste reads the
/// clipboard, and "Send from phone" (for links) opens the receive screen.
///
/// With [acceptFromPhone] (keys and long tokens, not on phones), the receiver
/// runs while the dialog is open and LocalSend text from the user's phone fills
/// the field, after the usual accept prompt. The "Send from phone" button is
/// replaced by a note, since receiving is already on.
Future<String?> askText(
  BuildContext c, {
  required String title,
  String? hint,
  String? initial,
  TextEntryKind kind = TextEntryKind.url,
  bool acceptFromPhone = false,
}) {
  return showDialog<String>(
    context: c,
    builder: (_) => _TextEntryDialog(
      opener: c,
      title: title,
      hint: hint,
      initial: initial,
      kind: kind,
      acceptFromPhone: acceptFromPhone,
    ),
  );
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({
    required this.opener,
    required this.title,
    this.hint,
    this.initial,
    required this.kind,
    this.acceptFromPhone = false,
  });

  final BuildContext opener;
  final String title;
  final String? hint;
  final String? initial;
  final TextEntryKind kind;
  final bool acceptFromPhone;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  final _keys = SectionFocus();
  bool? _showKeys;
  VoidCallback? _unroute;
  ReceiveService? _receive;

  bool get _link =>
      widget.kind == TextEntryKind.url || widget.kind == TextEntryKind.magnet;

  // Phones paste instead; their keyboard is the system one.
  bool get _fromPhone => widget.acceptFromPhone && !Dims.of(context).phone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_receive != null || !_fromPhone) return;
    final receive = AppServices.of(widget.opener).receive;
    _receive = receive;
    _unroute = receive.routeTextTo((text) => _controller.text = text.trim());
    unawaited(receive.start());
  }

  @override
  void dispose() {
    _unroute?.call();
    final receive = _receive;
    if (receive != null) unawaited(receive.stop());
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
    final start = sel.isValid && !sel.isCollapsed
        ? sel.start
        : (end - 1).clamp(0, end);
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
    return moveFocus(current, direction)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final showKeys = _showKeys ?? d.tv;
    // Not an AlertDialog: its intrinsic sizing cannot lay out the keyboard.
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        // The field and keyboard scroll; the buttons stay pinned below them so
        // OK is on screen even when the keyboard is taller than a 540 dp TV.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: _leaveField,
                      child: TextField(
                        key: Keys.textEntryField,
                        controller: _controller,
                        autofocus: true,
                        textInputAction: switch (widget.kind) {
                          TextEntryKind.search => TextInputAction.search,
                          TextEntryKind.pin => TextInputAction.done,
                          _ => TextInputAction.go,
                        },
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
                    if (_fromPhone) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Or send the text from your phone with LocalSend.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (showKeys && _link && !d.phone) ...[
                      const SizedBox(height: 16),
                      UrlKeyboard(
                        focus: _keys,
                        onChar: _type,
                        onBackspace: _backspace,
                        onClear: _controller.clear,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: Keys.textEntryPaste,
                    onPressed: _paste,
                    child: const Text('Paste'),
                  ),
                  // A phone has the system keyboard and is the sender: these two are for TVs and desktops.
                  if (_link && !d.phone)
                    TextButton(
                      key: Keys.textEntryKeyboard,
                      onPressed: () => setState(() => _showKeys = !showKeys),
                      child: Text(showKeys ? 'Hide keyboard' : 'Keyboard'),
                    ),
                  if (_link && !d.phone && !widget.acceptFromPhone)
                    TextButton(
                      key: Keys.textEntrySend,
                      onPressed: _sendFromPhone,
                      child: const Text('Send from phone'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: Keys.textEntryOk,
                    onPressed: () =>
                        Navigator.of(context).pop(_controller.text.trim()),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
