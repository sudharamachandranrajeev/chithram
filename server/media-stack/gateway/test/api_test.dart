import 'dart:convert';
import 'dart:io';

import 'package:chithram_gateway/src/api.dart';
import 'package:chithram_gateway/src/config.dart';
import 'package:chithram_gateway/src/pairing.dart';
import 'package:chithram_gateway/src/roles.dart';
import 'package:chithram_gateway/src/state.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late StateStore store;
  late Handler h;

  Request req(String method, String path, {String? token, Object? body}) =>
      Request(
        method,
        Uri.parse('https://gw$path'),
        headers: {
          'authorization': ?(token == null ? null : 'Bearer $token'),
          if (body != null) 'content-type': 'application/json',
        },
        body: body == null ? null : jsonEncode(body),
      );

  /// Creates user + device with [role]; returns the device token.
  String device(String userId, Role role) {
    return store.update((s) {
      s.users[userId] = UserRec('user-$userId', role);
      return redeemCode(
        s,
        issueCode(s, userId, DateTime.now().millisecondsSinceEpoch),
        'test',
        DateTime.now().millisecondsSinceEpoch,
      )!.token;
    });
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gw-test');
    store = StateStore(tmp.path);
    final cfg = Config.fromEnv({
      'STATE_DIR': tmp.path,
      'SECRETS_DIR': tmp.path,
    });
    h = Gateway(cfg, store, userActive: (_) async => true).handler;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<int> status(Request r) async => (await h(r)).statusCode;

  test('no token, wrong token, malformed header -> 401', () async {
    expect(await status(req('GET', '/v1/me')), 401);
    expect(await status(req('GET', '/v1/me', token: 'x' * 43)), 401);
    expect(await status(req('GET', '/v1/me', token: 'short')), 401);
    final bad = Request(
      'GET',
      Uri.parse('https://gw/v1/me'),
      headers: {'authorization': 'Basic abc'},
    );
    expect((await h(bad)).statusCode, 401);
  });

  test('valid token returns user and role', () async {
    final t = device('u1', Role.requester);
    final res = await h(req('GET', '/v1/me', token: t));
    expect(res.statusCode, 200);
    expect(jsonDecode(await res.readAsString()), {
      'user': 'user-u1',
      'role': 'requester',
    });
  });

  test('revoked device -> 401', () async {
    final t = device('u1', Role.viewer);
    store.update((s) => s.devices.clear());
    expect(await status(req('GET', '/v1/me', token: t)), 401);
  });

  test('inactive Jellyfin user -> 401', () async {
    final cfg = Config.fromEnv({'STATE_DIR': tmp.path});
    final h2 = Gateway(cfg, store, userActive: (_) async => false).handler;
    final t = device('u1', Role.admin);
    expect((await h2(req('GET', '/v1/me', token: t))).statusCode, 401);
  });

  test(
    'viewer cannot create requests; invalid input is 400 for requester',
    () async {
      final v = device('v', Role.viewer);
      expect(
        await status(
          req(
            'POST',
            '/v1/requests',
            token: v,
            body: {'tmdbId': 10331, 'type': 'movie'},
          ),
        ),
        403,
      );
      final r = device('r', Role.requester);
      expect(
        await status(
          req(
            'POST',
            '/v1/requests',
            token: r,
            body: {'tmdbId': '10331', 'type': 'movie'},
          ),
        ),
        400,
      );
      expect(
        await status(
          req(
            'POST',
            '/v1/requests',
            token: r,
            body: {'tmdbId': 1, 'type': 'music'},
          ),
        ),
        400,
      );
    },
  );

  test('approve, decline and downloads are admin-only', () async {
    for (final role in [Role.requester, Role.viewer]) {
      final t = device('u-${role.name}', role);
      expect(
        await status(req('POST', '/v1/requests/5/approve', token: t)),
        403,
      );
      expect(
        await status(req('POST', '/v1/requests/5/decline', token: t)),
        403,
      );
      expect(await status(req('GET', '/v1/downloads', token: t)), 403);
    }
  });

  test('input validation on query, library, images', () async {
    final t = device('r', Role.requester);
    expect(await status(req('GET', '/v1/search', token: t)), 400);
    expect(
      await status(req('GET', '/v1/search?q=${'a' * 200}', token: t)),
      400,
    );
    expect(await status(req('GET', '/v1/library?type=books', token: t)), 400);
    expect(
      await status(req('GET', '/v1/library?type=movies&cursor=-5', token: t)),
      400,
    );
    expect(await status(req('GET', '/v1/images/not-an-id', token: t)), 400);
    expect(await status(req('GET', '/v1/stream/../../x', token: t)), 404);
  });

  group('pair endpoint', () {
    test('bad bodies -> 400/415, oversize -> 413', () async {
      expect(
        await status(
          req('POST', '/v1/pair', body: {'code': 'abc', 'deviceName': 'x'}),
        ),
        400,
      );
      expect(
        await status(req('POST', '/v1/pair', body: {'code': '123456'})),
        400,
      );
      expect(
        await status(
          Request('POST', Uri.parse('https://gw/v1/pair'), body: '{}'),
        ),
        415,
      );
      expect(
        await status(
          req(
            'POST',
            '/v1/pair',
            body: {'code': '123456', 'deviceName': 'x' * 6000},
          ),
        ),
        413,
      );
    });

    test('pairs once, then 5 wrong guesses lock the next code', () async {
      store.update((s) => s.users['u1'] = UserRec('alice', Role.requester));
      final code = store.update(
        (s) => issueCode(s, 'u1', DateTime.now().millisecondsSinceEpoch),
      );
      final ok = await h(
        req('POST', '/v1/pair', body: {'code': code, 'deviceName': 'Pixel'}),
      );
      expect(ok.statusCode, 200);
      final j = jsonDecode(await ok.readAsString()) as Map;
      expect(j['role'], 'requester');
      expect(
        await status(req('GET', '/v1/me', token: j['token'] as String)),
        200,
      );
      expect(
        await status(
          req('POST', '/v1/pair', body: {'code': code, 'deviceName': 'Pixel'}),
        ),
        401,
      );

      final code2 = store.update(
        (s) => issueCode(s, 'u1', DateTime.now().millisecondsSinceEpoch),
      );
      final wrong = code2 == '000000' ? '111111' : '000000';
      for (var i = 0; i < 5; i++) {
        expect(
          await status(
            req('POST', '/v1/pair', body: {'code': wrong, 'deviceName': 'x'}),
          ),
          401,
        );
      }
      expect(
        await status(
          req('POST', '/v1/pair', body: {'code': code2, 'deviceName': 'x'}),
        ),
        401,
      );
    });

    test('global throttle returns 429', () async {
      var last = 0;
      for (var i = 0; i < 25; i++) {
        last = await status(
          req('POST', '/v1/pair', body: {'code': '000000', 'deviceName': 'x'}),
        );
      }
      expect(last, 429);
    });
  });

  test('unknown route -> 404 json; healthz needs no token', () async {
    expect(await status(req('GET', '/nope')), 404);
    expect(await status(req('GET', '/healthz')), 200);
  });
}
