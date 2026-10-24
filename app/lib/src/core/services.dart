import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:iptv/iptv.dart' hide SecretStore;

import '../catalog/catalog_repository.dart';
import '../catalog/tmdb_catalog.dart';
import '../data/database.dart';
import '../features/livetv/iptv_service.dart';
import '../features/receive/receive_service.dart';
import '../features/torrents/torrent_service.dart';
import '../features/youtube/feed/taste.dart';
import '../features/youtube/feed/youtube_feed.dart';
import '../features/youtube/youtube_service.dart';
import '../find/find_api.dart';
import '../home/engine/home_engine.dart';
import '../home/home_repository.dart';
import '../home/snapshot.dart';
import '../plugins/plugin_registry.dart';
import 'paths.dart';
import 'prefs.dart';
import 'resume_store.dart';
import 'resume_store_json.dart';
import 'secrets.dart';

/// The app's services, built once in `main()` and read with
/// [AppServices.of]. Plain objects (`ChangeNotifier` or `ValueListenable`
/// where they change), so widget tests can pass fakes to [AppServicesScope].
class AppServices {
  AppServices({
    required this.navigatorKey,
    required this.paths,
    required this.prefs,
    required this.resume,
    required this.youtube,
    required this.feed,
    required this.iptv,
    required this.torrents,
    required this.receive,
    required this.snapshots,
    required this.db,
    required this.secrets,
    required this.home,
    required this.catalog,
    required this.findSources,
  });

  /// The real services: files under the app support directory. Reads only
  /// `prefs.json` and `home_snapshot.json` (in parallel); the database, the
  /// secret store, plugins and the network stay untouched until after the
  /// first frame.
  static Future<AppServices> open() async {
    final paths = await AppPaths.resolve();
    final snapshots = SnapshotStore(paths.supportFile('home_snapshot.json'));
    final (prefs, snapshot) = await (
      Prefs.load(paths.supportFile('prefs.json')),
      snapshots.load(),
    ).wait;
    final navigatorKey = GlobalKey<NavigatorState>();
    final plugins = PluginRegistry();
    final youtube = YouTubeService(taste: TasteStore(paths.supportFile('youtube_taste.json')));
    return AppServices(
      navigatorKey: navigatorKey,
      paths: paths,
      prefs: prefs,
      resume: await JsonResumeStore.load(paths.supportFile('resume.json')),
      youtube: youtube,
      feed: YouTubeFeed(youtube: youtube, cacheFile: File('${paths.cache.path}/youtube_feed.json')),
      iptv: IptvService(store: JsonFileIptvStore(Directory('${paths.support.path}/iptv'))),
      torrents: TorrentService(paths: paths, prefs: prefs),
      receive: ReceiveService(navigatorKey: navigatorKey, paths: paths, prefs: prefs),
      snapshots: snapshots,
      db: AppDatabase.open(paths), // opens on its first query
      secrets: openSecretStore(paths),
      home: HomeEngine(snapshot: snapshot),
      catalog: const TmdbCatalog(),
      findSources: [plugins],
    );
  }

  /// Nothing touches the disk or the network until used. The default for
  /// `ChithramApp()` in tests; pass fakes for what a test cares about.
  factory AppServices.memory({
    GlobalKey<NavigatorState>? navigatorKey,
    Prefs? prefs,
    ResumeStore? resume,
    YouTubeService? youtube,
    YouTubeFeed? feed,
    IptvService? iptv,
    TorrentService? torrents,
    ReceiveService? receive,
    AppDatabase? db,
    SecretStore? secrets,
    HomeRepository? home,
    CatalogRepository? catalog,
    List<FindProviderSource>? findSources,
  }) {
    // Tests build many; each database is lazy and in memory.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final key = navigatorKey ?? GlobalKey<NavigatorState>();
    final paths = AppPaths.under('${Directory.systemTemp.path}/chithram-memory');
    final prefs0 = prefs ?? Prefs.memory();
    final youtube0 = youtube ?? YouTubeService();
    return AppServices(
      navigatorKey: key,
      paths: paths,
      prefs: prefs0,
      resume: resume ?? MemoryResumeStore(),
      youtube: youtube0,
      feed: feed ?? YouTubeFeed(youtube: youtube0),
      iptv: iptv ?? IptvService(store: InMemoryIptvStore()),
      torrents: torrents ?? TorrentService(paths: paths, prefs: prefs0),
      receive: receive ?? ReceiveService(navigatorKey: key, paths: paths, prefs: prefs0),
      snapshots: SnapshotStore(paths.supportFile('home_snapshot.json')),
      db: db ?? AppDatabase(LazyDatabase(() async => NativeDatabase.memory())),
      secrets: secrets ?? MemorySecretStore(),
      home: home ?? HomeEngine(),
      catalog: catalog ?? const TmdbCatalog(),
      findSources: findSources ?? [PluginRegistry()],
    );
  }

  /// Lets incoming transfers and intents show prompts from anywhere.
  final GlobalKey<NavigatorState> navigatorKey;
  final AppPaths paths;
  final Prefs prefs;
  final ResumeStore resume;
  final YouTubeService youtube;

  /// Home's YouTube rails.
  final YouTubeFeed feed;
  final IptvService iptv;
  final TorrentService torrents;
  final ReceiveService receive;

  /// `home_snapshot.json`: Home's first frame.
  final SnapshotStore snapshots;

  /// SQLite (HTTP cache, plugins, Torznab, provider health); opened on first use.
  final AppDatabase db;

  /// The TMDB and Torznab keys.
  final SecretStore secrets;
  final HomeRepository home;
  final CatalogRepository catalog;

  /// Where Find sources gets its providers (plugins, Torznab, YouTube, IPTV).
  final List<FindProviderSource> findSources;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppServicesScope>();
    assert(scope != null, 'No AppServicesScope above this context');
    return scope!.services;
  }
}

class AppServicesScope extends InheritedWidget {
  const AppServicesScope({super.key, required this.services, required super.child});

  final AppServices services;

  @override
  bool updateShouldNotify(AppServicesScope oldWidget) => services != oldWidget.services;
}
