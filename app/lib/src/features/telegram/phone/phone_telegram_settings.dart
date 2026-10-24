import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services.dart';
import '../telegram_keys.dart';
import '../telegram_page.dart';
import '../telegram_service.dart';
import '../telegram_settings.dart';

/// Telegram settings as list tiles.
class PhoneTelegramSettings extends StatelessWidget {
  const PhoneTelegramSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).telegram;
    return ValueListenableBuilder<TelegramState>(
      valueListenable: service.state,
      builder: (context, state, _) => Column(
        children: [
          ListTile(
            key: TelegramKeys.setup,
            minTileHeight: 56,
            leading: const Icon(Icons.telegram),
            title: const Text('Telegram'),
            subtitle: Text(TelegramSettings.label(state).replaceFirst('Telegram: ', '')),
            onTap: () => unawaited(openTelegram(context)),
          ),
          if (state.status == TelegramStatus.ready)
            ListTile(
              key: TelegramKeys.clear,
              minTileHeight: 56,
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Clear Telegram downloads'),
              onTap: () async {
                await service.clearDownloads();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Telegram downloads cleared')));
                }
              },
            ),
        ],
      ),
    );
  }
}
