import 'package:flutter/material.dart';

import '../../theme.dart';
import 'dims.dart';
import 'tokens.dart';

/// Where a media request stands. Each status has a colour, an icon and a
/// label; the chip never relies on colour alone.
enum RequestStatus {
  requested('Requested', Icons.schedule),
  awaitingApproval('Awaiting approval', Icons.hourglass_top),
  searching('Searching', Icons.travel_explore),
  downloading('Downloading', Icons.downloading),
  importing('Importing', Icons.move_to_inbox),
  available('Available', Icons.check_circle),
  failed('Failed', Icons.error);

  const RequestStatus(this.label, this.icon);

  final String label;
  final IconData icon;

  Color color(StatusColors c) => switch (this) {
        requested => c.requested,
        awaitingApproval => c.awaitingApproval,
        searching => c.searching,
        downloading => c.downloading,
        importing => c.importing,
        available => c.available,
        failed => c.failed,
      };
}

/// A pill with the status icon and label: the status colour at 16% over the
/// surface, a 1 dp border at 40%. [progress] (0 to 1) shows as a percent on
/// [RequestStatus.downloading].
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.progress});

  final RequestStatus status;
  final double? progress;

  /// The label as drawn, e.g. "Downloading 42%".
  String get text {
    final p = progress;
    if (status == RequestStatus.downloading && p != null) {
      return '${status.label} ${(p.clamp(0.0, 1.0) * 100).round()}%';
    }
    return status.label;
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final color = status.color(colors.status);
    final height = switch (d.form) {
      FormFactor.desktop => 24.0,
      FormFactor.phone => 28.0,
      FormFactor.tv => 36.0,
    };
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: d.tv ? Space.s12 : Space.s8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.16), colors.surface),
        borderRadius: BorderRadius.circular(Radii.chip),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: height * 0.58, color: color),
          const SizedBox(width: Space.s4),
          Text(text, style: d.type.meta.copyWith(color: color, height: 1.1)),
        ],
      ),
    );
  }
}
