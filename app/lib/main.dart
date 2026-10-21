import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/core/services.dart';
import 'src/smoke.dart';
import 'src/ui/app.dart';
import 'src/ui/form_factor.dart';

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
  runApp(ChithramApp(services: await AppServices.open(), formFactor: form));
  final smoke = smokeTarget(args);
  if (smoke != null) unawaited(runSmoke(smoke));
}
