import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../player/play_request.dart' show playerRouteName;
import '../../theme.dart';
import '../common/sections.dart';
import '../common/tokens.dart';
import 'title_bar.dart';
import 'window_chrome.dart';

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
  const SingleActivator(LogicalKeyboardKey.comma, control: true): const GoToSectionIntent(Section.settings),
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
  _KeyAction(this.guardTyping, void Function(T) onInvoke)
    : super(
        onInvoke: (i) {
          onInvoke(i);
          return null;
        },
      );

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
}) => {
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
    required this.submitSearch,
  });

  final VoidCallback focusSearch;
  final void Function(Section) goTo;
  final VoidCallback goHome;
  final VoidCallback toggleSidebar;
  final VoidCallback toggleFullscreen;

  /// Esc while the title-bar search has focus: leaves it. False when it had none.
  final bool Function() escapeSearch;

  /// Enter in the title-bar search field (drawn by the host, see
  /// [DesktopShortcutScopeState.drawsTitleBar]).
  final ValueChanged<String> submitSearch;
}

/// Where the app's Navigator stands, for the desktop frame: how many pages
/// are open ([depth], the shell counts as one; dialogs and menus do not) and
/// whether the top page covers the window ([fullscreen], the player).
typedef DesktopRouteState = ({int depth, bool fullscreen});

/// Follows the app's Navigator so the frame above it knows when to show Back
/// and when to step aside for the player. Give the same instance to
/// `MaterialApp.navigatorObservers` and to [DesktopShortcutScope].
class DesktopRouteObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];

  final state = ValueNotifier<DesktopRouteState>((depth: 1, fullscreen: false));
  bool _queued = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute != null) {
      if (i >= 0) {
        _routes[i] = newRoute;
      } else {
        _routes.add(newRoute);
      }
    } else if (i >= 0) {
      _routes.removeAt(i);
    }
    _changed();
  }

  // The Navigator reports in the middle of its own build; listeners rebuild
  // widgets, so the new state is published after the frame.
  void _changed() {
    if (_queued) return;
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      final pages = _routes.whereType<PageRoute<dynamic>>().toList();
      state.value = (
        depth: pages.isEmpty ? 1 : pages.length,
        fullscreen: pages.isNotEmpty && pages.last.settings.name == playerRouteName,
      );
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

/// The desktop frame above the [Navigator]: the shortcuts, the mouse's back
/// button and (with [routes]) the title bar, so all of them also work on a
/// page pushed over the shell (details, player settings...). Desktop form
/// only; the TV and phone shells never get one. The shell registers itself
/// here; without a scope it handles the keys and draws the bar itself.
///
/// With the bar up here a pushed page keeps the window buttons and gets a
/// Back button in the bar. The player covers the window, so the bar folds
/// away while it is on top.
class DesktopShortcutScope extends StatefulWidget {
  const DesktopShortcutScope({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.routes,
    this.chrome,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// The Navigator's observer; null: no title bar here (the shell draws its own).
  final DesktopRouteObserver? routes;

  /// The window; [WindowChrome.instance] when null (tests pass a fake).
  final WindowChrome? chrome;

  static DesktopShortcutScopeState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<DesktopShortcutScopeState>();

  @override
  State<DesktopShortcutScope> createState() => DesktopShortcutScopeState();
}

class DesktopShortcutScopeState extends State<DesktopShortcutScope> {
  DesktopShellCallbacks? _shell;

  /// The title-bar search field's focus and text; the shell listens to them.
  final searchFocus = FocusNode(debugLabel: 'title search');
  final searchController = TextEditingController();

  // The navigator sits in an overlay entry so the title bar's text field has
  // an Overlay (selection handles, context menu) above the Navigator's own.
  late final OverlayEntry _entry = OverlayEntry(builder: _frame, maintainState: true);

  /// The title bar is drawn here, above the Navigator, not by the shell.
  bool get drawsTitleBar => widget.routes != null;

  void register(DesktopShellCallbacks shell) => _shell = shell;

  void unregister(DesktopShellCallbacks shell) {
    if (identical(_shell, shell)) _shell = null;
  }

  @override
  void initState() {
    super.initState();
    searchFocus.addListener(_searchFocusChanged);
  }

  @override
  void didUpdateWidget(DesktopShortcutScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    searchFocus.removeListener(_searchFocusChanged);
    searchFocus.dispose();
    searchController.dispose();
    super.dispose();
  }

  NavigatorState? get _nav => widget.navigatorKey.currentState;

  /// Closes every page over the shell.
  void _toShell() => _nav?.popUntil((r) => r.isFirst);

  // Searching from a page over the shell: the results show in the shell.
  void _searchFocusChanged() {
    if (searchFocus.hasFocus && (_nav?.canPop() ?? false)) _toShell();
  }

  void _focusSearch() {
    _toShell();
    _shell?.focusSearch();
  }

  void _goTo(Section s) {
    _toShell();
    _shell?.goTo(s);
  }

  /// Alt+Left, the title bar's Back, the mouse's back button. `maybePop`, so
  /// a page that first closes something of its own (the player's menus, a
  /// scrub) gets to.
  void _back() {
    final nav = _nav;
    if (nav != null && nav.canPop()) {
      unawaited(nav.maybePop());
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
    if (nav != null && nav.canPop()) unawaited(nav.maybePop());
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse && event.buttons & kBackMouseButton != 0) _back();
  }

  Widget _frame(BuildContext context) {
    final routes = widget.routes!;
    return ValueListenableBuilder<DesktopRouteState>(
      valueListenable: routes.state,
      child: widget.child,
      builder: (context, state, navigator) {
        final shown = !state.fullscreen;
        // The bar is translucent; behind it is the app background, as on the
        // shell when it draws the bar itself.
        return ColoredBox(
          color: ChithramColors.of(context).background,
          child: Column(
            children: [
              // Always in the tree (removing it would rebuild the Navigator
              // below); folded to nothing under the player.
              ClipRect(
                child: AnimatedAlign(
                  alignment: Alignment.bottomCenter,
                  heightFactor: shown ? 1 : 0,
                  duration: Motion.of(context).expandTime,
                  curve: Motion.curve,
                  child: ExcludeFocus(
                    excluding: !shown,
                    child: Material(
                      type: MaterialType.transparency,
                      child: DesktopTitleBar(
                        chrome: widget.chrome ?? WindowChrome.instance,
                        searchFocus: searchFocus,
                        searchController: searchController,
                        onSearchSubmitted: (text) => _shell?.submitSearch(text),
                        onBack: state.depth > 1 ? _back : null,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: navigator!),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onPointerDown,
    child: Shortcuts(
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
        child: widget.routes == null ? widget.child : Overlay(initialEntries: [_entry]),
      ),
    ),
  );
}
