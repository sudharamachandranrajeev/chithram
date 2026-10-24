import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_rx/localsend_rx.dart';

import '../../intake/intake.dart';
import '../../intake/summary.dart';
import 'receive_keys.dart';

/// What a sender wants to deliver, and the choice: the action Chithram would
/// take (which counts as accepting) or Reject. Reject is focused first, so a
/// stray press never accepts. Gives up as a rejection after 60 s, or when
/// [dismiss] fires (the receiver stopped).
///
/// [title] and [acceptLabel] replace the LocalSend wording (Telegram uses it
/// for "New from Telegram" / "Play").
Future<bool> showReceivePrompt(
  BuildContext context,
  LsOffer offer, {
  required Listenable dismiss,
  String? title,
  String? acceptLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ReceivePrompt(offer: offer, dismiss: dismiss, title: title, acceptLabel: acceptLabel),
  );
  return result ?? false;
}

class _ReceivePrompt extends StatefulWidget {
  const _ReceivePrompt({required this.offer, required this.dismiss, this.title, this.acceptLabel});

  final LsOffer offer;
  final Listenable dismiss;
  final String? title;
  final String? acceptLabel;

  @override
  State<_ReceivePrompt> createState() => _ReceivePromptState();
}

class _ReceivePromptState extends State<_ReceivePrompt> {
  Timer? _timeout;
  NavigatorState? _navigator;

  @override
  void initState() {
    super.initState();
    widget.dismiss.addListener(_close);
    _timeout = Timer(const Duration(seconds: 60), _close);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigator = Navigator.of(context);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    widget.dismiss.removeListener(_close);
    _navigator = null;
    super.dispose();
  }

  void _close() {
    final nav = _navigator;
    _navigator = null;
    nav?.pop(false);
  }

  /// The button text, and what the content line shows.
  (String, Widget) _describe() {
    final files = widget.offer.files;
    final single = files.length == 1 ? files.single : null;
    final preview = single?.preview;
    if (preview != null) {
      final action = intakeActionLabel(classify(preview));
      return (action ?? 'Show text', IntakeSummary(preview));
    }
    if (single != null && single.name.toLowerCase().endsWith('.torrent')) {
      return ('Open torrent', Text('${single.name} (${_size(single.size)})'));
    }
    return (
      widget.acceptLabel ?? 'Accept',
      Text([for (final f in files) '${f.name} (${_size(f.size)})'].join('\n')),
    );
  }

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : bytes >= 1024
          ? '${(bytes / 1024).toStringAsFixed(0)} KB'
          : '$bytes B';

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final (action, content) = _describe();
    final who = [o.senderAlias, if (o.senderModel != null) o.senderModel!, o.senderAddress].join(' · ');
    return AlertDialog(
      key: ReceiveKeys.prompt,
      title: Text(widget.title ?? 'Incoming from a phone'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          content,
        ],
      ),
      actions: [
        TextButton(
          key: ReceiveKeys.reject,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Reject'),
        ),
        FilledButton(
          key: ReceiveKeys.accept,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    );
  }
}
