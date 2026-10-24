import 'dart:io';

import 'package:nova_host/nova_host.dart';

import '../core/app_channel.dart';
import '../core/paths.dart';
import '../data/database.dart';
import 'plugin_fetch.dart';
import 'plugin_registry.dart';
import 'plugin_runtime.dart';

/// The end-to-end builds point plugins at a local fixture server over plain
/// http, with fake DNS for `fixture.test`. Release builds leave this empty.
const e2ePluginRepoDefine = String.fromEnvironment('E2E_PLUGIN_REPO');

/// The registry the app uses: real runner for this platform, https-only fetches
/// (http only under the end-to-end define), concurrency sized after the first frame.
PluginRegistry openPluginRegistry({required AppDatabase db, required AppPaths paths}) {
  final test = e2ePluginRepoDefine.isNotEmpty;
  final desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  return PluginRegistry.open(
    db: db,
    paths: paths,
    runner: NovaPluginRunner.forPlatform(
      broker: test
          ? BrokerPolicy(testMode: true, hostOverrides: {
              'fixture.test': InternetAddress.loopbackIPv4,
              'other.test': InternetAddress.loopbackIPv4,
            })
          : const BrokerPolicy(),
    ),
    fetcher: HttpPluginFetcher(allowInsecure: test),
    concurrency: desktop ? 4 : 2,
    concurrencyProbe: () async {
      final info = await AppChannel.memoryInfo();
      return pluginConcurrency(desktop: desktop, lowRam: info != null && (info.lowRam || info.totalMem <= 2 * 1024 * 1024 * 1024));
    },
  );
}
