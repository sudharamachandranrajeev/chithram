import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Widget keys the tests look for. Keys that belong to the nav rail
/// (`nav-<section>`) and the search keyboard (`key-<id>`) are built where they
/// are used.
abstract final class Keys {
  static const playerRoot = ValueKey('player-root');

  /// A `Text` with the position as `m:ss` (or `h:mm:ss`).
  static const playerPosition = ValueKey('player-position');
  static const playerError = ValueKey('player-error');
  static const textEntryField = ValueKey('text-entry-field');
  static const textEntryPaste = ValueKey('text-entry-paste');
  static const textEntryOk = ValueKey('text-entry-ok');
  static const textEntryKeyboard = ValueKey('text-entry-keyboard');
  static const textEntrySend = ValueKey('text-entry-send');
}

/// True when [event] is a Ctrl, Alt or Meta chord (a shortcut such as the
/// desktop's Ctrl+1) and so must not be typed as a character. AltGr reports
/// Ctrl+Alt on Windows but still produces a character (for example `@`): that
/// is typing.
bool isShortcutChord(KeyEvent event) {
  final keys = HardwareKeyboard.instance;
  final ctrl = keys.isControlPressed, alt = keys.isAltPressed;
  if (ctrl && alt && event.character != null) return false;
  return ctrl || alt || keys.isMetaPressed;
}
