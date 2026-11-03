import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common/sections.dart';

/// The desktop sections in the order of Ctrl+1 to Ctrl+6 and of the sidebar.
/// (Not [Section.values] order: YouTube comes before Torrents here.)
const desktopSectionOrder = [
  Section.home,
  Section.search,
  Section.liveTv,
  Section.youtube,
  Section.torrents,
  Section.settings,
];

class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

class GoToSectionIntent extends Intent {
  const GoToSectionIntent(this.section);

  final Section section;
}

class ToggleSidebarIntent extends Intent {
  const ToggleSidebarIntent();
}

class ToggleFullscreenIntent extends Intent {
  const ToggleFullscreenIntent();
}

class GoBackIntent extends Intent {
  const GoBackIntent();
}

class EscapeIntent extends Intent {
  const EscapeIntent();
}

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
];

/// Ctrl+K or / search, Ctrl+1..6 sections, Ctrl+, Settings, Ctrl+B sidebar,
/// Alt+Left back, F11 fullscreen, Esc closes what is open.
final Map<ShortcutActivator, Intent> desktopShortcuts = {
  const SingleActivator(LogicalKeyboardKey.keyK, control: true): const FocusSearchIntent(),
  const SingleActivator(LogicalKeyboardKey.slash): const FocusSearchIntent(),
  for (var i = 0; i < desktopSectionOrder.length; i++)
    SingleActivator(_digits[i], control: true): GoToSectionIntent(desktopSectionOrder[i]),
  const SingleActivator(LogicalKeyboardKey.comma, control: true):
      const GoToSectionIntent(Section.settings),
  const SingleActivator(LogicalKeyboardKey.keyB, control: true): const ToggleSidebarIntent(),
  const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): const GoBackIntent(),
  const SingleActivator(LogicalKeyboardKey.f11): const ToggleFullscreenIntent(),
  const SingleActivator(LogicalKeyboardKey.escape): const EscapeIntent(),
};

/// True while the keyboard types into a text field.
bool typingInTextField() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// An action that steps aside while the user types: a bare key such as `/`
/// must still reach the text field.
class _KeyAction<T extends Intent> extends CallbackAction<T> {
  _KeyAction(this.guardTyping, void Function(T) onInvoke) : super(onInvoke: (i) {
        onInvoke(i);
        return null;
      });

  final bool guardTyping;

  @override
  bool isEnabled(T intent) => !guardTyping || !typingInTextField();
}

/// The actions for [desktopShortcuts].
Map<Type, Action<Intent>> desktopActions({
  required VoidCallback focusSearch,
  required void Function(Section) goTo,
  required VoidCallback toggleSidebar,
  required VoidCallback toggleFullscreen,
  required VoidCallback back,
  required VoidCallback escape,
}) =>
    {
      // `/` is only a shortcut outside a text field; Ctrl+K works everywhere.
      FocusSearchIntent: _FocusSearchAction(focusSearch),
      GoToSectionIntent: _KeyAction<GoToSectionIntent>(false, (i) => goTo(i.section)),
      ToggleSidebarIntent: _KeyAction<ToggleSidebarIntent>(false, (_) => toggleSidebar()),
      ToggleFullscreenIntent: _KeyAction<ToggleFullscreenIntent>(false, (_) => toggleFullscreen()),
      GoBackIntent: _KeyAction<GoBackIntent>(false, (_) => back()),
      EscapeIntent: _KeyAction<EscapeIntent>(false, (_) => escape()),
    };

class _FocusSearchAction extends Action<FocusSearchIntent> {
  _FocusSearchAction(this.onFocus);

  final VoidCallback onFocus;

  // Ctrl+K always; a bare `/` only when nothing is being typed.
  @override
  bool isEnabled(FocusSearchIntent intent) {
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed;
    return ctrl || !typingInTextField();
  }

  @override
  Object? invoke(FocusSearchIntent intent) {
    onFocus();
    return null;
  }
}
