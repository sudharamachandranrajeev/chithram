import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import 'telegram_keys.dart';
import 'telegram_page.dart';
import 'telegram_service.dart';

/// Settings section for Telegram: the screen to sign in and see what arrived,
/// and clearing the downloads.
class TelegramSettings extends StatelessWidget {
  const TelegramSettings({super.key});

  static String label(TelegramState s) => switch (s.status) {
        TelegramStatus.unavailable => 'Telegram: not in this build',
        TelegramStatus.ready => 'Telegram: signed in',
        TelegramStatus.signedOut => 'Telegram: sign in',
        _ => 'Telegram: signing in',
      };

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).telegram;
    return ValueListenableBuilder<TelegramState>(
      valueListenable: service.state,
      builder: (context, state, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: FocusCard(
              key: TelegramKeys.setup,
              radius: 24,
              onActivate: () => unawaited(openTelegram(context)),
              child: ActionLabel(text: label(state)),
            ),
          ),
          if (state.status == TelegramStatus.ready)
            Padding(
              padding: const EdgeInsets.all(8),
              child: FocusCard(
                key: TelegramKeys.clear,
                radius: 24,
                onActivate: () async {
                  await service.clearDownloads();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Telegram downloads cleared')));
                  }
                },
                child: const ActionLabel(text: 'Clear Telegram downloads'),
              ),
            ),
        ],
      ),
    );
  }
}
