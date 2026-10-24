import 'package:flutter/material.dart';

import '../../../core/services.dart';
import '../../../ui/phone/phone_widgets.dart';
import '../../telegram/telegram_received.dart';
import '../receive_keys.dart';
import '../receive_service.dart';

/// The Receive screen on a phone. The receiver itself is started and stopped
/// by the page that shows this ([service] is its service).
class PhoneReceivePage extends StatelessWidget {
  const PhoneReceivePage({super.key, required this.service});

  final ReceiveService service;

  @override
  Widget build(BuildContext context) {
    final hasPin = AppServices.of(context).prefs.getString(ReceivePrefs.pin) != null;
    return Scaffold(
      key: ReceiveKeys.page,
      appBar: AppBar(title: const Text('Receive')),
      body: SafeArea(
        child: ValueListenableBuilder<ReceiveState>(
          valueListenable: service.state,
          builder: (context, state, _) {
            final name = state.alias.isEmpty ? service.alias : state.alias;
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                PhoneNote(
                  'Open LocalSend on the other device, pick "$name" and send a link, a magnet or a '
                  '.torrent file. You are asked before anything is used, and nothing plays on its own.',
                ),
                ..._status(state, hasPin),
                const TelegramReceiveSection(),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _status(ReceiveState state, bool hasPin) {
    switch (state.status) {
      case ReceiveStatus.stopped:
      case ReceiveStatus.starting:
        return const [PhoneNote('Starting...')];
      case ReceiveStatus.error:
        return [PhoneNote(state.error ?? 'Receiving is not available.', color: Colors.redAccent)];
      case ReceiveStatus.listening:
        return [
          const PhoneNote('Waiting for the other device.', color: Colors.white),
          if (hasPin) const PhoneNote('A PIN is required. The other device will ask for it.'),
          const PhoneNote('If it does not find this device, add it by address in LocalSend:'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: phoneGutter),
            child: SelectableText(state.addresses.join('   '), key: ReceiveKeys.addresses),
          ),
          if (state.note != null) PhoneNote(state.note!),
        ];
    }
  }
}
