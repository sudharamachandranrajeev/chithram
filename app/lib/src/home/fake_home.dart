import 'package:flutter/foundation.dart';

import '../core/item_id.dart';
import 'home_repository.dart';
import 'home_source.dart';
import 'snapshot.dart';

/// Synthetic tiles: "Fixture Film 1", never real TMDB content.
List<HomeTile> fixtureTiles(int count, {MediaKind kind = MediaKind.movie, int firstId = 1}) => [
      for (var i = 0; i < count; i++)
        HomeTile(
          id: kind == MediaKind.movie ? ItemId.tmdbMovie(firstId + i) : ItemId.tmdbShow(firstId + i),
          kind: kind,
          tmdbId: firstId + i,
          title: kind == MediaKind.movie ? 'Fixture Film ${firstId + i}' : 'Fixture Show ${firstId + i}',
          subtitle: '${2000 + i}',
          poster: '/fixture_poster_${firstId + i}.jpg',
          backdrop: '/fixture_backdrop_${firstId + i}.jpg',
          rating: 5 + (i % 5),
        ),
    ];

HomeSnapshot fixtureSnapshot({int rails = 3, int perRail = 10, DateTime? at}) {
  final now = at ?? DateTime.utc(2026, 10, 22);
  return HomeSnapshot(
    generatedAt: now,
    language: 'en-US',
    region: 'US',
    hero: fixtureTiles(5),
    rails: [
      for (var r = 0; r < rails; r++)
        HomeRail(
          id: 'rail$r',
          title: 'Fixture Rail ${r + 1}',
          fetchedAt: now,
          tiles: fixtureTiles(perRail, firstId: 1 + r * perRail),
        ),
    ],
  );
}

/// A [HomeSource] that answers from memory. Counts fetches; `failWith` makes
/// every fetch fail (`authRejected` for a rejected key).
class FakeHomeSource implements HomeSource {
  FakeHomeSource({this.configured = true, this.railCount = 3, this.perRail = 10});

  @override
  bool configured;
  final int railCount, perRail;
  RailFailed? failWith;
  int fetches = 0;
  String? etag = 'fixture-etag';

  @override
  List<RailSpec> rails(HomeConfig c) => [
        const RailSpec(id: 'hero', title: 'Featured', softTtl: Duration(hours: 12), hero: true),
        for (var r = 0; r < railCount; r++)
          RailSpec(id: 'rail$r', title: 'Fixture Rail ${r + 1}', softTtl: const Duration(hours: 24)),
      ];

  @override
  Future<RailFetch> fetch(RailSpec r, HomeConfig c, {String? etag}) async {
    fetches++;
    final fail = failWith;
    if (fail != null) return fail;
    if (etag != null && etag == this.etag) return const RailNotModified();
    final n = r.hero ? 5 : perRail;
    return RailData(fixtureTiles(n, firstId: r.hero ? 1 : 1 + (int.tryParse(r.id.substring(4)) ?? 0) * perRail),
        etag: this.etag);
  }
}

/// A [HomeRepository] whose state a test sets; counts calls.
class FakeHomeRepository implements HomeRepository {
  FakeHomeRepository([HomeState state = const HomeState()]) : _state = ValueNotifier(state);

  final ValueNotifier<HomeState> _state;
  int refreshes = 0, forced = 0, interactions = 0;
  bool visible = false;

  set value(HomeState s) => _state.value = s;

  @override
  ValueListenable<HomeState> get state => _state;

  @override
  Future<void> refresh({bool force = false}) async {
    refreshes++;
    if (force) forced++;
  }

  @override
  void setVisible(bool v) => visible = v;

  @override
  void noteInteraction() => interactions++;
}
