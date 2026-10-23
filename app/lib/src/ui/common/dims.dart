import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'form_factor.dart';

export 'form_factor.dart' show FormFactor;

/// Sizes that depend on the screen, so the same widgets serve TV, phone and
/// desktop. Read with [Dims.of].
class Dims {
  const Dims._(this.form);

  final FormFactor form;

  bool get tv => form == FormFactor.tv;
  bool get phone => form == FormFactor.phone;

  /// The window-size guess: phone below 600 dp wide; a wide Android screen is
  /// a TV; the rest desktop. Only a fallback (tests): the app knows its form
  /// factor from the device and hands it down in a [FormScope].
  static FormFactor formFor(Size size) {
    if (size.width < 600) return FormFactor.phone;
    if (defaultTargetPlatform == TargetPlatform.android && size.width >= 900) {
      return FormFactor.tv;
    }
    return FormFactor.desktop;
  }

  static Dims of(BuildContext context) =>
      Dims._(FormScope.maybeOf(context) ?? formFor(MediaQuery.sizeOf(context)));

  /// A font size: never below 24 on a TV (10-foot reading), bigger there.
  double t(double base) => tv ? math.max(24, base * 1.25) : base;

  /// A length (tile sizes, icons): larger on a TV.
  double u(double base) => tv ? base * 1.35 : base;

  double get railOpen => tv ? 290 : 220;
  double get railClosed => tv ? 100 : 84;
}

/// 5% overscan-safe padding on an Android TV; nothing elsewhere (a desktop in
/// 10-foot mode has no overscan).
class Overscan extends StatelessWidget {
  const Overscan({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (!Dims.of(context).tv || defaultTargetPlatform != TargetPlatform.android) return child;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.05, vertical: size.height * 0.05),
      child: child,
    );
  }
}
