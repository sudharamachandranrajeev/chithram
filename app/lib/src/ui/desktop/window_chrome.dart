import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:screen_retriever/screen_retriever.dart';
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

  /// The window fills the screen (F11, the player's fullscreen button). Esc
  /// in the player leaves it before it closes the player.
  ValueListenable<bool> get fullscreen;

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
  ValueListenable<bool> get fullscreen => _never;

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
  final _fullscreen = ValueNotifier<bool>(false);
  bool _frameless = false;

  @override
  bool get custom => _frameless;

  @override
  ValueListenable<bool> get maximized => _maximized;

  @override
  ValueListenable<bool> get fullscreen => _fullscreen;

  @override
  void onWindowMaximize() => _maximized.value = true;

  @override
  void onWindowUnmaximize() => _maximized.value = false;

  @override
  void onWindowEnterFullScreen() => _fullscreen.value = true;

  @override
  void onWindowLeaveFullScreen() => _fullscreen.value = false;

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
  Future<void> toggleFullscreen() async {
    final on = !await windowManager.isFullScreen();
    await windowManager.setFullScreen(on);
    // Not every platform sends the enter/leave events; the call itself is known.
    _fullscreen.value = on;
  }

  @override
  Future<void> startDrag() => windowManager.startDragging();
}

/// The window size to open at: [desired], but at most [fraction] of the
/// [visible] work area (so the title bar is never off-screen on a small or
/// scaled display), and never below [min]. [maximize] is true when even [min]
/// does not fit in the work area.
({Size size, bool maximize}) fitWindowSize(
  Size desired,
  Size visible, {
  Size min = minWindowSize,
  double fraction = 0.9,
}) {
  final w = desired.width.clamp(0.0, visible.width * fraction);
  final h = desired.height.clamp(0.0, visible.height * fraction);
  final size = Size(w < min.width ? min.width : w, h < min.height ? min.height : h);
  return (size: size, maximize: size.width > visible.width || size.height > visible.height);
}

/// How long the window setup may take before the app starts anyway.
const windowSetupTimeout = Duration(seconds: 2);

/// Called once from `main()` before the first frame: Windows gets the frameless
/// window (at most 90% of the work area, [defaultWindowSize] at best) with a
/// [minWindowSize] floor; elsewhere the window is left as the runner made it.
/// [frameless] false keeps the native frame (the desktop's 10-foot TV mode has
/// no title bar of its own).
///
/// Never throws and never hangs: on any failure or after [windowSetupTimeout]
/// the app keeps the native frame ([NativeChrome]) and starts as usual.
Future<void> setupWindowChrome({required bool frameless}) async {
  if (kIsWeb || !Platform.isWindows) return;
  final chrome = WindowsChrome._().._frameless = frameless;
  try {
    await _setup(chrome, frameless).timeout(windowSetupTimeout);
    WindowChrome.instance = chrome;
  } catch (_) {
    windowManager.removeListener(chrome);
    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.normal).timeout(windowSetupTimeout);
    } catch (_) {
      // Already the native frame, or the plugin is not there: nothing to undo.
    }
  }
}

Future<void> _setup(WindowsChrome chrome, bool frameless) async {
  await windowManager.ensureInitialized();
  windowManager.addListener(chrome);
  final visible = (await screenRetriever.getPrimaryDisplay()).visibleSize;
  final fit = visible == null ? (size: defaultWindowSize, maximize: false) : fitWindowSize(defaultWindowSize, visible);
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: fit.size,
      minimumSize: minWindowSize,
      center: true,
      title: 'Chithram',
      titleBarStyle: frameless ? TitleBarStyle.hidden : TitleBarStyle.normal,
    ),
    () async {
      await windowManager.show();
      if (fit.maximize) await windowManager.maximize();
      await windowManager.focus();
    },
  );
}
