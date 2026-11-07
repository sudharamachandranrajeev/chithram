import 'package:flutter/material.dart';

import '../../theme.dart';
import 'dims.dart';
import 'tokens.dart';

// Transitions built from Flutter's own primitives (no animations package):
// fade-through for content that replaces content, shared-axis for moving
// between a page and the page it leads to, a one-shot staggered entrance for
// lists, and a shimmer for skeletons. All of them honour [Motion.reduced], and
// on a TV they drop the scale (a transform on large layers costs the GPU of a
// 2 GB box more than a fade does).

/// Fade-through: the old content fades out quickly, then the new one fades
/// in while growing from 94%. For switching what a page shows (topic chips).
class FadeThroughSwitcher extends StatelessWidget {
  const FadeThroughSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
  });

  /// Give it a key that changes with the content.
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.of(context).reduced;
    final scale = !Dims.of(context).tv;
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : duration,
      // Top-aligned: content of different heights must not jump to the centre.
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => _FadeThrough(animation: animation, scale: scale, child: child),
      child: child,
    );
  }
}

class _FadeThrough extends AnimatedWidget {
  const _FadeThrough({required Animation<double> animation, required this.scale, required this.child})
    : super(listenable: animation);

  final bool scale;
  final Widget child;

  static const _out = Interval(0.6, 1, curve: Curves.easeIn);
  static const _in = Interval(0.35, 1, curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final a = listenable as Animation<double>;
    // The switcher runs the outgoing child's animation in reverse: it is gone
    // in the first 40% of the time, before the new one appears.
    final leaving = a.status == AnimationStatus.reverse;
    final t = leaving ? _out.transform(a.value) : _in.transform(a.value);
    Widget out = Opacity(opacity: t, child: child);
    if (scale && !leaving) out = Transform.scale(scale: 0.94 + 0.06 * t, child: out);
    // The leaving content must not take taps or focus meant for the new one.
    return IgnorePointer(ignoring: leaving, child: out);
  }
}

/// Two pages on one axis: [primary] (a home) and, when not null, [secondary]
/// (what it led to, such as search results). Both stay built, so going back
/// finds the primary exactly as it was (scroll, focus, hero slide). The
/// hidden one is offstage, out of focus traversal and its tickers paused.
class SharedAxisSwitch extends StatefulWidget {
  const SharedAxisSwitch({super.key, required this.primary, this.secondary});

  final Widget primary;
  final Widget? secondary;

  @override
  State<SharedAxisSwitch> createState() => _SharedAxisSwitchState();
}

class _SharedAxisSwitchState extends State<SharedAxisSwitch> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));

  /// The secondary page, kept while it animates away.
  Widget? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.secondary;
    _c.value = _shown == null ? 0 : 1;
    _c.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && widget.secondary == null && mounted) {
        setState(() => _shown = null);
      }
    });
  }

  @override
  void didUpdateWidget(SharedAxisSwitch old) {
    super.didUpdateWidget(old);
    final reduced = Motion.of(context).reduced;
    if (widget.secondary != null) {
      _shown = widget.secondary;
      reduced ? _c.value = 1 : _c.forward();
    } else if (old.secondary != null) {
      if (reduced) {
        _c.value = 0;
        _shown = null;
      } else {
        _c.reverse();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = Dims.of(context).tv;
    final open = widget.secondary != null;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_c.value);
        final primaryHidden = _c.value == 1;
        final secondary = _shown;
        // Expand: an offstage primary has no size, and the secondary must
        // still fill the page.
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: primaryHidden,
              child: TickerMode(
                enabled: !primaryHidden,
                child: ExcludeFocus(
                  excluding: open,
                  child: IgnorePointer(
                    ignoring: open,
                    // The page in front of the axis grows a little as it leaves.
                    child: Opacity(
                      opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                      child: tv
                          ? widget.primary
                          : Transform.scale(scale: 1 + 0.04 * t, child: widget.primary),
                    ),
                  ),
                ),
              ),
            ),
            if (secondary != null)
              ExcludeFocus(
                excluding: !open,
                child: IgnorePointer(
                  ignoring: !open,
                  child: Opacity(
                    opacity: ((t - 0.25) / 0.75).clamp(0.0, 1.0),
                    child: tv ? secondary : Transform.scale(scale: 0.94 + 0.06 * t, child: secondary),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A route that comes in on the shared axis: it fades in while sliding up
/// 4% (and the page under it is left as it was, scroll and focus included).
Route<T> sharedAxisRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 320),
  reverseTransitionDuration: const Duration(milliseconds: 260),
  pageBuilder: (context, _, _) => builder(context),
  transitionsBuilder: (context, animation, _, child) {
    if (Motion.of(context).reduced) return child;
    final t = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(t),
        child: child,
      ),
    );
  },
);

