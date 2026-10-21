import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'keys.dart';

enum TextEntryKind { search, url, magnet, pin }

/// Asks for a line of text. Null when cancelled. Stub: a dialog with a
/// TextField and a Paste button; the TV key handling and the on-screen URL
/// layout come with the player work package.
Future<String?> askText(
  BuildContext c, {
  required String title,
  String? hint,
  String? initial,
  TextEntryKind kind = TextEntryKind.url,
}) {
  return showDialog<String>(
    context: c,
    builder: (_) => _TextEntryDialog(title: title, hint: hint, initial: initial, kind: kind),
  );
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({required this.title, this.hint, this.initial, required this.kind});

  final String title;
  final String? hint;
  final String? initial;
  final TextEntryKind kind;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null) _controller.text = text.trim();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
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
      actions: [
        TextButton(key: Keys.textEntryPaste, onPressed: _paste, child: const Text('Paste')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: Keys.textEntryOk,
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
