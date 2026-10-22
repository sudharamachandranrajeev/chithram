import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dims.dart';

/// Which kind of device the UI is built for. Decided once at launch from the
/// device, never from the window size (see [resolveFormFactor]).
enum FormFactor { phone, tv, desktop }

/// `--dart-define=FORM_FACTOR=tv|phone|desktop`: forces the form (tests, dev).
const formFactorDefine = String.fromEnvironment('FORM_FACTOR');

/// The prefs key of the desktop "10-foot TV mode" setting.
const tenFootPref = 'ui.tenFoot';

/// `--form-factor=` on the Android launch intent (see MainActivity).
const formFactorArgPrefix = '--form-factor=';

/// The channel the Android activity answers `formFactor` on (integration tests
/// build the app directly, so they ask instead of reading the launch args).
const appChannel = MethodChannel('dev.chithram/app');

FormFactor? parseFormFactor(String? name) {
  for (final f in FormFactor.values) {
    if (f.name == name) return f;
  }
  return null;
}

/// The value of `--form-factor=` in [args], if any.
String? formFactorArg(List<String> args) {
  for (final a in args) {
    if (a.startsWith(formFactorArgPrefix)) return a.substring(formFactorArgPrefix.length);
  }
  return null;
}

/// The form factor of this device, or null when nothing says: then [Dims.of]
/// falls back to the window size (that is how `flutter test` runs).
///
/// Order: [define] (tests, dev) > the desktop-only [tenFoot] preference >
/// detection ([arg] from the Android launcher; Windows and Linux are desktop).
FormFactor? resolveFormFactor({
  required TargetPlatform platform,
  String? define,
  String? arg,
  bool tenFoot = false,
}) {
  final forced = parseFormFactor(define);
  if (forced != null) return forced;
  switch (platform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return tenFoot ? FormFactor.tv : FormFactor.desktop;
    case TargetPlatform.android:
      final f = parseFormFactor(arg);
      return f == FormFactor.tv || f == FormFactor.phone ? f : null;
    default:
      return null;
  }
}

/// What the Android activity detected (tv or phone); null elsewhere.
Future<FormFactor?> androidFormFactor() async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    return parseFormFactor(await appChannel.invokeMethod<String>('formFactor'));
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Hands the resolved form factor to every widget below it.
class FormScope extends InheritedWidget {
  const FormScope({super.key, required this.form, required super.child});

  final FormFactor form;

  static FormFactor? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FormScope>()?.form;

  @override
  bool updateShouldNotify(FormScope oldWidget) => form != oldWidget.form;
}

/// [phone] on a phone or tablet; [tv] on a TV and on desktop.
class FormSwitch extends StatelessWidget {
  const FormSwitch({super.key, required this.tv, required this.phone});

  final Widget tv;
  final Widget phone;

  @override
  Widget build(BuildContext context) => Dims.of(context).phone ? phone : tv;
}

/// Which orientations the app allows: phones stay in portrait (the player
/// takes landscape itself and calls [restore] when it closes), tablets and
/// everything else rotate.
abstract final class OrientationPolicy {
  static List<DeviceOrientation> _allowed = DeviceOrientation.values;

  /// Tablets start at 600 dp on the short side.
  static const tabletShortestSide = 600.0;

  static bool isTablet(double shortestSideDp) => shortestSideDp >= tabletShortestSide;

  /// The orientations [form] allows on a screen with this short side.
  static List<DeviceOrientation> allowedFor(FormFactor form, double shortestSideDp) =>
      form == FormFactor.phone && !isTablet(shortestSideDp)
          ? const [DeviceOrientation.portraitUp]
          : DeviceOrientation.values;

  /// Called once at launch.
  static void apply(FormFactor form, {required double shortestSideDp}) {
    _allowed = allowedFor(form, shortestSideDp);
    if (form != FormFactor.phone) return;
    SystemChrome.setPreferredOrientations(_allowed);
    // Phones draw edge to edge (targetSdk 36 requires it); the shell pads.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// Back to the launch policy, after something (the player) changed it.
  static void restore() {
    SystemChrome.setPreferredOrientations(_allowed);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
