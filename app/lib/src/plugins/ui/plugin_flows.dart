import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nova_host/nova_host.dart';

import '../../core/services.dart';
import '../../ui/common/text_entry.dart';
import '../plugin_registry.dart';
import 'plugin_keys.dart';

/// The dialogs behind Settings > Search plugins: add a repository, add a single
/// `.py`, review an update, test. Each one shows what is about to be trusted and
/// leaves Cancel focused; nothing installs without an explicit press.

Future<T> _progress<T>(BuildContext context, String label, Future<T> work) async {
  final nav = Navigator.of(context, rootNavigator: true);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 20),
          Flexible(child: Text(label)),
        ]),
      ),
    ),
  ));
  try {
    return await work;
  } finally {
    if (nav.mounted) nav.pop();
  }
}

Future<void> showPluginError(BuildContext context, String title, Object error) {
  final text = error is PluginInstallError ? error.message : 'Something went wrong: $error';
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [TextButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
    ),
  );
}

Widget _domains(PluginCandidate c) {
  final domains = c.allowedHosts;
  return Text('${c.name} talks to ${domains.join(', ')}');
}

/// Adds a plugin repository: key (trust on first use), the plugins to install,
/// the domains each one is limited to. [url] pre-fills the question (links
/// handed to the app).
Future<void> addRepoFlow(BuildContext context, {String? url}) async {
  final registry = AppServices.of(context).plugins;
  final address = await askText(
    context,
    title: 'Plugin repository address',
    hint: 'https://example.org/plugins/',
    initial: url,
    acceptFromPhone: true,
  );
  if (address == null || address.trim().isEmpty || !context.mounted) return;
  final RepoPreview preview;
  try {
    preview = await _progress(context, 'Checking the repository...', registry.previewRepo(address));
  } catch (e) {
    if (context.mounted) await showPluginError(context, 'Could not add the repository', e);
    return;
  }
  if (!context.mounted) return;
  if (preview.firstUse) {
    final trust = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trust this repository?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(preview.name, style: Theme.of(ctx).textTheme.titleMedium),
            Text(preview.baseUrl),
            const SizedBox(height: 12),
            const Text('Its signing key:'),
            SelectableText(preview.keyId, key: const ValueKey('plugins-key-id'), style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 12),
            const Text('Chithram will only accept plugins signed by this key from now on. '
                'Trust it only if you got the address from someone you trust.'),
            const SizedBox(height: 12),
            Text('${preview.entries.length} plugin${preview.entries.length == 1 ? '' : 's'} listed.'),
          ]),
        ),
        actions: [
          TextButton(key: PluginKeys.cancel, autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(key: PluginKeys.trustContinue, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Trust and continue')),
        ],
      ),
    );
    if (trust != true || !context.mounted) return;
  }
  final picked = await _pickEntries(context, preview);
  if (picked == null || picked.isEmpty || !context.mounted) return;
  final List<PluginCandidate> cands;
  try {
    cands = await _progress(context, 'Checking ${picked.length} plugin${picked.length == 1 ? '' : 's'}...', () async {
      return [for (final e in picked) await registry.inspectEntry(preview, e)];
    }());
  } catch (e) {
    if (context.mounted) await showPluginError(context, 'Could not check the plugins', e);
    return;
  }
  if (!context.mounted) return;
  final ok = await _confirmDomains(context, cands, signed: true);
  if (ok != true || !context.mounted) return;
  try {
    await registry.installFromRepo(preview, cands);
    if (context.mounted) _say(context, 'Installed ${cands.length} plugin${cands.length == 1 ? '' : 's'}');
  } catch (e) {
    if (context.mounted) await showPluginError(context, 'Could not install', e);
  }
}

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

