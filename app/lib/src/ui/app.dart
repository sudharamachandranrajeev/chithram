import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/services.dart';
import '../spikes/registry.dart';
import '../theme.dart';
import 'form_factor.dart';
import 'shell.dart';

class ChithramApp extends StatefulWidget {
  /// [services] defaults to in-memory ones, so `const ChithramApp()` works in
  /// tests; `main()` passes the real ones.
  ///
  /// [formFactor] is what the device is (see [resolveFormFactor]). Without it
  /// the app asks the `FORM_FACTOR` define and the platform, and if neither
  /// knows, every widget falls back to the window size (`flutter test`).
  const ChithramApp({super.key, this.services, this.formFactor});

  final AppServices? services;
  final FormFactor? formFactor;

  @override
  State<ChithramApp> createState() => _ChithramAppState();
}

class _ChithramAppState extends State<ChithramApp> {
  late final AppServices _services = widget.services ?? AppServices.memory();
  FormFactor? _shown;

  /// Desktop in 10-foot mode is the TV design; everything else is as detected.
  FormFactor? _effective() {
    final base = widget.formFactor ??
        resolveFormFactor(platform: defaultTargetPlatform, define: formFactorDefine);
    if (base == FormFactor.desktop && _services.prefs.getBool(tenFootPref)) return FormFactor.tv;
    return base;
  }

  @override
  Widget build(BuildContext context) {
    return AppServicesScope(
      services: _services,
      child: ListenableBuilder(
        listenable: _services.prefs,
        builder: (context, _) {
          final form = _effective();
          if (_shown != null && form != _shown) {
            // The design changed under the user: start again from Home.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _services.navigatorKey.currentState?.popUntil((r) => r.isFirst);
            });
          }
          _shown = form;
          final app = MaterialApp(
            navigatorKey: _services.navigatorKey,
            title: 'Chithram',
            debugShowCheckedModeBanner: false,
            theme: buildChithramTheme(form: form ?? FormFactor.tv),
            home: Shell(key: ValueKey(form)),
            // Debug-only spike pages (see spikes/registry.dart); null in release.
            initialRoute: spikeInitialRoute(),
            onGenerateRoute: spikeRoute,
            onUnknownRoute: (settings) =>
                MaterialPageRoute<void>(builder: (_) => const Shell()),
          );
          return form == null ? app : FormScope(form: form, child: app);
        },
      ),
    );
  }
}
