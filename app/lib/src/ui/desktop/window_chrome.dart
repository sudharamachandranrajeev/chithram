import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:window_manager/window_manager.dart';

/// The desktop window as the shell sees it. Windows draws its own title bar
/// (frameless window, via `window_manager`); Linux keeps the native one, so
/// [custom] is false there and every method does nothing. Tests pass a fake.
abstract class WindowChrome {
  /// What the app uses; [setupWindowChrome] replaces it on Windows.
  static WindowChrome instance = const NativeChrome();

  /// The shell draws the window buttons and the drag area.
  bool get custom;

  ValueListenable<bool> get maximized;

  /// Frameless (the shell draws the bar) or the native frame (10-foot mode).
  Future<void> setCustomFrame(bool on);

  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> close();
  Future<void> toggleFullscreen();
  Future<void> startDrag();
}

/// The operating system's own title bar; nothing to control.
class NativeChrome implements WindowChrome {
  const NativeChrome();

  static final _never = ValueNotifier<bool>(false);

  @override
  bool get custom => false;

  @override
  ValueListenable<bool> get maximized => _never;

  @override
  Future<void> setCustomFrame(bool on) async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> toggleMaximize() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> toggleFullscreen() async {}
  @override
  Future<void> startDrag() async {}
}

const minWindowSize = Size(1024, 640);
const defaultWindowSize = Size(1440, 900);

/// Windows: frameless window through `window_manager`.
class WindowsChrome with WindowListener implements WindowChrome {
  WindowsChrome._();

  final _maximized = ValueNotifier<bool>(false);
  bool _frameless = false;

  @override
  bool get custom => _frameless;

  @override
  ValueListenable<bool> get maximized => _maximized;

  @override
  void onWindowMaximize() => _maximized.value = true;

  @override
  void onWindowUnmaximize() => _maximized.value = false;

  @override
  Future<void> setCustomFrame(bool on) async {
    if (on == _frameless) return;
    _frameless = on;
    await windowManager.setTitleBarStyle(on ? TitleBarStyle.hidden : TitleBarStyle.normal);
  }

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> toggleFullscreen() async =>
      windowManager.setFullScreen(!await windowManager.isFullScreen());

  @override
  Future<void> startDrag() => windowManager.startDragging();
}

/// Called once from `main()` before the first frame: Windows gets the frameless
/// window at [defaultWindowSize] with a [minWindowSize] floor; elsewhere the
/// window is left as the runner made it. [frameless] false keeps the native
/// frame (the desktop's 10-foot TV mode has no title bar of its own).
Future<void> setupWindowChrome({required bool frameless}) async {
  if (kIsWeb || !Platform.isWindows) return;
  await windowManager.ensureInitialized();
  final chrome = WindowsChrome._().._frameless = frameless;
  windowManager.addListener(chrome);
  WindowChrome.instance = chrome;
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: defaultWindowSize,
      minimumSize: minWindowSize,
      center: true,
      title: 'Chithram',
      titleBarStyle: frameless ? TitleBarStyle.hidden : TitleBarStyle.normal,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}
