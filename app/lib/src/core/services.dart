import 'dart:io';

import 'package:flutter/material.dart';
import 'package:iptv/iptv.dart';

import '../features/livetv/iptv_service.dart';
import '../features/receive/receive_service.dart';
import '../features/torrents/torrent_service.dart';
import '../features/youtube/youtube_service.dart';
import 'paths.dart';
import 'prefs.dart';
import 'resume_store.dart';

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
    required this.iptv,
    required this.torrents,
    required this.receive,
  });

  /// The real services: files under the app support directory.
  static Future<AppServices> open() async {
    final paths = await AppPaths.resolve();
    final prefs = await Prefs.load(paths.supportFile('prefs.json'));
    final navigatorKey = GlobalKey<NavigatorState>();
    return AppServices(
      navigatorKey: navigatorKey,
      paths: paths,
      prefs: prefs,
      // The JSON store replaces this with the player work package.
      resume: MemoryResumeStore(),
      youtube: YouTubeService(),
      iptv: IptvService(store: JsonFileIptvStore(Directory('${paths.support.path}/iptv'))),
      torrents: TorrentService(paths: paths, prefs: prefs),
      receive: ReceiveService(navigatorKey: navigatorKey, paths: paths, prefs: prefs),
    );
  }

  /// Nothing touches the disk or the network until used. The default for
  /// `ChithramApp()` in tests; pass fakes for what a test cares about.
  factory AppServices.memory({
    GlobalKey<NavigatorState>? navigatorKey,
    Prefs? prefs,
    ResumeStore? resume,
    YouTubeService? youtube,
    IptvService? iptv,
    TorrentService? torrents,
    ReceiveService? receive,
  }) {
    final key = navigatorKey ?? GlobalKey<NavigatorState>();
    final paths = AppPaths.under('${Directory.systemTemp.path}/chithram-memory');
    final prefs0 = prefs ?? Prefs.memory();
    return AppServices(
      navigatorKey: key,
      paths: paths,
      prefs: prefs0,
      resume: resume ?? MemoryResumeStore(),
      youtube: youtube ?? YouTubeService(),
      iptv: iptv ?? IptvService(store: InMemoryIptvStore()),
      torrents: torrents ?? TorrentService(paths: paths, prefs: prefs0),
      receive: receive ?? ReceiveService(navigatorKey: key, paths: paths, prefs: prefs0),
    );
  }

  /// Lets incoming transfers and intents show prompts from anywhere.
  final GlobalKey<NavigatorState> navigatorKey;
  final AppPaths paths;
  final Prefs prefs;
  final ResumeStore resume;
  final YouTubeService youtube;
  final IptvService iptv;
  final TorrentService torrents;
  final ReceiveService receive;

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
