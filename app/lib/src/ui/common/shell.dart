import 'package:flutter/material.dart';

import 'form_factor.dart';
import '../phone/phone_shell.dart';
import '../tv/tv_shell.dart';

/// The app's frame. A phone or tablet gets [PhoneShell]; a TV and desktop get
/// [TvShell]. Both show the same pages and share all services.
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) => const FormSwitch(tv: TvShell(), phone: PhoneShell());
}
