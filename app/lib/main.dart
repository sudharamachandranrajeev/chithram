import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    // Loads libmpv; the release smoke tests check it got this far.
    try {
      MediaKit.ensureInitialized();
    } catch (error) {
      debugPrint('libmpv could not be loaded: $error');
    }
  }
  runApp(const ChithramApp());
}
