import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services.dart';
import '../../features/receive/receive_page.dart';
import '../../features/receive/receive_service.dart';
import 'dims.dart';
import '../tv/dpad.dart';
import '../tv/search_keyboard.dart';
import 'keys.dart';

/// What the text is: it picks the system keyboard type and the on-screen
/// keyboard's layout. [number] is a phone number or a login code.
enum TextEntryKind { search, url, magnet, pin, number }

/// Asks for a line of text. Null when cancelled.
///
/// The TextField uses the system keyboard, so a phone keyboard, a remote app
/// or a USB keyboard can type into it. On a TV and desktop the dialog opens
/// compact (field and buttons); the on-screen keyboard (the search keyboard,
/// in a layout for the [kind]) drops down from the field only when the field
/// is selected or Keyboard is pressed, and its OK key confirms. Paste reads
/// the clipboard, and "Send from phone" (for links) opens the receive screen.
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
  final _field = GlobalKey();
  bool _keysOpen = false;
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
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null) _controller.text = text.trim();
  }

  KeyboardLayout get _layout => switch (widget.kind) {
    TextEntryKind.url || TextEntryKind.magnet => KeyboardLayout.url,
    TextEntryKind.number => KeyboardLayout.number,
    TextEntryKind.search || TextEntryKind.pin => KeyboardLayout.text,
  };

  /// Drops the on-screen keyboard down from the field. Its keys type at the
  /// end of the text; its OK key confirms the dialog.
  Future<void> _openKeys() async {
    final box = _field.currentContext?.findRenderObject() as RenderBox?;
    if (_keysOpen || box == null) return;
    _keysOpen = true;
    final text = ValueNotifier(_controller.text);
    void sync() => _controller.value = TextEditingValue(
      text: text.value,
      selection: TextSelection.collapsed(offset: text.value.length),
    );
    text.addListener(sync);
    final ok = await showSearchKeyboard(
      context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      query: text,
      layout: _layout,
    );
    text
      ..removeListener(sync)
      ..dispose();
    _keysOpen = false;
    if (ok && mounted) Navigator.of(context).pop(_controller.text.trim());
  }

  void _sendFromPhone() {
    final opener = widget.opener;
    Navigator.of(context).pop();
    if (opener.mounted) unawaited(openReceive(opener));
  }

  // flutter/flutter#147772: Up and Down stay inside a TextField on a TV. This
  // catches them first and moves focus by geometry instead. Select (the
  // remote's centre key), or Enter on an empty field, opens the keyboard.
  KeyEventResult _leaveField(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (!Dims.of(context).phone &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.gameButtonA ||
            (key == LogicalKeyboardKey.enter && _controller.text.isEmpty))) {
      unawaited(_openKeys());
      return KeyEventResult.handled;
    }
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
    final pad = d.tv ? 20.0 : 24.0;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: d.tv ? 540 : 680),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: d.tv ? 20 : null),
              ),
              SizedBox(height: d.tv ? 10 : 16),
              Focus(
                key: _field,
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _leaveField,
                child: TextField(
                  key: Keys.textEntryField,
                  controller: _controller,
                  autofocus: true,
                  textInputAction: switch (widget.kind) {
                    TextEntryKind.search => TextInputAction.search,
                    TextEntryKind.pin || TextEntryKind.number => TextInputAction.done,
                    _ => TextInputAction.go,
                  },
                  obscureText: widget.kind == TextEntryKind.pin,
                  keyboardType: switch (widget.kind) {
                    TextEntryKind.pin => TextInputType.number,
                    TextEntryKind.number => TextInputType.phone,
                    TextEntryKind.search => TextInputType.text,
                    _ => TextInputType.url,
                  },
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    // On a TV the field says how to bring up the keys.
                    helperText: d.tv ? 'Select the field to type' : null,
                  ),
                  // A TV remote has no pointer; a tap there is a touch remote.
                  onTap: d.tv ? () => unawaited(_openKeys()) : null,
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
              SizedBox(height: d.tv ? 12 : 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  // A phone has the system keyboard and is the sender: these are for TVs and desktops.
                  if (!d.phone)
                    TextButton.icon(
                      key: Keys.textEntryKeyboard,
                      onPressed: () => unawaited(_openKeys()),
                      icon: const Icon(Icons.keyboard_rounded),
                      label: const Text('Keyboard'),
                    ),
                  TextButton(
                    key: Keys.textEntryPaste,
                    onPressed: _paste,
                    child: const Text('Paste'),
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
            ],
          ),
        ),
      ),
    );
  }
}
