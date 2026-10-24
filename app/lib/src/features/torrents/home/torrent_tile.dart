import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../ui/common/dims.dart';
import '../torrent_logic.dart';
import 'popular_item.dart';

/// "3 h", "2 d", "5 w": how old [published] is at [now]; empty without a date.
String ageText(DateTime? published, DateTime now) {
  if (published == null) return '';
  final d = now.difference(published);
  if (d.inMinutes < 60) return 'now';
  if (d.inHours < 24) return '${d.inHours} h';
  if (d.inDays < 14) return '${d.inDays} d';
  return '${d.inDays ~/ 7} w';
}

/// Name, size, seeders, source, age.
class TorrentTileBody extends StatelessWidget {
  const TorrentTileBody({super.key, required this.item, this.width, this.now});

  final PopularItem item;
  final double? width;

  /// For tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final dim = TextStyle(color: ChithramColors.textDim, fontSize: d.t(13));
    final age = ageText(item.published, now ?? DateTime.now());
    final facts = [if (item.sizeBytes != null) formatBytes(item.sizeBytes!), if (age.isNotEmpty) age].join(' · ');
    return Container(
      width: width ?? d.u(300),
      padding: EdgeInsets.all(d.u(12)),
      color: ChithramColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: d.t(15), fontWeight: FontWeight.w600),
          ),
          SizedBox(height: d.u(8)),
          Row(
            children: [
              Icon(Icons.arrow_upward_rounded, size: d.t(16), color: ChithramColors.accent),
              const SizedBox(width: 2),
              Text(
                '${item.seeders ?? 0}',
                style: TextStyle(color: ChithramColors.accent, fontSize: d.t(14), fontWeight: FontWeight.w600),
              ),
              if (facts.isNotEmpty) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: dim),
                ),
              ],
            ],
          ),
          SizedBox(height: d.u(4)),
          Text(
            item.sources.isEmpty ? item.sourceLabel : item.sources.join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dim,
          ),
        ],
      ),
    );
  }
}
