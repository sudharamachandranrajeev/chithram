import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/services.dart';

/// Short UI sounds (synthesised by `app/tool/make_sfx.py`).
enum Sfx { move, key, delete, open, close, submit }

/// Prefs key: UI sounds on (default) or off.
const soundsPref = 'ui.sounds';

/// Whether this build plays UI sounds at all: Android, through a SoundPool.
/// Desktop and tests stay silent.
bool get sfxSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android && !Platform.environment.containsKey('FLUTTER_TEST');

const _channel = MethodChannel('dev.chithram/app');
Future<void>? _loading;

/// Copies the sounds to the cache and hands them to the SoundPool, once.
/// Call when a keyboard opens so its first key is not silent.
Future<void> preloadSfx(BuildContext context) {
  if (!sfxSupported) return Future.value();
  final cache = AppServices.of(context).paths.cache;
  return _loading ??= _load(cache).catchError((Object _) => _loading = null);
}

Future<void> _load(Directory cache) async {
  final dir = Directory('${cache.path}/sfx');
  await dir.create(recursive: true);
  final paths = <String, String>{};
  for (final s in Sfx.values) {
    final data = await rootBundle.load('assets/sfx/${s.name}.wav');
    final file = File('${dir.path}/${s.name}.wav');
    if (!await file.exists() || await file.length() != data.lengthInBytes) {
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
    paths[s.name] = file.path;
  }
  await _channel.invokeMethod<void>('sfxLoad', paths);
}

/// Plays [sound] unless sounds are off in Settings. Never throws.
void playSfx(BuildContext context, Sfx sound) {
  if (!sfxSupported || !AppServices.of(context).prefs.getBool(soundsPref, fallback: true)) return;
  unawaited(
    preloadSfx(context).then((_) => _channel.invokeMethod<void>('sfxPlay', sound.name)).catchError((Object _) {}),
  );
}
