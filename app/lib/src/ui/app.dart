import 'package:flutter/material.dart';

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
    );
  }
}
