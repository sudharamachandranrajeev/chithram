import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// String extras of the Android launch intent (`am start --es key value`).
/// Empty on other platforms. The spike pages use it to pick URLs in CI.
Future<Map<String, String>> launchArgs() async {
  if (!Platform.isAndroid) return const <String, String>{};
  try {
    final raw = await const MethodChannel('chithram_player/methods')
        .invokeMapMethod<String, String>('launchArgs');
    return raw ?? const <String, String>{};
  } on PlatformException {
    return const <String, String>{};
  } on MissingPluginException {
    return const <String, String>{};
  }
}
