import 'package:flutter/material.dart';
import 'package:tmdb/tmdb.dart';

import '../../core/services.dart';
import '../../catalog/tmdb_catalog.dart';
import '../../ui/common/text_entry.dart';
import 'attribution.dart';
import 'metadata_setup.dart';

class MetadataSettings extends StatelessWidget {
  const MetadataSettings({super.key});

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is TmdbException
                  ? error.message
                  : 'Could not update metadata settings.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _edit(
    BuildContext context,
    String key,
    String title,
    RegExp valid,
  ) async {
    final s = AppServices.of(context);
    final input = await askText(
      context,
      title: title,
      initial: s.prefs.getString(key),
      acceptFromPhone: true,
    );
    if (input == null || !context.mounted) return;
    if (input.isNotEmpty && !valid.hasMatch(input)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a valid language or region code.'),
          ),
        );
      }
      return;
    }
    await _run(context, () async {
      final catalog = s.catalog is TmdbCatalog
          ? s.catalog as TmdbCatalog
          : null;
      await catalog?.suspend();
      try {
        await s.prefs.set(key, input.isEmpty ? null : input);
      } finally {
        catalog?.resume();
      }
      await s.home.refresh(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.prefs, metadataBusy(s)]),
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Metadata',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const Text(
              'Films and TV details come from TMDB with your own key.',
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: metadataBusy(s).value
                      ? null
                      : () => openMetadataSetup(context),
                  child: Text(
                    s.prefs.getBool('tmdb.configured')
                        ? 'Replace key'
                        : 'Add key',
                  ),
                ),
                if (s.prefs.getBool('tmdb.configured'))
                  OutlinedButton(
                    onPressed: metadataBusy(s).value
                        ? null
                        : () => _run(context, () => removeMetadataKey(s)),
                    child: const Text('Remove key and cached metadata'),
                  ),
                OutlinedButton(
                  onPressed: metadataBusy(s).value
                      ? null
                      : () => _edit(
                          context,
                          'tmdb.language',
                          'Language (for example en-US)',
                          RegExp(r'^[a-z]{2}(?:-[A-Z]{2})?$'),
                        ),
                  child: Text(
                    'Language: ${s.prefs.getString('tmdb.language') ?? 'Device default'}',
                  ),
                ),
                OutlinedButton(
                  onPressed: metadataBusy(s).value
                      ? null
                      : () => _edit(
                          context,
                          'tmdb.region',
                          'Region (for example IN)',
                          RegExp(r'^[A-Z]{2}$'),
                        ),
                  child: Text(
                    'Region: ${s.prefs.getString('tmdb.region') ?? 'Device default'}',
                  ),
                ),
                OutlinedButton(
                  onPressed: metadataBusy(s).value
                      ? null
                      : () => _edit(
                          context,
                          'tmdb.originalLanguages',
                          'Popular in (up to four language codes, comma separated)',
                          RegExp(r'^[a-z]{2}(?:,[a-z]{2}){0,3}$'),
                        ),
                  child: Text(
                    'Popular in: ${s.prefs.getString('tmdb.originalLanguages') ?? 'None'}',
                  ),
                ),
              ],
            ),
            if (s.secrets.isFallback)
              const Text(
                'The system keyring is unavailable. Keys are stored in a private file accessible only to your account.',
              ),
            const MetadataAttribution(),
          ],
        ),
      ),
    );
  }
}
