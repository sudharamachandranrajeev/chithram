import 'package:flutter/material.dart';
import 'package:torznab/torznab.dart';

import '../../core/redact.dart';
import '../../core/services.dart';
import '../../ui/common/text_entry.dart';
import 'torznab_service.dart';

/// "Last worked 3 min ago", the last error, or "Not used yet". For Settings.
String healthLine(TorznabService service, TorznabEndpoint e, DateTime now) {
  final h = service.health(e.id);
  if (h.lastError != null) return 'Failing: ${h.lastError}';
  final ok = h.lastOk;
  if (ok == null) return e.capsAt == null ? 'Not checked yet' : 'Capabilities checked';
  final d = now.difference(ok);
  final ago = d.inMinutes < 1
      ? 'just now'
      : d.inHours < 1
      ? '${d.inMinutes} min ago'
      : d.inDays < 1
      ? '${d.inHours} h ago'
      : '${d.inDays} d ago';
  return 'Worked $ago';
}

void _say(ScaffoldMessengerState messenger, String m) => messenger.showSnackBar(SnackBar(content: Text(redactText(m))));

/// Address, then API key; adds the endpoint once its capabilities answer.
/// Text from the phone fills either field.
Future<void> addTorznabEndpoint(BuildContext context) async {
  final service = AppServices.of(context).torznab;
  final messenger = ScaffoldMessenger.of(context);
  final url = await askText(
    context,
    title: 'Torznab address',
    hint: 'http://192.168.1.5:9117/api/v2.0/indexers/all/results/torznab/',
    kind: TextEntryKind.url,
    acceptFromPhone: true,
  );
  if (url == null || url.trim().isEmpty || !context.mounted) return;
  final key = await askText(
    context,
    title: 'API key (leave empty if none)',
    kind: TextEntryKind.url,
    acceptFromPhone: true,
  );
  if (key == null || !context.mounted) return;
  try {
    final e = await service.add(name: '', url: url, apiKey: key);
    _say(messenger, 'Added ${e.name}');
  } on TorznabException catch (e) {
    _say(messenger, e.message);
  }
}

enum _Choice { test, toggle, remove }

/// Test, enable or disable, remove.
Future<void> torznabEndpointMenu(BuildContext context, TorznabEndpoint e) async {
  final service = AppServices.of(context).torznab;
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showDialog<_Choice>(
    context: context,
    builder: (_) => SimpleDialog(
      title: Text(e.name),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(context, _Choice.test), child: const Text('Test')),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _Choice.toggle),
          child: Text(e.enabled ? 'Disable' : 'Enable'),
        ),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, _Choice.remove), child: const Text('Remove')),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _Choice.test:
      try {
        final caps = await service.test(e.id);
        _say(
          messenger,
          'Works: ${caps.categories.length} categories${caps.movieSearch ? ', movie search' : ''}${caps.tvSearch ? ', TV search' : ''}',
        );
      } on TorznabException catch (x) {
        _say(messenger, x.message);
      }
    case _Choice.toggle:
      await service.setEnabled(e.id, !e.enabled);
    case _Choice.remove:
      await service.remove(e.id);
      _say(messenger, 'Removed ${e.name}');
  }
}
