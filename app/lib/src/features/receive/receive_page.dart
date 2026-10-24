import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import '../telegram/telegram_received.dart';
import 'phone/phone_receive_page.dart';
import 'receive_keys.dart';
import 'receive_service.dart';

/// Opens the "send from your phone" screen. The receiver runs while it is open.
Future<void> openReceive(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReceivePage()));
}

class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  final _focus = SectionFocus();
  bool _started = false;
  late final ReceiveService _service = AppServices.of(context).receive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _started = true;
      unawaited(_service.start());
      _focus.entry.requestFocus();
    });
  }

  @override
  void dispose() {
    if (_started) unawaited(_service.stop());
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    if (d.phone) return PhoneReceivePage(service: _service);
    final dim = TextStyle(color: ChithramColors.textDim, fontSize: d.t(14));
    final pin = AppServices.of(context).prefs.getString(ReceivePrefs.pin);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        key: ReceiveKeys.page,
        body: Overscan(
          child: FocusScope(
            child: Padding(
              padding: EdgeInsets.all(d.phone ? 16 : 32),
              child: ValueListenableBuilder<ReceiveState>(
                valueListenable: _service.state,
                builder: (context, state, _) => SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Send from phone', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                        'Open LocalSend on your phone, pick "${state.alias.isEmpty ? _service.alias : state.alias}" '
                        'and send a link, a magnet or a .torrent file. You are asked before anything is used, '
                        'and nothing plays on its own.',
                        style: dim,
                      ),
                      const SizedBox(height: 16),
                      ..._status(state, dim, pin != null),
                      const TelegramReceiveSection(),
                      const SizedBox(height: 28),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: FocusCard(
                          focusNode: _focus.entry,
                          section: _focus,
                          radius: 24,
                          onActivate: () => Navigator.of(context).maybePop(),
                          child: const ActionLabel(text: 'Back'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _status(ReceiveState state, TextStyle dim, bool hasPin) {
    switch (state.status) {
      case ReceiveStatus.stopped:
      case ReceiveStatus.starting:
        return [Text('Starting...', style: dim)];
      case ReceiveStatus.error:
        return [Text(state.error ?? 'Receiving is not available.', style: dim.copyWith(color: Colors.redAccent))];
      case ReceiveStatus.listening:
        return [
          Text('Waiting for your phone.', style: dim.copyWith(color: Colors.white)),
          if (hasPin) Text('A PIN is required. Your phone will ask for it.', style: dim),
          const SizedBox(height: 8),
          Text(
            'If your phone does not find this device, add it by address in LocalSend:',
            style: dim,
          ),
          Text(state.addresses.join('   '), key: ReceiveKeys.addresses, style: dim.copyWith(color: Colors.white)),
          if (state.note != null) Text(state.note!, style: dim),
        ];
    }
  }
}
