import 'package:chithram/src/ui/desktop/window_chrome.dart';
import 'package:flutter/foundation.dart';

/// A window that records what it was asked. [toggleFullscreen] flips
/// [fullscreen], as the real window reports it back.
class FakeChrome implements WindowChrome {
  FakeChrome({this.custom = true});

  @override
  final bool custom;
  final calls = <String>[];

  @override
  final ValueNotifier<bool> maximized = ValueNotifier(false);

  @override
  final ValueNotifier<bool> fullscreen = ValueNotifier(false);

  @override
  Future<void> setCustomFrame(bool on) async => calls.add('frame:$on');
  @override
  Future<void> minimize() async => calls.add('minimize');
  @override
  Future<void> toggleMaximize() async => calls.add('maximize');
  @override
  Future<void> close() async => calls.add('close');
  @override
  Future<void> toggleFullscreen() async {
    calls.add('fullscreen');
    fullscreen.value = !fullscreen.value;
  }

  @override
  Future<void> startDrag() async => calls.add('drag');
}
