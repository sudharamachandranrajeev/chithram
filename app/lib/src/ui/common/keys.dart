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
