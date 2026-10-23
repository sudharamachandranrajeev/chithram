import 'dart:io';

import 'package:flutter/services.dart';

import '../ui/common/form_factor.dart' show appChannel;

/// Device facts from the platform (`dev.chithram/app`), Android only. Anywhere
/// else (desktop, tests) the calls do nothing and [memoryInfo] says so.
abstract final class AppChannel {
  /// Marks the first frame of Home, the end of the cold start ("Fully drawn").
  static Future<void> reportFullyDrawn() async {
    if (!Platform.isAndroid) return;
    try {
      await appChannel.invokeMethod<void>('reportFullyDrawn');
    } on PlatformException {
      // Measurement only.
    } on MissingPluginException {
      // Not running inside the app (tests).
    }
  }

  /// Total RAM and the low-RAM flag; null when the platform cannot say.
  static Future<MemoryInfo?> memoryInfo() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await appChannel.invokeMapMethod<String, Object?>('memoryInfo');
      if (m == null) return null;
      return MemoryInfo(totalMem: (m['totalMem'] as num).toInt(), lowRam: m['lowRam'] == true);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

class MemoryInfo {
  const MemoryInfo({required this.totalMem, required this.lowRam});
  final int totalMem;
  final bool lowRam;

  /// In-memory `imageCache` budget in bytes: 40 MB up to 2 GB RAM, 80 MB up to
  /// 4 GB, else 128 MB.
  int get imageCacheBytes {
    const gb = 1 << 30;
    if (lowRam || totalMem <= 2 * gb) return 40 << 20;
    if (totalMem <= 4 * gb) return 80 << 20;
    return 128 << 20;
  }
}
