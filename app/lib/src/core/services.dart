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
import '../features/telegram/telegram_service.dart';
import '../features/torrents/home/popular_source.dart';
import '../features/torrents/home/torrent_home_feed.dart';
import '../features/torrents/torrent_service.dart';
import '../features/websites/websites_service.dart';
import '../features/youtube/feed/taste.dart';
import '../features/youtube/feed/youtube_feed.dart';
import '../features/youtube/youtube_service.dart';
import '../find/find_api.dart';
import '../find/torznab/torznab_provider.dart';
import '../find/torznab/torznab_service.dart';
import '../home/engine/home_engine.dart';
import '../home/home_repository.dart';
import '../home/snapshot.dart';
import '../plugins/plugin_registry.dart';
import '../plugins/plugin_wiring.dart';
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
    required this.telegram,
    required this.snapshots,
    required this.db,
    required this.secrets,
    required this.home,
    required this.catalog,
    required this.findSources,
    required this.torznab,
    required this.torrentHome,
    required this.websites,
    PluginRegistry? plugins,
  }) : plugins = plugins ?? PluginRegistry();

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
    final youtube = YouTubeService(taste: TasteStore(paths.supportFile('youtube_taste.json')), prefs: prefs);
    final db = AppDatabase.open(paths); // opens on its first query
    final plugins = openPluginRegistry(db: db, paths: paths);
    final secrets = openSecretStore(paths);
    final torrents = TorrentService(paths: paths, prefs: prefs);
    final torznab = TorznabService(db: db, secrets: secrets, network: () => torrents.guard.choice);
    return AppServices(
      navigatorKey: navigatorKey,
      paths: paths,
      prefs: prefs,
      resume: await JsonResumeStore.load(paths.supportFile('resume.json')),
      youtube: youtube,
      feed: YouTubeFeed(youtube: youtube, cacheFile: File('${paths.cache.path}/youtube_feed.json')),
      iptv: IptvService(store: JsonFileIptvStore(Directory('${paths.support.path}/iptv'))),
      torrents: torrents,
      receive: ReceiveService(navigatorKey: navigatorKey, paths: paths, prefs: prefs),
      telegram: TelegramService(navigatorKey: navigatorKey, paths: paths, prefs: prefs, secrets: secrets),
      snapshots: snapshots,
      db: db,
      secrets: secrets,
      home: HomeEngine(snapshot: snapshot),
      catalog: const TmdbCatalog(),
      findSources: [plugins, TorznabProviders(torznab)],
      torznab: torznab,
      torrentHome: TorrentHomeFeed(
        sources: TorznabPopularSources(torznab),
        cacheFile: File('${paths.cache.path}/torrent_home.json'),
      ),
      websites: WebsitesService(file: paths.supportFile('websites.json')),
      plugins: plugins,
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
    TelegramService? telegram,
    AppDatabase? db,
    SecretStore? secrets,
    HomeRepository? home,
    CatalogRepository? catalog,
    List<FindProviderSource>? findSources,
    TorznabService? torznab,
    TorrentHomeFeed? torrentHome,
    WebsitesService? websites,
    PluginRegistry? plugins,
  }) {
    // Tests build many; each database is lazy and in memory.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final pluginRegistry = plugins ?? PluginRegistry();
    final key = navigatorKey ?? GlobalKey<NavigatorState>();
    final paths = AppPaths.under('${Directory.systemTemp.path}/chithram-memory');
    final prefs0 = prefs ?? Prefs.memory();
    final youtube0 = youtube ?? YouTubeService(prefs: prefs0);
    final torrents0 = torrents ?? TorrentService(paths: paths, prefs: prefs0);
    final db0 = db ?? AppDatabase(LazyDatabase(() async => NativeDatabase.memory()));
    final secrets0 = secrets ?? MemorySecretStore();
    final torznab0 =
        torznab ?? TorznabService(db: db0, secrets: secrets0, network: () => torrents0.guard.choice);
    return AppServices(
      navigatorKey: key,
      paths: paths,
      prefs: prefs0,
      resume: resume ?? MemoryResumeStore(),
      youtube: youtube0,
      feed: feed ?? YouTubeFeed(youtube: youtube0),
      iptv: iptv ?? IptvService(store: InMemoryIptvStore()),
      torrents: torrents0,
      receive: receive ?? ReceiveService(navigatorKey: key, paths: paths, prefs: prefs0),
      telegram: telegram ?? TelegramService(navigatorKey: key, paths: paths, prefs: prefs0, secrets: secrets0),
      snapshots: SnapshotStore(paths.supportFile('home_snapshot.json')),
      db: db0,
      secrets: secrets0,
      home: home ?? HomeEngine(),
      catalog: catalog ?? const TmdbCatalog(),
      findSources: findSources ?? [pluginRegistry],
      torznab: torznab0,
      torrentHome: torrentHome ?? TorrentHomeFeed(sources: TorznabPopularSources(torznab0)),
      websites: websites ?? WebsitesService(),
      plugins: pluginRegistry,
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

  /// Files sent to the user's own Telegram Saved Messages (TDLib).
  final TelegramService telegram;

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

  /// The user's Torznab endpoints (keys in [secrets]).
  final TorznabService torznab;

  /// Torrent Home's popular rails.
  final TorrentHomeFeed torrentHome;

  /// Sites the user added, read for video without their ads.
  final WebsitesService websites;

  /// Search plugins: install, update, health, and `search` for Torrent Home.
  /// Inert (no plugins) in [AppServices.memory] unless a test passes one.
  final PluginRegistry plugins;

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
