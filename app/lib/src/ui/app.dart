import 'package:flutter/material.dart';

import '../spikes/registry.dart';
import '../theme.dart';
import 'shell.dart';

class ChithramApp extends StatelessWidget {
  const ChithramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chithram',
      debugShowCheckedModeBanner: false,
      theme: buildChithramTheme(),
      home: const Shell(),
      // Debug-only spike pages (see spikes/registry.dart); null in release.
      initialRoute: spikeInitialRoute(),
      onGenerateRoute: spikeRoute,
      onUnknownRoute: (settings) =>
          MaterialPageRoute<void>(builder: (_) => const Shell()),
    );
  }
}
