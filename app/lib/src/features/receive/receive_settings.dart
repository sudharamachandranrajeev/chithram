import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../ui/common/dims.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import '../../ui/common/text_entry.dart';
import 'receive_page.dart';
import 'receive_service.dart';

/// Settings section for receiving links from a phone: the screen, the name
/// phones see, a PIN, and whether to keep receiving while the app is open.
class ReceiveSettings extends StatefulWidget {
  const ReceiveSettings({super.key, this.entry});

  /// Gets the card's focus node when this is the first focusable thing on the page.
  final SectionFocus? entry;

  @override
  State<ReceiveSettings> createState() => _ReceiveSettingsState();
}

class _ReceiveSettingsState extends State<ReceiveSettings> {
  Future<void> _rename() async {
    final services = AppServices.of(context);
    final name = await askText(
      context,
      title: 'Name phones see',
      initial: services.receive.alias,
      kind: TextEntryKind.search,
    );
    if (name == null) return;
    await services.prefs.set(ReceivePrefs.alias, name.trim().isEmpty ? null : name.trim());
    await services.receive.settingsChanged();
    if (mounted) setState(() {});
  }

  Future<void> _setPin() async {
    final services = AppServices.of(context);
    final pin = await askText(
      context,
      title: 'PIN (4 to 8 digits, empty for none)',
      hint: '1234',
      kind: TextEntryKind.pin,
    );
    if (pin == null || !mounted) return;
    if (pin.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A PIN is 4 to 8 digits')));
      return;
    }
    await services.prefs.set(ReceivePrefs.pin, pin.isEmpty ? null : pin);
    await services.receive.settingsChanged();
    if (mounted) setState(() {});
  }

  Future<void> _toggleKeep() async {
    final services = AppServices.of(context);
    await services.prefs.set(ReceivePrefs.keep, !services.prefs.getBool(ReceivePrefs.keep));
    await services.receive.keepChanged();
    if (mounted) setState(() {});
  }

  Widget _card(String text, VoidCallback onActivate, {FocusNode? node, SectionFocus? section}) => Padding(
        padding: const EdgeInsets.all(8),
        child: FocusCard(
          focusNode: node,
          section: section,
          radius: 24,
          onActivate: onActivate,
          child: ActionLabel(text: text),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final prefs = services.prefs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A phone is the sender; the button is for the big screen.
        if (!Dims.of(context).phone)
          _card('Send from phone', () => openReceive(context), node: widget.entry?.entry, section: widget.entry),
        _card('Name phones see: ${services.receive.alias}', _rename),
        _card('Receive PIN: ${prefs.getString(ReceivePrefs.pin) == null ? 'off' : 'on'}', _setPin),
        _card(
          'Keep receiving while Chithram is open: ${prefs.getBool(ReceivePrefs.keep) ? 'on' : 'off'}',
          _toggleKeep,
        ),
      ],
    );
  }
}
