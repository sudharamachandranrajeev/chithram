import 'package:flutter/material.dart';

import '../../../core/services.dart';
import '../../../ui/text_entry.dart';
import '../receive_page.dart';
import '../receive_service.dart';

/// Receive settings as list tiles: open the Receive screen, the name other
/// devices see, a PIN, and whether to keep receiving while the app is open.
/// (A phone is normally the sender, so the screen is here and not in the tabs.)
class PhoneReceiveSettings extends StatefulWidget {
  const PhoneReceiveSettings({super.key});

  @override
  State<PhoneReceiveSettings> createState() => _PhoneReceiveSettingsState();
}

class _PhoneReceiveSettingsState extends State<PhoneReceiveSettings> {
  Future<void> _rename() async {
    final services = AppServices.of(context);
    final name = await askText(
      context,
      title: 'Name other devices see',
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

  Future<void> _setKeep(bool on) async {
    final services = AppServices.of(context);
    await services.prefs.set(ReceivePrefs.keep, on);
    await services.receive.keepChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final prefs = services.prefs;
    return Column(
      children: [
        ListTile(
          key: const ValueKey('settings-receive'),
          minTileHeight: 56,
          leading: const Icon(Icons.download_rounded),
          title: const Text('Receive links and files'),
          subtitle: const Text('From LocalSend on another device'),
          onTap: () => openReceive(context),
        ),
        ListTile(
          minTileHeight: 56,
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Name other devices see'),
          subtitle: Text(services.receive.alias),
          onTap: _rename,
        ),
        ListTile(
          minTileHeight: 56,
          leading: const Icon(Icons.pin_outlined),
          title: const Text('Receive PIN'),
          subtitle: Text(prefs.getString(ReceivePrefs.pin) == null ? 'Off' : 'On'),
          onTap: _setPin,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.hearing_rounded),
          title: const Text('Keep receiving while Chithram is open'),
          value: prefs.getBool(ReceivePrefs.keep),
          onChanged: _setKeep,
        ),
      ],
    );
  }
}
