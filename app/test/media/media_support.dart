// Fakes and pumping helpers shared by the Media tests.
import 'dart:async';
import 'dart:typed_data';

import 'package:chithram/src/core/prefs.dart';
import 'package:chithram/src/core/services.dart';
import 'package:chithram/src/media/gateway_client.dart';
import 'package:chithram/src/media/media_config.dart';
import 'package:chithram/src/media/media_service.dart';
import 'package:chithram/src/media/models.dart';
import 'package:chithram/src/media/token_store.dart';
import 'package:chithram/src/theme.dart';
import 'package:chithram/src/ui/common/form_factor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final testFingerprint = normalizeFingerprint('ab' * 32)!;
const testToken = 'T0kenT0kenT0kenT0kenT0kenT0kenT0kenT0kenT0k';

/// A gateway that answers from memory. Counts calls, never opens a socket.
class FakeGateway extends GatewayClient {
  FakeGateway({this.role = MediaRole.admin, this.searchHits = const [], super.token = testToken})
    : super(host: const GatewayHost('media.test', 8443), fingerprint: testFingerprint);

  final MediaRole role;
  List<SearchItem> searchHits;
  List<RequestItem> requestItems = [];
  List<DownloadItem> downloadItems = [];
  List<LibraryItem> libraryItems = [];
  Object? searchError;
  Object? meError;
  final calls = <String>[];
  Completer<List<SearchItem>>? searchGate;

  @override
  Future<Me> me() async {
    calls.add('me');
    if (meError != null) throw meError!;
    return Me(user: 'sam', role: role);
  }

  @override
  Future<List<SearchItem>> search(String query) async {
    calls.add('search:$query');
    if (searchError != null) throw searchError!;
    if (searchGate != null) return searchGate!.future;
    return searchHits;
  }

  @override
  Future<RequestItem> createRequest(int tmdbId, String type) async {
    calls.add('request:$type:$tmdbId');
    return RequestItem(id: 1, tmdbId: tmdbId, type: type, title: 't', status: MediaStatus.awaitingApproval);
  }

  @override
  Future<Paged<RequestItem>> requests({String? cursor}) async {
    calls.add('requests');
    return Paged(requestItems, null);
  }

  @override
  Future<RequestItem> decide(int id, {required bool approve}) async {
    calls.add('${approve ? 'approve' : 'decline'}:$id');
    final r = requestItems.firstWhere((e) => e.id == id);
    return r.withStatus(approve ? MediaStatus.approved : MediaStatus.failed);
  }

  @override
  Future<List<DownloadItem>> downloads() async {
    calls.add('downloads');
    return downloadItems;
  }

  @override
  Future<Paged<LibraryItem>> library(LibraryKind kind, {String? cursor}) async {
    calls.add('library:${kind.name}');
    return Paged(libraryItems, null);
  }

  @override
  Future<Uint8List> image(String path) async {
    calls.add('image');
    throw const GatewayException(GatewayErrorKind.notFound, 'no image in tests');
  }

  @override
  Future<PairResult> pair(String code, String deviceName) async {
    calls.add('pair:$code');
    return PairResult(token: testToken, deviceId: 'dev', user: 'sam', role: role);
  }
}

/// A service whose gateway is [gateway]; [made] counts client constructions
/// (a flag-off service must make none).
class Harness {
  Harness({
    bool enabled = true,
    bool paired = true,
    MediaRole role = MediaRole.admin,
    FakeGateway? gateway,
    Map<String, Object?> prefsInit = const {},
  }) : gateway = gateway ?? FakeGateway(role: role),
       tokens = MemoryTokenStore(paired ? testToken : null),
       prefs = Prefs.memory({
         mediaEnabledPref: enabled,
         if (paired) ...{
           mediaHostPref: 'media.test',
           mediaPortPref: 8443,
           mediaFingerprintPref: testFingerprint,
         },
         ...prefsInit,
       }) {
    service = MediaService(
      prefs: prefs,
      tokens: tokens,
      factory: (host, fp, token) {
        made++;
        return this.gateway;
      },
    );
  }

  final FakeGateway gateway;
  final MemoryTokenStore tokens;
  final Prefs prefs;
  late final MediaService service;
  int made = 0;

  AppServices get services => AppServices.memory(prefs: prefs, media: service);
}

/// Pumps [child] under app services, a form factor and a text scale.
Future<void> pumpMedia(
  WidgetTester tester,
  Widget child, {
  required AppServices services,
  FormFactor form = FormFactor.desktop,
  Size? size,
  double textScale = 1.0,
}) async {
  final s = size ??
      switch (form) {
        FormFactor.phone => const Size(360, 740),
        FormFactor.tv => const Size(960, 540),
        FormFactor.desktop => const Size(1280, 800),
      };
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppServicesScope(
      services: services,
      child: FormScope(
        form: form,
        child: MaterialApp(
          theme: buildChithramTheme(form: form),
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: c!,
          ),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
