import 'package:iptv/iptv.dart';
import 'package:test/test.dart';

void main() {
  test('N+1 first when zapping up, N-1 first when down', () {
    expect(zapNeighbours(10, 5), [6, 4]);
    expect(zapNeighbours(10, 5, direction: -1), [4, 6]);
  });
  test('wraps and no-wrap', () {
    expect(zapNeighbours(5, 4), [0, 3]);
    expect(zapNeighbours(5, 0, direction: -1), [4, 1]);
    expect(zapNeighbours(5, 4, wrap: false), [3]);
  });
  test('skips unplayable, radius, tiny lists', () {
    expect(zapNeighbours(10, 5, isPlayable: (i) => i != 6), [7, 4]);
    expect(zapNeighbours(10, 5, radius: 2), [6, 4, 7, 3]);
    expect(zapNeighbours(1, 0), isEmpty);
    expect(zapNeighbours(2, 0), [1]);
    expect(zapNeighbours(3, 7), isEmpty);
  });
}
