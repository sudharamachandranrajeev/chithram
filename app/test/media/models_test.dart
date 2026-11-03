import 'package:chithram/src/media/models.dart';
import 'package:chithram/src/ui/common/status_chip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('roles decide what is offered', () {
    expect(MediaRole.admin.canRequest && MediaRole.admin.isAdmin && MediaRole.admin.canSeeDownloads, isTrue);
    expect(MediaRole.requester.canRequest, isTrue);
    expect(MediaRole.requester.isAdmin || MediaRole.requester.canSeeDownloads, isFalse);
    expect(MediaRole.viewer.canRequest || MediaRole.viewer.isAdmin || MediaRole.viewer.canSeeDownloads, isFalse);
    expect(MediaRole.parse('nope'), isNull);
  });

  test('every gateway status parses and has a distinct label', () {
    for (final s in MediaStatus.values) {
      expect(MediaStatus.parse(s.name), s);
    }
    expect(MediaStatus.values.map((s) => s.label).toSet().length, MediaStatus.values.length);
    expect(() => MediaStatus.parse('weird'), throwsA(isA<ModelError>()));
    expect(MediaStatus.available.chip, RequestStatus.available);
    expect(MediaStatus.none.chip, isNull);
    expect(MediaStatus.approved.chip, isNull, reason: 'drawn by MediaStatusChip');
  });

  test('search results are validated', () {
    final ok = SearchItem.listFrom({
      'results': [
        {'tmdbId': 1, 'type': 'movie', 'title': 'Dune\u0000', 'year': 2021, 'overview': null, 'posterPath': '/x', 'mediaStatus': 'none'},
      ],
    });
    expect(ok.single.title, 'Dune');
    expect(
      () => SearchItem.listFrom({
        'results': [
          {'tmdbId': '1', 'type': 'movie', 'title': 'a', 'mediaStatus': 'none'},
        ],
      }),
      throwsA(isA<ModelError>()),
    );
    expect(
      () => SearchItem.listFrom({
        'results': [
          {'tmdbId': 1, 'type': 'game', 'title': 'a', 'mediaStatus': 'none'},
        ],
      }),
      throwsA(isA<ModelError>()),
    );
    expect(() => SearchItem.listFrom({'results': 'x'}), throwsA(isA<ModelError>()));
    expect(() => SearchItem.listFrom([]), throwsA(isA<ModelError>()));
  });

  test('library items accept only gateway image paths and hex ids', () {
    final id = 'a' * 32;
    final it = LibraryItem.fromJson({'id': id, 'title': 'T', 'type': 'Movie', 'poster': '/v1/images/$id?w=342'});
    expect(it.playable, isTrue);
    expect(LibraryItem.fromJson({'id': id, 'title': 'T', 'type': 'Series'}).playable, isFalse);
    expect(
      () => LibraryItem.fromJson({'id': id, 'title': 'T', 'type': 'Movie', 'poster': 'https://evil.example/x.png'}),
      throwsA(isA<ModelError>()),
    );
    expect(() => LibraryItem.fromJson({'id': 'ZZ', 'title': 'T', 'type': 'Movie'}), throwsA(isA<ModelError>()));
    expect(validImagePath('/v1/images/$id'), isTrue);
    expect(validImagePath('/v1/images/$id/../x'), isFalse);
    expect(validImagePath('//evil/v1/images/$id'), isFalse);
  });

  test('pair result needs a plausible token and a known role', () {
    final tok = 'A' * 43;
    final r = PairResult.fromJson({'token': tok, 'deviceId': 'd', 'user': 'u', 'role': 'viewer'});
    expect(r.role, MediaRole.viewer);
    expect(
      () => PairResult.fromJson({'token': 'short', 'deviceId': 'd', 'user': 'u', 'role': 'viewer'}),
      throwsA(isA<ModelError>()),
    );
    expect(
      () => PairResult.fromJson({'token': tok, 'deviceId': 'd', 'user': 'u', 'role': 'root'}),
      throwsA(isA<ModelError>()),
    );
  });

  test('downloads clamp progress and need a download status', () {
    final d = DownloadItem.listFrom({
      'downloads': [
        {'id': 1, 'type': 'movie', 'title': 'X', 'status': 'downloading', 'progress': 1.7, 'timeLeft': '00:10:00'},
        {'id': 2, 'type': 'tv', 'title': null, 'status': 'importing', 'progress': null},
      ],
    });
    expect(d[0].progress, 1.0);
    expect(d[1].title, 'Unknown title');
    final many = DownloadItem.listFrom({
      'downloads': [
        for (var i = 0; i < 250; i++) {'id': i, 'type': 'movie', 'title': 'T$i', 'status': 'downloading'},
      ],
    });
    expect(many.length, maxDownloadsShown, reason: 'a long queue is cut, not an error');
    expect(many.first.title, 'T0');
    expect(
      () => DownloadItem.listFrom({
        'downloads': [
          {'status': 'available', 'title': 'x'},
        ],
      }),
      throwsA(isA<ModelError>()),
    );
  });
}
