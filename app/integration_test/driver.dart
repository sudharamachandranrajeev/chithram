import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host side of `flutter drive`: writes each takeScreenshot() PNG to
/// $SCREENSHOT_DIR (default ./screenshots).
Future<void> main() {
  final dir = Platform.environment['SCREENSHOT_DIR'] ?? 'screenshots';
  return integrationDriver(
    onScreenshot: (String name, List<int> image, [Map<String, Object?>? args]) async {
      final file = File('$dir/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(image);
      return true;
    },
  );
}
