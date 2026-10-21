/// Channel indexes worth preloading around [index] for instant zapping.
///
/// [direction] (+1 = last zap went up) puts the likelier neighbour first.
/// [isPlayable] skips dead/missing channels so preload slots are not wasted.
/// With [wrap] the list is circular. Result never contains [index] or
/// duplicates and has at most `2 * radius` entries.
List<int> zapNeighbours(
  int length,
  int index, {
  int radius = 1,
  int direction = 1,
  bool wrap = true,
  bool Function(int i)? isPlayable,
}) {
  if (length <= 1 || index < 0 || index >= length) return const [];
  final dir = direction >= 0 ? 1 : -1;
  final out = <int>[];
  final seen = <int>{index};

  int? step(int from, int d) {
    var i = from;
    for (var n = 0; n < length; n++) {
      i += d;
      if (i < 0 || i >= length) {
        if (!wrap) return null;
        i = (i + length) % length;
      }
      if (i == index) return null;
      if (isPlayable == null || isPlayable(i)) return i;
    }
    return null;
  }

  var up = index, down = index;
  for (var r = 0; r < radius; r++) {
    for (final d in [dir, -dir]) {
      final from = d == dir ? up : down;
      final n = step(from, d);
      if (n == null) continue;
      if (d == dir) {
        up = n;
      } else {
        down = n;
      }
      if (seen.add(n)) out.add(n);
    }
  }
  return out;
}
