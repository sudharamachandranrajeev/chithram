import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../theme.dart';
import '../common/search_page.dart';
import '../common/section_shell.dart';
import '../common/sections.dart';
import '../tv/focus_card.dart';
import 'desktop_home.dart';
import 'shortcuts.dart';
import 'sidebar.dart';
import 'title_bar.dart';
import 'window_chrome.dart';

/// The desktop design (Windows, Linux): a 40 dp title bar with search, a
/// sidebar (240 dp, or a 72 dp icon rail when narrow or collapsed) and the
/// current section. Mouse and keyboard first: hovering never moves focus, a
/// click only shows a section, Tab goes title bar, sidebar, content.
///
/// Selection, focus memory and Back come from [SectionShellState], shared with
/// the TV shell.
class DesktopShell extends StatefulWidget {
  /// [chrome] is the window; it defaults to [WindowChrome.instance] (tests pass a fake).
  const DesktopShell({super.key, this.chrome});

  final WindowChrome? chrome;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends SectionShellState<DesktopShell> {
  late final WindowChrome _chrome = widget.chrome ?? WindowChrome.instance;
  final _ownSearchFocus = FocusNode(debugLabel: 'title search');
  final _ownSearchText = TextEditingController();

  /// The app's frame draws the title bar above the Navigator (so pages over
  /// the shell keep it); this shell then only listens to its search field.
  bool get _hostBar => _host?.drawsTitleBar ?? false;
  FocusNode get _searchFocus => _hostBar ? _host!.searchFocus : _ownSearchFocus;
  TextEditingController get _searchText => _hostBar ? _host!.searchController : _ownSearchText;

  // Tab leaves these scopes at their ends (to the next one in title bar,
  // sidebar, content order) instead of wrapping inside them.
  final _navScope = FocusScopeNode(
    debugLabel: 'sidebar',
    traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );
  final _contentScopes = [
    for (final s in Section.values)
      FocusScopeNode(
        debugLabel: 'content ${s.label}',
        traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
      ),
  ];

  /// The section that was showing when the search field took focus; Esc goes back to it.
  int? _returnTo;

  /// Set when the app handles the shortcuts above the Navigator (then pages
  /// pushed over the shell get them too); null: this shell handles them.
  DesktopShortcutScopeState? _host;

  late final _callbacks = DesktopShellCallbacks(
    focusSearch: _focusSearch,
    goTo: open,
    goHome: _goHome,
    toggleSidebar: _toggleSidebar,
    toggleFullscreen: () => unawaited(_chrome.toggleFullscreen().catchError((Object _) {})),
    escapeSearch: _escapeSearch,
    submitSearch: _submitSearch,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_chrome.setCustomFrame(true).catchError((Object _) {}));
    _host = DesktopShortcutScope.maybeOf(context)?..register(_callbacks);
    _searchFocus.addListener(_searchFocusChanged);
  }

  @override
  void dispose() {
    _host?.unregister(_callbacks);
    _searchFocus.removeListener(_searchFocusChanged);
    _ownSearchFocus.dispose();
    _ownSearchText.dispose();
    _navScope.dispose();
    for (final s in _contentScopes) {
      s.dispose();
    }
    // Another design (10-foot mode) has no bar of its own: native frame back.
    unawaited(_chrome.setCustomFrame(false).catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget homePage(SectionFocus focus) => DesktopHome(focus: focus, onOpenSection: open);

  void _searchFocusChanged() {
    if (!_searchFocus.hasFocus) return;
    if (index != Section.search.index) _returnTo = index;
    show(Section.search);
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _searchText.selection = TextSelection(baseOffset: 0, extentOffset: _searchText.text.length);
  }

  void _submitSearch(String text) {
    final query = text.trim();
    if (query.isEmpty) return;
    _searchText.clear();
    _returnTo = null;
    _searchFocus.unfocus();
    focusRail();
    unawaited(openSearch(context, query));
  }

  /// Esc: leaves the search field (and the Search section it opened), else
  /// closes a page opened over the shell.
  void _escape() {
    if (_escapeSearch()) return;
    // maybePop: the page on top may first close something of its own.
    final nav = Navigator.of(context);
    if (nav.canPop()) unawaited(nav.maybePop());
  }

  /// Esc in the search field: leaves it. False when it did not have focus.
  bool _escapeSearch() {
    if (_searchFocus.hasFocus) {
      final back = _returnTo;
      _returnTo = null;
      _searchText.clear();
      if (back != null && index == Section.search.index) {
        show(Section.values[back]);
        railNodes[back].requestFocus();
      } else {
        focusRail();
      }
      return true;
    }
    return false;
  }

  /// Alt+Left: close the page over the shell, else go to Home.
  void _goBack() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      unawaited(nav.maybePop());
    } else {
      _goHome();
    }
  }

  void _goHome() {
    if (index == 0) return;
    show(Section.home);
    railNodes[0].requestFocus();
  }

  bool _narrow(BuildContext context) => MediaQuery.sizeOf(context).width < sidebarAutoCollapseWidth;

  void _toggleSidebar() {
    // A narrow window is always collapsed; there is nothing to toggle.
    if (_narrow(context)) return;
    final prefs = AppServices.of(context).prefs;
    unawaited(prefs.set(sidebarCollapsedPref, !prefs.getBool(sidebarCollapsedPref)));
  }

  @override
  Widget buildNav(Widget rail) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (has) => setState(() => railHasFocus = has),
        child: FocusScope(node: _navScope, child: rail),
      );

  @override
  Widget buildContent() => Stack(
        children: [
          for (final section in Section.values)
            if (section != Section.media || mediaOn)
            Offstage(
              offstage: section.index != index,
              child: ExcludeFocus(
                excluding: section.index != index,
                child: FocusScope(node: _contentScopes[section.index], child: page(section)),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final prefs = AppServices.of(context).prefs;
    final page = Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-1.1, -1.2),
            radius: 1.3,
            colors: [c.heroTint.withValues(alpha: 0.14), c.background],
          ),
        ),
        child: RailScope(
          focusRail: focusRail,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              children: [
                if (!_hostBar)
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(0),
                    child: DesktopTitleBar(
                      chrome: _chrome,
                      searchFocus: _searchFocus,
                      searchController: _searchText,
                      onSearchSubmitted: _submitSearch,
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: ListenableBuilder(
                          listenable: prefs,
                          builder: (context, _) => buildNav(
                            DesktopSidebar(
                              collapsed: _narrow(context) || prefs.getBool(sidebarCollapsedPref),
                              showMedia: mediaOn,
                              selected: Section.values[index],
                              nodes: railNodes,
                              onFocused: show,
                              onEnter: enterContent,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: buildContent(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // With a scope above the Navigator the keys also work on pages over the
    // shell; without one (this shell on its own) it handles them itself.
    return wrapBack(
      _host != null
          ? page
          : Shortcuts(
              shortcuts: desktopShortcuts,
              child: Actions(
                actions: desktopActions(
                  focusSearch: _focusSearch,
                  goTo: open,
                  toggleSidebar: _toggleSidebar,
                  toggleFullscreen: _callbacks.toggleFullscreen,
                  back: _goBack,
                  escape: _escape,
                ),
                child: page,
              ),
            ),
    );
  }
}
