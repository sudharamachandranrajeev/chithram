import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/livetv/livetv_page.dart';
import '../../features/torrents/torrents_page.dart';
import '../../features/youtube/youtube_page.dart';
import '../tv/focus_card.dart';
import '../tv/home_page.dart';
import 'search_page.dart';
import 'sections.dart';
import 'settings_page.dart';

/// The navigation every keyboard and D-pad shell shares (the TV shell and the
/// desktop shell draw it differently):
///
/// - one rail item per [Section], each with a `rail <label>` focus node;
/// - Right or Select on a rail item enters the section, Left at a section's
///   edge comes back (see [RailScope]);
/// - focus is remembered per section and never lost;
/// - Back goes content -> rail -> Home -> exit.
abstract class SectionShellState<T extends StatefulWidget> extends State<T> {
  int index = 0;
  bool railHasFocus = true;
  final sections = [for (final _ in Section.values) SectionFocus()];
  final railNodes = [for (final s in Section.values) FocusNode(debugLabel: 'rail ${s.label}')];

  /// The section's page; Home differs per shell.
  Widget homePage(SectionFocus focus) => HomePage(focus: focus);

  @override
  void initState() {
    super.initState();
    // Start on the rail's Home item.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) railNodes[0].requestFocus();
    });
    FocusManager.instance.addListener(_guardFocus);
  }

  bool _guardQueued = false;

  /// Focus is never lost: if nothing (or only a scope) is focused while the
  /// shell is the visible route, put it back on the current rail item.
  void _guardFocus() {
    if (_guardQueued) return;
    _guardQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guardQueued = false;
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      final f = FocusManager.instance.primaryFocus;
      if (f == null || f is FocusScopeNode || f.context == null) {
        railNodes[index].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_guardFocus);
    for (final s in sections) {
      s.dispose();
    }
    for (final n in railNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void focusRail() => railNodes[index].requestFocus();

  void enterContent() => sections[index].focus();

  /// Shows [section] (a rail item gained focus, or was clicked).
  void show(Section section) {
    if (index != section.index) setState(() => index = section.index);
  }

  /// Shows [section] and moves into it (mouse click, a shortcut).
  void open(Section section) {
    show(section);
    railNodes[section.index].requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) enterContent();
    });
  }

  void onBack() {
    if (!railHasFocus) {
      focusRail();
    } else if (index != 0) {
      railNodes[0].requestFocus();
    } else {
      SystemNavigator.pop();
    }
  }

  Widget page(Section section) {
    final focus = sections[section.index];
    return switch (section) {
      Section.home => homePage(focus),
      Section.search => SearchPage(focus: focus),
      Section.settings => SettingsPage(focus: focus),
      Section.liveTv => LiveTvPage(focus: focus),
      Section.torrents => TorrentsPage(focus: focus),
      Section.youtube => YouTubePage(focus: focus),
    };
  }

  /// Every section's page, only the current one visible and focusable.
  Widget buildContent() => Stack(
        children: [
          for (final section in Section.values)
            Offstage(
              offstage: section.index != index,
              child: ExcludeFocus(
                excluding: section.index != index,
                // Its own scope: arrows stay inside the section.
                child: FocusScope(child: page(section)),
              ),
            ),
        ],
      );

  /// Wraps [rail] so the shell knows whether the rail has focus.
  Widget buildNav(Widget rail) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (has) => setState(() => railHasFocus = has),
        child: FocusScope(child: rail),
      );

  /// Back handling around the whole shell.
  Widget wrapBack(Widget child) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onBack();
        },
        child: child,
      );
}

class EnterContentIntent extends Intent {
  const EnterContentIntent();
}

/// A rail item's keyboard, focus and mouse behaviour; [builder] draws it.
/// Right or Select enters the section; hovering focuses it when
/// [hoverFocuses]; a click shows the section (and enters it: [enterOnTap]).
class RailItemBehavior extends StatefulWidget {
  const RailItemBehavior({
    super.key,
    required this.section,
    required this.node,
    required this.onFocused,
    required this.onEnter,
    required this.builder,
    this.hoverFocuses = true,
    this.enterOnTap = true,
  });

  final Section section;
  final FocusNode node;
  final VoidCallback onFocused;
  final VoidCallback onEnter;
  final bool hoverFocuses;

  /// A click also moves focus into the section (TV); otherwise it only shows
  /// it and focus stays on the item (desktop: no focus glow after a click).
  final bool enterOnTap;
  final Widget Function(BuildContext context, bool focused, bool hovered) builder;

  @override
  State<RailItemBehavior> createState() => _RailItemBehaviorState();
}

class _RailItemBehaviorState extends State<RailItemBehavior> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.node,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) widget.onFocused();
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowRight): EnterContentIntent(),
      },
      actions: <Type, Action<Intent>>{
        EnterContentIntent: CallbackAction<EnterContentIntent>(onInvoke: (_) {
          widget.onEnter();
          return null;
        }),
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onEnter();
          return null;
        }),
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovered = true);
          if (widget.hoverFocuses && !widget.node.hasFocus) widget.node.requestFocus();
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        child: GestureDetector(
          key: ValueKey('nav-${widget.section.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.onFocused();
            widget.node.requestFocus();
            if (!widget.enterOnTap) return;
            // After the section is built focusable.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onEnter();
            });
          },
          child: widget.builder(context, _focused, _hovered),
        ),
      ),
    );
  }
}
