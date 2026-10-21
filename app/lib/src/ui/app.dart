import 'package:flutter/material.dart';

import '../core/services.dart';
import '../spikes/registry.dart';
import '../theme.dart';
import '../intake/intake.dart';
import 'search_page.dart';
import 'shell.dart';

class ChithramApp extends StatefulWidget {
  /// [services] defaults to in-memory ones, so `const ChithramApp()` works in
  /// tests; `main()` passes the real ones.
  const ChithramApp({super.key, this.services});

  final AppServices? services;

  @override
  State<ChithramApp> createState() => _ChithramAppState();
}

class _ChithramAppState extends State<ChithramApp> {
  late final AppServices _services = widget.services ?? AppServices.memory();

  @override
  void initState() {
    super.initState();
    IntakeHooks.search = openSearch;
  }

  @override
  Widget build(BuildContext context) {
    return AppServicesScope(
      services: _services,
      child: MaterialApp(
        navigatorKey: _services.navigatorKey,
        title: 'Chithram',
        debugShowCheckedModeBanner: false,
        theme: buildChithramTheme(),
        home: const Shell(),
        // Debug-only spike pages (see spikes/registry.dart); null in release.
        initialRoute: spikeInitialRoute(),
        onGenerateRoute: spikeRoute,
        onUnknownRoute: (settings) =>
            MaterialPageRoute<void>(builder: (_) => const Shell()),
      ),
    );
  }
}
