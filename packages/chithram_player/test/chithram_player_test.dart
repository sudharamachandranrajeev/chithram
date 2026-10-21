import 'package:chithram_player/chithram_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('package loads', () {
    expect(chithramPlayerPackageName, 'chithram_player');
  });

  test('MediaSpec defaults', () {
    const spec = MediaSpec(videoUrl: 'http://x/v.mp4');
    expect(spec.audioUrl, isNull);
    expect(spec.headers, isEmpty);
    expect(spec.isLive, isFalse);
    expect(spec.startPosition, Duration.zero);
  });
}
