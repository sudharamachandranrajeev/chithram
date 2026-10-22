import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/core/services.dart';
import 'src/intake/intake.dart';
import 'src/smoke.dart';
import 'src/ui/app.dart';
import 'src/ui/search_page.dart';

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
  // "Search for this text" in the intake prompt.
  IntakeHooks.search = openSearch;
  runApp(ChithramApp(services: await AppServices.open()));
  final smoke = smokeTarget(args);
  if (smoke != null) unawaited(runSmoke(smoke));
}
