import 'package:flutter/material.dart';

import '../desktop/desktop_shell.dart';
import '../phone/phone_shell.dart';
import '../tv/tv_shell.dart';
import 'dims.dart';

/// The app's frame, one per form factor: [PhoneShell] on a phone or tablet,
/// [TvShell] on a TV (and on a desktop in 10-foot TV mode, which the app turns
/// into the TV form factor), [DesktopShell] on a desktop. All show the same
/// pages and share all services.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) => switch (Dims.of(context).form) {
        FormFactor.phone => const PhoneShell(),
        FormFactor.tv => const TvShell(),
        FormFactor.desktop => const DesktopShell(),
      };
}
