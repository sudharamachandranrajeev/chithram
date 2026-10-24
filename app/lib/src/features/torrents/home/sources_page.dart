import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../find/torznab/torznab_settings.dart';
import '../../../plugins/ui/plugins_settings.dart';
import '../../../ui/common/dims.dart';
import '../../../ui/tv/focus_card.dart';

/// Where "Add a source" leads: search plugins and Torznab endpoints, the two
/// kinds of source Torrent Home reads.
Future<void> openSources(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SourcesPage()));

class SourcesPage extends StatefulWidget {
  const SourcesPage({super.key});

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  final _focus = SectionFocus();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.entry.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final body = FocusScope(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(d.phone ? 8 : 24, 16, d.phone ? 8 : 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PluginsSettings(),
            TorznabSettings(entry: _focus),
          ],
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Scaffold(
        appBar: d.phone ? AppBar(title: const Text('Sources')) : null,
        body: d.phone ? body : Overscan(child: body),
      ),
    );
  }
}
