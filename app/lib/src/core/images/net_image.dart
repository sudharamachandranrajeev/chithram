import 'package:flutter/widgets.dart';

/// R0 stub (WP-B replaces it with the disk cache): decodes at the physical
/// [width] over plain HTTP.
ImageProvider netImage(String url, {required int width}) =>
    ResizeImage(NetworkImage(url), width: width, allowUpscaling: false);

/// Stub: downloads nothing.
Future<void> prefetchToDisk(Iterable<String> urls) async {}

/// Stub: warms nothing; false means "not decoded yet".
Future<bool> precacheFromDisk(
  BuildContext c,
  String url, {
  required int width,
  Duration timeout = const Duration(milliseconds: 300),
}) async =>
    false;
