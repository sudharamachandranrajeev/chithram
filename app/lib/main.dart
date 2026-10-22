import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/core/app_channel.dart';
import 'src/core/perf.dart';
import 'src/core/services.dart';
import 'src/intake/intake.dart';
import 'src/smoke.dart';
import 'src/ui/common/app.dart';
import 'src/ui/common/form_factor.dart';
import 'src/ui/common/search_page.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    // Loads libmpv; the release smoke tests check it got this far.
    try {
      MediaKit.ensureInitialized();
    } catch (error) {
      debugPrint('libmpv could not be loaded: $error');
    }
  }
  FrameProbe.install(); // only with --dart-define=PERF_PROBE=true
  // Decided once, from the device (never the window size).
  final form = resolveFormFactor(
    platform: defaultTargetPlatform,
    define: formFactorDefine,
    arg: formFactorArg(args),
  );
  if (form != null) {
    final view = PlatformDispatcher.instance.views.first;
    OrientationPolicy.apply(
      form,
      shortestSideDp: view.physicalSize.shortestSide / view.devicePixelRatio,
    );
  }
  // "Search for this text" in the intake prompt.
  IntakeHooks.search = openSearch;
  runApp(ChithramApp(services: await AppServices.open(), formFactor: form));
  // After the first frame: the cold-start mark, then the image cache budget
  // from the device's RAM. Nothing here runs before Home is on screen.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Perf.mark('first_frame');
    unawaited(AppChannel.reportFullyDrawn());
    unawaited(_sizeImageCache());
  });
  final smoke = smokeTarget(args);
  if (smoke != null) unawaited(runSmoke(smoke));
}

Future<void> _sizeImageCache() async {
  final info = await AppChannel.memoryInfo();
  if (info == null) return;
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSizeBytes = info.imageCacheBytes;
  cache.maximumSize = 400;
}
