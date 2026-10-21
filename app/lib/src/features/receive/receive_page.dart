import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services.dart';
import '../../theme.dart';
import '../../ui/dims.dart';
import '../../ui/focus_card.dart';
import '../../ui/home_page.dart' show ActionLabel;
import 'receive_service.dart';

/// Opens the "send from your phone" screen. The receiver runs while it is open.
Future<void> openReceive(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReceivePage()));
}

/// Placeholder body until the LocalSend work package.
class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  final _focus = SectionFocus();
  late final ReceiveService _service = AppServices.of(context).receive;

  @override
  void initState() {
    super.initState();
    unawaited(_service.start());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.entry.requestFocus();
    });
  }

  @override
  void dispose() {
    unawaited(_service.stop());
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        body: Overscan(
          child: FocusScope(
            child: Padding(
              padding: EdgeInsets.all(d.phone ? 16 : 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send from phone', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    'Receiving links from a phone is coming soon.',
                    style: TextStyle(color: ChithramColors.textDim, fontSize: d.t(14)),
                  ),
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
    );
  }
}
