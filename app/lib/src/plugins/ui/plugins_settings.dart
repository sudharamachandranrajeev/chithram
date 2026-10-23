import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/common/dims.dart';

/// R0 stub: the section's place in Settings. The owning work package fills it in.
class PluginsSettings extends StatelessWidget {
  const PluginsSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Search plugins', style: TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Add search plugins (nova3 format) here.', style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14))),
        ],
      ),
    );
  }
}