Future<List<PluginEntry>?> _pickEntries(BuildContext context, RepoPreview preview) {
  final chosen = <String>{};
  return showDialog<List<PluginEntry>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Plugins in ${preview.name}'),
        content: SizedBox(
          width: 520,
          child: preview.entries.isEmpty
              ? const Text('This repository lists no plugins.')
              : ListView(shrinkWrap: true, children: [
                  for (final e in preview.entries)
                    CheckboxListTile(
                      key: PluginKeys.pick(e.id),
                      value: chosen.contains(e.id),
                      onChanged: (v) => setState(() => v == true ? chosen.add(e.id) : chosen.remove(e.id)),
                      title: Text(e.name),
                      subtitle: Text(e.version.isEmpty ? e.id : 'Version ${e.version}'),
                    ),
                  if (preview.hiddenAdult > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${preview.hiddenAdult} more not shown: adult plugins are not supported yet.'),
                    ),
                ]),
        ),
        actions: [
          TextButton(key: PluginKeys.cancel, autofocus: true, onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            key: PluginKeys.pickNext,
            onPressed: chosen.isEmpty ? null : () => Navigator.of(ctx).pop([for (final e in preview.entries) if (chosen.contains(e.id)) e]),
            child: const Text('Next'),
          ),
        ],
      ),
    ),
  );
}

Future<bool?> _confirmDomains(BuildContext context, List<PluginCandidate> cands, {required bool signed}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Allow these sites?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Each plugin can only reach the sites listed here. It cannot read your files or use the network on its own.'),
          const SizedBox(height: 12),
          for (final c in cands) Padding(padding: const EdgeInsets.only(bottom: 6), child: _domains(c)),
        ]),
      ),
      actions: [
        TextButton(key: PluginKeys.cancel, autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(key: PluginKeys.installConfirm, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Install')),
      ],
    ),
  );
}

