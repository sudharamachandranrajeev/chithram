import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/common/dims.dart';

/// R0 stub: the section's place in Settings. The owning work package fills it in.
class CacheSettings extends StatelessWidget {
  const CacheSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Image cache', style: TextStyle(fontSize: d.t(20), fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Posters and backdrops are cached on this device.', style: TextStyle(color: ChithramColors.of(context).textDim, fontSize: d.t(14))),
        ],
      ),
    );
  }
}
