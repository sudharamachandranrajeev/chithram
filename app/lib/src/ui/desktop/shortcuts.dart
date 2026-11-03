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

/// What the shell offers the shortcut host (see [DesktopShortcutScope]).
class DesktopShellCallbacks {
  const DesktopShellCallbacks({
    required this.focusSearch,
    required this.goTo,
    required this.goHome,
    required this.toggleSidebar,
    required this.toggleFullscreen,
    required this.escapeSearch,
  });

  final VoidCallback focusSearch;
  final void Function(Section) goTo;
  final VoidCallback goHome;
  final VoidCallback toggleSidebar;
  final VoidCallback toggleFullscreen;

  /// Esc while the title-bar search has focus: leaves it. False when it had none.
  final bool Function() escapeSearch;
}

/// The desktop shortcuts above the [Navigator], so they also work on a page
/// pushed over the shell (details, player settings...). Desktop form only; the
/// TV and phone shells never get one. The shell registers itself here; without
/// a scope it handles the keys itself.
class DesktopShortcutScope extends StatefulWidget {
  const DesktopShortcutScope({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  static DesktopShortcutScopeState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<DesktopShortcutScopeState>();

  @override
  State<DesktopShortcutScope> createState() => DesktopShortcutScopeState();
}

class DesktopShortcutScopeState extends State<DesktopShortcutScope> {
  DesktopShellCallbacks? _shell;

  void register(DesktopShellCallbacks shell) => _shell = shell;

  void unregister(DesktopShellCallbacks shell) {
    if (identical(_shell, shell)) _shell = null;
  }

  NavigatorState? get _nav => widget.navigatorKey.currentState;

  /// Closes every page over the shell.
  void _toShell() => _nav?.popUntil((r) => r.isFirst);

  void _focusSearch() {
    _toShell();
    _shell?.focusSearch();
  }

  void _goTo(Section s) {
    _toShell();
    _shell?.goTo(s);
  }

  void _back() {
    final nav = _nav;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else {
      _shell?.goHome();
    }
  }

  /// Esc: leaves the search field; in any other text field only leaves that
  /// field; else closes the top page.
  void _escape() {
    if (_shell?.escapeSearch() ?? false) return;
    if (typingInTextField()) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    final nav = _nav;
    if (nav != null && nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: desktopShortcuts,
        child: Actions(
          actions: desktopActions(
            focusSearch: _focusSearch,
            goTo: _goTo,
            toggleSidebar: () => _shell?.toggleSidebar(),
            toggleFullscreen: () => _shell?.toggleFullscreen(),
            back: _back,
            escape: _escape,
          ),
          child: widget.child,
        ),
      );
}
