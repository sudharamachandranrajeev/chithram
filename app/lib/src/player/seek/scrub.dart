import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:innertube/innertube.dart' show Chapter;

/// A pause this long after the last Left/Right commits the scrub.
const scrubIdle = Duration(milliseconds: 1200);

/// While a key is held a step is taken at most this often.
const scrubRepeat = Duration(milliseconds: 140);

/// How far one step goes after the key was held for [held]: 10 s, then 30 s,
/// 1 min and 2 min. A short [length] caps it (a tenth of the video, 5 s at
/// least) so a three-minute clip is not crossed in one step.
Duration scrubStep(Duration held, {Duration length = Duration.zero}) {
  final ms = held.inMilliseconds;
  var seconds = ms < 800 ? 10 : (ms < 1600 ? 30 : (ms < 2800 ? 60 : 120));
  if (length > Duration.zero) {
    final cap = (length.inSeconds ~/ 10).clamp(5, 120);
    if (seconds > cap) seconds = cap;
  }
  return Duration(seconds: seconds);
}

/// A scrub in progress: a preview position that moves without seeking, until
/// it is committed (OK, a pause, or the end of a drag) or cancelled (Back).
///
/// Left and Right call [key]; a drag calls [drag]. Listeners hear every
/// change of [preview].
class Scrubber extends ChangeNotifier {
  Scrubber({required this.onCommit, this.idle = scrubIdle});

  /// Called with the position to seek to.
  final void Function(Duration to) onCommit;
  final Duration idle;

  Duration? _preview;
  Timer? _idle;
  int _dir = 0;
  Duration _heldSince = Duration.zero;
  Duration _lastStep = Duration.zero;
  bool _dragging = false;

  /// Where the scrub points now; null when not scrubbing.
  Duration? get preview => _preview;
  bool get active => _preview != null;

  /// A Left (-1) or Right (+1) key event. [now] is any monotonic clock.
  void key(
    int dir, {
    required bool repeat,
    required Duration now,
    required Duration position,
    required Duration length,
  }) {
    if (_dragging) return;
    if (!repeat || dir != _dir) {
      _dir = dir;
      _heldSince = now;
    } else if (now - _lastStep < scrubRepeat) {
      return;
    }
    _lastStep = now;
    final step = scrubStep(now - _heldSince, length: length);
    _set(_clamp((_preview ?? position) + step * dir, length));
    _armIdle();
  }

  /// The arrow key was released: the next press starts slow again.
  void keyUp() => _dir = 0;

  /// Touch or mouse: the thumb is at [to]. No idle commit while held.
  void drag(Duration to, Duration length) {
    _dragging = true;
    _idle?.cancel();
    _set(_clamp(to, length));
  }

  /// The drag ended: commit where it stopped.
  void dragEnd() {
    _dragging = false;
    commit();
  }

  /// Seeks to the preview, if scrubbing.
  void commit() {
    _idle?.cancel();
    final to = _preview;
    if (to == null) return;
    _preview = null;
    _dir = 0;
    notifyListeners();
    onCommit(to);
  }

  /// Drops the preview without seeking.
  void cancel() {
    _idle?.cancel();
    _dragging = false;
    _dir = 0;
    if (_preview == null) return;
    _preview = null;
    notifyListeners();
  }

  void _set(Duration to) {
    if (_preview == to) return;
    _preview = to;
    notifyListeners();
  }

  void _armIdle() {
    _idle?.cancel();
    _idle = Timer(idle, commit);
  }

  static Duration _clamp(Duration d, Duration length) {
    if (d < Duration.zero) return Duration.zero;
    if (length > Duration.zero && d > length) return length;
    return d;
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }
}

/// The chapter [t] falls in, or null.
Chapter? chapterAt(List<Chapter> chapters, Duration t) {
  Chapter? found;
  for (final c in chapters) {
    if (c.start > t) break;
    found = c;
  }
  return found;
}

/// SponsorBlock's own colours for its categories.
Color sponsorColor(String category) => switch (category) {
  'sponsor' => const Color(0xFF00D400),
  'selfpromo' => const Color(0xFFFFFF00),
  'interaction' => const Color(0xFFCC00FF),
  'intro' => const Color(0xFF00FFFF),
  'outro' => const Color(0xFF0202ED),
  'preview' => const Color(0xFF008FD6),
  'music_offtopic' => const Color(0xFFFF9900),
  _ => const Color(0xFFB0B0B0),
};
