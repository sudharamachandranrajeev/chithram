import 'package:chithram_gateway/src/roles.dart';
import 'package:chithram_gateway/src/status_map.dart';
import 'package:chithram_gateway/src/validate.dart';
import 'package:test/test.dart';

void main() {
  group('status mapping', () {
    test('table', () {
      expect(mapStatus(), 'none');
      expect(mapStatus(mediaStatus: 1), 'none');
      expect(mapStatus(mediaStatus: 2), 'requested');
      expect(mapStatus(requestStatus: 1, mediaStatus: 2), 'awaitingApproval');
      expect(mapStatus(requestStatus: 2, mediaStatus: 3), 'approved');
      expect(mapStatus(requestStatus: 3), 'failed');
      expect(mapStatus(requestStatus: 4), 'failed');
      expect(mapStatus(requestStatus: 2, mediaStatus: 5), 'available');
      expect(mapStatus(mediaStatus: 4), 'available');
      expect(mapStatus(requestStatus: 5), 'available');
    });

    test('arr activity refines approved', () {
      expect(
        mapStatus(requestStatus: 2, arr: const ArrActivity(searching: true)),
        'searching',
      );
      expect(
        mapStatus(requestStatus: 2, arr: const ArrActivity(downloading: true)),
        'downloading',
      );
      expect(
        mapStatus(
          requestStatus: 2,
          arr: const ArrActivity(importing: true, downloading: true),
        ),
        'importing',
      );
      expect(mapStatus(requestStatus: 2, arr: const ArrActivity()), 'approved');
    });

    test('pending request never shows arr activity', () {
      expect(
        mapStatus(requestStatus: 1, arr: const ArrActivity(downloading: true)),
        'awaitingApproval',
      );
    });

    test('every output is a known name', () {
      for (final rs in [null, 1, 2, 3, 4, 5, 9]) {
        for (final ms in [null, 1, 2, 3, 4, 5, 6, 7, 9]) {
          expect(
            statusNames,
            contains(mapStatus(requestStatus: rs, mediaStatus: ms)),
          );
        }
      }
    });
  });

  group('roles', () {
    test('seerr permission mapping', () {
      expect(Role.admin.seerrPermissions, 2);
      expect(Role.requester.seerrPermissions, 32);
      expect(Role.viewer.seerrPermissions, 0);
    });
    test('capabilities', () {
      expect(Role.viewer.canRequest, isFalse);
      expect(Role.requester.canRequest, isTrue);
      expect(Role.requester.isAdmin, isFalse);
      expect(Role.admin.canRequest, isTrue);
      expect(Role.parse('root'), isNull);
      expect(Role.parse(null), isNull);
    });
  });

  group('validation', () {
    test('code', () {
      expect(validCode('123456'), isTrue);
      for (final bad in [
        '12345',
        '1234567',
        'abcdef',
        '12 456',
        123456,
        null,
        '１２３４５６',
      ]) {
        expect(validCode(bad), isFalse, reason: '$bad');
      }
    });
    test('tmdb id and type', () {
      expect(validTmdbId(10331), 10331);
      for (final bad in [0, -1, 1000000001, '5', 1.5, null]) {
        expect(validTmdbId(bad), isNull, reason: '$bad');
      }
      expect(validMediaType('movie'), 'movie');
      expect(validMediaType('tv'), 'tv');
      expect(validMediaType('music'), isNull);
    });
    test('query and device name', () {
      expect(
        validQuery('  Night of the Living Dead '),
        'Night of the Living Dead',
      );
      expect(validQuery(''), isNull);
      expect(validQuery('a' * 101), isNull);
      expect(validQuery('a\nb'), isNull);
      expect(validDeviceName('Pixel 8'), 'Pixel 8');
      expect(validDeviceName('x' * 65), isNull);
      expect(validDeviceName('a\u0000'), isNull);
      expect(validDeviceName(5), isNull);
    });
    test('ids, cursor, width, library type', () {
      expect(
        normalizeItemId('ABCDEF0123456789ABCDEF0123456789'),
        'abcdef0123456789abcdef0123456789',
      );
      expect(normalizeItemId('../etc/passwd'), isNull);
      expect(normalizeItemId('abc'), isNull);
      expect(validNumericId('42'), 42);
      expect(validNumericId('4x'), isNull);
      expect(validNumericId('0'), isNull);
      expect(validCursor(null), 0);
      expect(validCursor('150'), 150);
      expect(validCursor('-1'), isNull);
      expect(validCursor('123456789'), isNull);
      expect(validWidth(null), 342);
      expect(validWidth('9999'), isNull);
      expect(validWidth('10'), isNull);
      expect(validWidth('500'), 500);
      expect(libraryItemType('movies'), 'Movie');
      expect(libraryItemType('tv'), 'Series');
      expect(libraryItemType('music'), 'MusicAlbum');
      expect(libraryItemType('x'), isNull);
    });
    test('route template hides ids', () {
      expect(
        routeTemplate('/v1/requests/42/approve'),
        '/v1/requests/:id/approve',
      );
      expect(
        routeTemplate('/v1/images/abcdef0123456789abcdef0123456789'),
        '/v1/images/:id',
      );
    });
  });
}
