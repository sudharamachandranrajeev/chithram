import 'dart:io';
import 'dart:typed_data';

import 'package:chithram/src/core/paths.dart';
import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/secrets.dart';
import 'package:chithram/src/features/telegram/telegram_service.dart';
import 'package:chithram/src/features/telegram/telegram_store.dart';
import 'package:chithram/src/player/play_request.dart';
import 'package:flutter/material.dart';
import 'package:tdlib/tdlib.dart';

TgMedia media(
  int id, {
  String? name,
  DateTime? date,
  int size = 1000,
  TgMediaKind kind = TgMediaKind.video,
  String mime = 'video/mp4',
}) =>
    TgMedia(
      chatId: 1,
      messageId: id,
      date: date ?? DateTime.utc(2026, 10, 24, 12),
      kind: kind,
      name: name ?? 'file$id.mp4',
      mime: mime,
      file: TgFile(id: id * 10, size: size),
    );

Uint8List bytes(int n) => Uint8List.fromList(List.generate(n, (i) => i % 251));

/// A service on a fake client. [played] gets every PlayRequest.
class Rig {
  Rig({
    int? apiId = 1,
    String? apiHash = 'h',
    bool memoryStore = true,
    this.clock = _now,
    int historyCount = 20,
    int maxBytes = 4 * 1024 * 1024 * 1024,
  })  : fake = FakeTelegramClient(),
        navigatorKey = GlobalKey<NavigatorState>(),
        prefs = Prefs.memory(),
        secrets = MemorySecretStore(),
        dir = Directory.systemTemp.createTempSync('tg-test') {
    paths = AppPaths.under(dir.path);
    service = TelegramService(
      navigatorKey: navigatorKey,
      paths: paths,
      prefs: prefs,
      secrets: secrets,
      apiId: apiId,
      apiHash: apiHash,
      clientFactory: () async => fake,
      isForeground: () => foreground,
      clock: () => clock(),
      player: (context, request) async => played.add(request),
      store: memoryStore ? TelegramStore(null) : null,
      historyCount: historyCount,
      maxBytes: maxBytes,
    );
  }

  static DateTime _now() => DateTime.utc(2026, 10, 24, 12, 5);

  final FakeTelegramClient fake;
  final GlobalKey<NavigatorState> navigatorKey;
  final Prefs prefs;
  final MemorySecretStore secrets;
  final Directory dir;
  late final AppPaths paths;
  late final TelegramService service;
  DateTime Function() clock;
  bool foreground = true;
  final played = <PlayRequest>[];

  /// Brings the fake to the signed-in state.
  Future<void> signIn() async {
    await service.start();
    fake.emitAuth(const TgAuthWaitPhone());
    await Future<void>.delayed(Duration.zero);
    fake.emitAuth(const TgAuthReady());
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() {
    service.dispose();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
