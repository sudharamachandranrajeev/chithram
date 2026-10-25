import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tmdb/tmdb.dart';

import '../../catalog/catalog_worker.dart';
import '../../catalog/tmdb_catalog.dart';
import '../../core/services.dart';
import '../../ui/common/text_entry.dart';

final _busy = Expando<ValueNotifier<bool>>();
ValueNotifier<bool> metadataBusy(AppServices services) =>
    _busy[services] ??= ValueNotifier(false);
Future<void> _exclusive(
  AppServices services,
  Future<void> Function() action,
) async {
  final busy = metadataBusy(services);
  if (busy.value) {
    throw const TmdbException(
      'Wait for the current metadata change to finish.',
    );
  }
  busy.value = true;
  try {
    await action();
  } finally {
    busy.value = false;
  }
}

Future<void> _purge(AppServices services) async {
  await services.db.cacheDao.purgeTmdb();
  await services.snapshots.delete();
  final images = services.paths.cacheDir('img');
  if (await images.exists()) await images.delete(recursive: true);
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}

/// Validates before writing anything. A rejected replacement leaves the old
/// working key intact. No key, response body or URL enters error text.
Future<void> saveMetadataKey(
  AppServices services,
  String input, {
  CatalogWorker? worker,
}) => _exclusive(services, () async {
  final key = input.trim();
  authMode(key);
  final temporary = worker ?? CatalogWorker();
  try {
    await temporary.fetch(key: key, path: 'configuration');
    final catalog = services.catalog is TmdbCatalog
        ? services.catalog as TmdbCatalog
        : null;
    await catalog?.suspend();
    try {
      await _purge(services);
      await services.secrets.write(TmdbCatalog.secretKey, key);
      await services.prefs.set('tmdb.configured', true);
    } finally {
      catalog?.resume();
    }
    await services.home.refresh(force: true);
  } finally {
    if (worker == null) await temporary.close();
  }
});

Future<void> removeMetadataKey(AppServices s) => _exclusive(s, () async {
  final catalog = s.catalog is TmdbCatalog ? s.catalog as TmdbCatalog : null;
  await catalog?.suspend();
  try {
    await s.prefs.set('tmdb.configured', false);
    // Cleanup still runs if the keyring is temporarily unavailable.
    try {
      await s.secrets.delete(TmdbCatalog.secretKey);
    } finally {
      await _purge(s);
    }
  } finally {
    catalog?.resume();
  }
  await s.home.refresh(force: true);
});

Future<void> openMetadataSetup(BuildContext context) async {
  final services = AppServices.of(context);
  final key = await askText(
    context,
    title: 'Set up TMDB metadata',
    hint: 'Get your free key at themoviedb.org/settings/api. Paste the API key or read access token.',
    kind: TextEntryKind.url,
    acceptFromPhone: true,
  );
  if (key == null || !context.mounted) return;
  try {
    await saveMetadataKey(services, key);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Metadata is ready.')));
    }
  } on TmdbException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  } on FileSystemException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save metadata settings.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the metadata key.')),
      );
    }
  }
}
