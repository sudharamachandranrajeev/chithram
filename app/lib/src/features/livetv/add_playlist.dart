import 'package:flutter/material.dart';
import 'package:iptv/iptv.dart';

import '../../ui/text_entry.dart';
import 'iptv_service.dart';
import 'suggestions.dart';

/// Widget keys for the Live TV add flows (tests look for them).
abstract final class LiveTvKeys {
  static const addPlaylist = ValueKey('livetv-add');
  static const addUrl = ValueKey('livetv-add-url');
  static ValueKey<String> suggestion(CatalogueSuggestion s) => ValueKey('livetv-suggest-${s.name}');
  static const confirmAdd = ValueKey('livetv-confirm-add');
  static const cancelAdd = ValueKey('livetv-cancel-add');
  static const filterCountry = ValueKey('livetv-filter-country');
  static const filterLanguage = ValueKey('livetv-filter-language');
}

/// Why [url] should not be added as is, or null. A playlist link that carries
/// a login over plain http sends it unencrypted on every refresh.
String? urlWarning(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !u.hasScheme || u.host.isEmpty) return 'That is not a web address.';
  if (u.scheme != 'http' && u.scheme != 'https') return 'Only http and https playlists can be added.';
  return null;
}

/// True when [url] is plain http and carries a login or token.
bool sendsCredentialsInTheClear(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'http') return false;
  if (u.userInfo.isNotEmpty) return true;
  return u.queryParameters.keys.any((k) => RegExp('pass|pwd|token|secret|key|user', caseSensitive: false).hasMatch(k));
}

/// Asks for a playlist URL and a name, warns about credentials over http,
/// then adds and downloads it.
Future<void> addPlaylistFromUrl(BuildContext c, IptvService service, {String? url}) async {
  final entered = url ?? await askText(c, title: 'Playlist URL', hint: 'https://...');
  if (entered == null || entered.isEmpty || !c.mounted) return;
  final bad = urlWarning(entered);
  if (bad != null) {
    _snack(c, bad);
    return;
  }
  if (sendsCredentialsInTheClear(entered)) {
    final go = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('Login sent without encryption'),
        content: const Text(
            'This address starts with http and contains a user name, password or token. '
            'Anyone on the network could read it each time the playlist refreshes.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Add anyway')),
        ],
      ),
    );
    if (go != true || !c.mounted) return;
  }
  final host = Uri.parse(entered).host;
  final name = await askText(c, title: 'Name', hint: 'My playlist', initial: host, kind: TextEntryKind.search);
  if (name == null || !c.mounted) return;
  final result = await service.addM3uUrl(name: name.isEmpty ? host : name, url: entered);
  if (c.mounted) _report(c, name.isEmpty ? host : name, result);
}

/// "Add playlist": a playlist URL, or one of the suggestions not added yet.
Future<void> showAddPlaylist(BuildContext c, IptvService service) async {
  final have = {for (final s in await service.sources()) s.id};
  if (!c.mounted) return;
  final choice = await showDialog<Object>(
    context: c,
    builder: (ctx) => SimpleDialog(
      title: const Text('Add playlist'),
      children: [
        SimpleDialogOption(
          key: LiveTvKeys.addUrl,
          onPressed: () => Navigator.of(ctx).pop('url'),
          child: const ListTile(
            leading: Icon(Icons.link_rounded),
            title: Text('Playlist URL'),
            subtitle: Text('An M3U link you have'),
          ),
        ),
        for (final s in CatalogueSuggestion.values)
          if (!have.contains(s.sourceId))
            SimpleDialogOption(
              key: LiveTvKeys.suggestion(s),
              onPressed: () => Navigator.of(ctx).pop(s),
              child: ListTile(
                leading: const Icon(Icons.public_rounded),
                title: Text(s.name),
                subtitle: const Text('Community catalogue, asks before downloading'),
              ),
            ),
      ],
    ),
  );
  if (!c.mounted || choice == null) return;
  if (choice == 'url') {
    await addPlaylistFromUrl(c, service);
  } else if (choice is CatalogueSuggestion) {
    await addSuggestionFlow(c, service, choice);
  }
}

/// Explains what [s] is and which host it contacts, and downloads nothing
/// unless the user confirms.
Future<void> addSuggestionFlow(BuildContext c, IptvService service, CatalogueSuggestion s) async {
  final country = TextEditingController();
  final language = TextEditingController();
  final ok = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text('Add ${s.name}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.blurb),
            const SizedBox(height: 12),
            Text('Nothing has been downloaded. If you add it, Chithram connects to ${s.host} '
                'and, for the channels you play, to the stream hosts they list.'),
            if (s.filterable) ...[
              const SizedBox(height: 12),
              TextField(
                key: LiveTvKeys.filterCountry,
                controller: country,
                decoration: const InputDecoration(labelText: 'Country code (optional)', hintText: 'IN'),
              ),
              TextField(
                key: LiveTvKeys.filterLanguage,
                controller: language,
                decoration: const InputDecoration(labelText: 'Language code (optional)', hintText: 'mal'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            key: LiveTvKeys.cancelAdd,
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            key: LiveTvKeys.confirmAdd, onPressed: () => Navigator.of(ctx).pop(true), child: Text('Add ${s.name}')),
      ],
    ),
  );
  final cc = country.text, ll = language.text;
  country.dispose();
  language.dispose();
  if (ok != true || !c.mounted) return;
  final result = await service.addSuggestion(s, country: cc, language: ll);
  if (c.mounted) _report(c, s.name, result);
}

void _report(BuildContext c, String name, RefreshResult r) {
  final msg = switch (r.status) {
    RefreshStatus.updated => '$name added: ${r.total} channels.',
    RefreshStatus.failed || RefreshStatus.deprecated => '$name was added, but loading it failed. Try Refresh later.',
    _ => '$name added.',
  };
  _snack(c, msg);
}

void _snack(BuildContext c, String msg) => ScaffoldMessenger.maybeOf(c)?.showSnackBar(SnackBar(content: Text(msg)));
