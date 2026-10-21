import 'package:flutter/material.dart';

import '../../ui/focus_card.dart';
import '../../ui/home_page.dart' show ActionLabel;
import 'receive_page.dart';

/// Settings section for receiving links from a phone.
class ReceiveSettings extends StatelessWidget {
  const ReceiveSettings({super.key, this.entry});

  /// Gets the card's focus node when this is the first focusable thing on the page.
  final SectionFocus? entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FocusCard(
        focusNode: entry?.entry,
        section: entry,
        radius: 24,
        onActivate: () => openReceive(context),
        child: const ActionLabel(text: 'Send from phone'),
      ),
    );
  }
}