/// Fades [child] in and lifts it 16 dp into place once, after a delay that
/// grows with [index] (so a list arrives as a cascade). Runs when the widget
/// is first built, which for a lazy grid is when the item scrolls into view.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  /// Delay per index step; the cascade stops growing after [_maxSteps].
  static const step = Duration(milliseconds: 40);
  static const _maxSteps = 8;
  static const _run = Duration(milliseconds: 280);

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late Animation<double> _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final delay = StaggeredEntrance.step * widget.index.clamp(0, StaggeredEntrance._maxSteps);
    final total = delay + StaggeredEntrance._run;
    final c = AnimationController(vsync: this, duration: total);
    _c = c;
    // One controller with a delayed interval, rather than a Timer: nothing is
    // left pending when the item is scrolled away early.
    _t = CurvedAnimation(
      parent: c,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: Curves.easeOutCubic),
    );
    if (Motion.of(context).reduced) {
      c.value = 1;
    } else {
      c.forward();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) => _t.value == 1
        ? child!
        : Opacity(
            opacity: _t.value,
            child: Transform.translate(offset: Offset(0, 16 * (1 - _t.value)), child: child),
          ),
  );
}

/// Drives every [SkeletonBox] below it with one shared sweep.
///
/// The sweep stops after about 40 s (a load that slow is not helped by a
/// moving placeholder), so a hung request never keeps frames coming forever.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  static const _maxSweeps = 28;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    // Slower on a TV: fewer changes per second, same look from the sofa.
    final period = Duration(milliseconds: Dims.of(context).tv ? 1800 : 1400);
    final c = AnimationController(vsync: this, duration: period);
    _c = c;
    if (!Motion.of(context).reduced) {
      c.repeat(count: _maxSweeps);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ShimmerScope(animation: _c!, child: widget.child);
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_ShimmerScope old) => old.animation != animation;
}

/// A placeholder block in the skeleton of a page that is loading. Static
/// without a [Shimmer] above it.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = 10});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    final base = Color.alphaBlend(c.text.withValues(alpha: 0.06), c.surface);
    final glow = Color.alphaBlend(c.text.withValues(alpha: 0.13), c.surface);
    final animation = context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;
    final shape = BorderRadius.circular(radius);
    Widget box(double t) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [base, glow, base],
          stops: const [0.35, 0.5, 0.65],
          transform: _Sweep(t),
        ),
      ),
      // No width means as wide as allowed: in a start-aligned column a
      // null width would shrink the box to nothing.
      child: SizedBox(width: width ?? double.infinity, height: height),
    );
    if (animation == null) return box(-1);
    return RepaintBoundary(
      child: AnimatedBuilder(animation: animation, builder: (context, _) => box(animation.value * 2 - 1)),
    );
  }
}

/// Slides the gradient across the box: -1 is off the left edge, 1 off the right.
class _Sweep extends GradientTransform {
  const _Sweep(this.t);

  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * t * 1.3, 0, 0);
}