/// Adds one plugin from a link to a `.py` file. Unsigned: a warning with the
/// declared domains, Cancel focused, "Install anyway" to continue.
Future<void> addSingleFlow(BuildContext context, {String? url}) async {
  final registry = AppServices.of(context).plugins;
  final address = await askText(
    context,
    title: 'Link to a plugin (.py file)',
    hint: 'https://example.org/plugin.py',
    initial: url,
    acceptFromPhone: true,
  );
  if (address == null || address.trim().isEmpty || !context.mounted) return;
  final PluginCandidate c;
  try {
    c = await _progress(context, 'Checking the plugin...', registry.inspectSingle(address));
  } catch (e) {
    if (context.mounted) await showPluginError(context, 'Could not add the plugin', e);
    return;
  }
  if (!context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Install ${c.name}?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Unsigned', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final w in c.warnings) Padding(padding: const EdgeInsets.only(top: 6), child: Text(w)),
          const SizedBox(height: 12),
          const Text('It will be allowed to reach:'),
          SelectableText(c.allowedHosts.join('\n'), key: const ValueKey('plugins-warning-domains')),
          const SizedBox(height: 12),
          const Text('It runs in the sandbox with no access to your files, and it does not update by itself.'),
        ]),
      ),
      actions: [
        TextButton(key: PluginKeys.cancel, autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(key: PluginKeys.installAnyway, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Install anyway')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  try {
    await registry.installSingle(c);
    if (context.mounted) _say(context, 'Installed ${c.name}');
  } catch (e) {
    if (context.mounted) await showPluginError(context, 'Could not install', e);
  }
}

/// Installs plugins a repository lists that are not installed yet.
Future<void> installOffersFlow(BuildContext context, PluginRepoView repo) async {
  final registry = AppServices.of(context).plugins;
  final chosen = <String>{};
  final picked = await showDialog<List<RepoOffer>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Available from ${repo.name}'),
        content: SizedBox(
          width: 520,
          child: ListView(shrinkWrap: true, children: [
            for (final o in repo.offers)
              CheckboxListTile(
                key: PluginKeys.pick(o.id),
                value: chosen.contains(o.id),
                onChanged: (v) => setState(() => v == true ? chosen.add(o.id) : chosen.remove(o.id)),
                title: Text(o.name),
                subtitle: Text([if (repo.isNew(o)) 'New', if (o.version.isNotEmpty) 'Version ${o.version}'].join(' - ')),
              ),
          ]),
        ),
        actions: [
          TextButton(key: PluginKeys.cancel, autofocus: true, onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            key: PluginKeys.pickNext,
            onPressed: chosen.isEmpty ? null : () => Navigator.of(ctx).pop([for (final o in repo.offers) if (chosen.contains(o.id)) o]),
            child: const Text('Next'),
          ),
        ],
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;
  final List<PluginCandidate> cands;
  try {
    cands = await _progress(context, 'Checking...', registry.inspectOffers(repo.id, picked));
  } catch (e) {
    if (context.mounted) await showPluginError(context, 'Could not check the plugins', e);
    return;
  }
  if (!context.mounted) return;
  if (await _confirmDomains(context, cands, signed: true) != true || !context.mounted) return;
  try {
    await registry.installOffers(repo.id, cands);
  } catch (e) {
    if (context.mounted) await showPluginError(context, 'Could not install', e);
  }
}

/// Shows what an update changes and applies it on "Approve update".
Future<void> reviewUpdateFlow(BuildContext context, InstalledPlugin p) async {
  final registry = AppServices.of(context).plugins;
  final pending = p.pending;
  if (pending == null) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Update needs approval: ${p.name}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('This version changes more than the plugin itself. Review the differences:'),
          const SizedBox(height: 10),
          for (final d in pending.differences)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(d, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 10),
          const Text('Until you approve, the installed version keeps running as before.'),
        ]),
      ),
      actions: [
        TextButton(key: PluginKeys.cancel, autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(key: PluginKeys.approveUpdate, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Approve update')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  try {
    await _progress(context, 'Updating...', registry.approveUpdate(p));
    if (context.mounted) _say(context, '${p.name} updated');
  } catch (e) {
    if (context.mounted) await showPluginError(context, 'Could not update', e);
  }
}

/// "Check for update" for an unsigned plugin.
Future<void> checkUnsignedFlow(BuildContext context, InstalledPlugin p) async {
  final registry = AppServices.of(context).plugins;
  try {
    final r = await _progress(context, 'Checking for an update...', registry.checkUnsigned(p));
    if (!context.mounted) return;
    if (r == UpdateCheck.upToDate) {
      _say(context, '${p.name} is up to date');
    } else if (r == UpdateCheck.needsApproval) {
      final fresh = registry.plugins.value.firstWhere((x) => x.id == p.id, orElse: () => p);
      await reviewUpdateFlow(context, fresh);
    }
  } catch (e) {
    if (context.mounted) await showPluginError(context, 'Could not check', e);
  }
}

/// The Test button: asks for a query, runs the plugin once, shows what came back.
Future<void> testPluginFlow(BuildContext context, InstalledPlugin p) async {
  final registry = AppServices.of(context).plugins;
  final query = await askText(context, title: 'Test ${p.name}: search for', hint: 'a title', kind: TextEntryKind.search);
  if (query == null || query.trim().isEmpty || !context.mounted) return;
  final r = await _progress(context, 'Searching ${p.name}...', registry.test(p, query.trim()));
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(r.ok ? '${r.hits.length} result${r.hits.length == 1 ? '' : 's'}' : 'The test failed'),
      content: SingleChildScrollView(
        key: const ValueKey('plugins-test-result'),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r.elapsed.inMilliseconds} ms'),
          if (!r.ok) Text('Reason: ${r.reason ?? 'unknown'}'),
          if (r.blockedHosts.isNotEmpty) Text('Blocked sites: ${r.blockedHosts.join(', ')}'),
          const SizedBox(height: 8),
          for (final h in r.hits.take(8))
            Text('${h.name}  -  ${h.seeders ?? '?'} seeders${h.sizeBytes == null ? '' : ', ${_size(h.sizeBytes!)}'}'),
        ]),
      ),
      actions: [TextButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
    ),
  );
}

String _size(int bytes) {
  const gb = 1 << 30, mb = 1 << 20;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / mb).round()} MB';
}
