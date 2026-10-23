import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/common/dims.dart';

/// R0 stub: the section's place in Settings. The owning work package fills it in.
class TorznabSettings extends StatelessWidget {
  const TorznabSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Torznab', style: TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Add your own Torznab indexers here.', style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14))),
        ],
      ),
    );
  }
}
