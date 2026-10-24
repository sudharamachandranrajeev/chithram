import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tdlib/tdlib.dart' show TgMediaKind;

import '../../core/services.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/phone/phone_widgets.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import 'telegram_keys.dart';
import 'telegram_page.dart';
import 'telegram_service.dart';

String formatBytes(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) return '${(bytes / (1024 * mb)).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// "From Telegram" on the Receive screen: files from Saved Messages (select
/// one to play it), or a way to set Telegram up.
class TelegramReceiveSection extends StatelessWidget {
  const TelegramReceiveSection({super.key, this.embedded = false});

  /// Inside the Telegram page itself: no "set up" row.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).telegram;
    final d = Dims.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([service, service.state]),
      builder: (context, _) {
        final state = service.state.value;
        final gutter = d.phone ? phoneGutter : 8.0;
        final head = TextStyle(fontSize: d.t(16), fontWeight: FontWeight.w600, color: Colors.white);
        final dim = TextStyle(color: ChithramColors.of(context).textDim, fontSize: d.t(14));
        if (state.status != TelegramStatus.ready) {
          if (embedded) return const SizedBox.shrink();
          return Column(
            key: TelegramKeys.section,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 4),
                child: Text('From Telegram', style: head),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 4),
                child: Text(
                  state.status == TelegramStatus.unavailable
                      ? (state.message ?? 'Telegram is not available in this build.')
                      : 'Sign in to receive videos and audio you send to your Saved Messages.',
                  style: dim,
                ),
              ),
              if (state.status != TelegramStatus.unavailable) _open(context, 'Set up Telegram', d.phone),
            ],
          );
        }
        final items = service.items;
        return Column(
          key: TelegramKeys.section,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 4), child: Text('From Telegram', style: head)),
            if (items.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 4),
                child: Text('Nothing yet. Send a video or audio file to your Saved Messages.', style: dim),
              ),
            for (final item in items) _row(context, service, item, d.phone),
            if (!embedded) _open(context, 'Telegram settings', d.phone),
          ],
        );
      },
    );
  }

  Widget _open(BuildContext context, String label, bool phone) {
    if (phone) {
      return ListTile(
        key: TelegramKeys.setup,
        minTileHeight: 56,
        leading: const Icon(Icons.telegram),
        title: Text(label),
        onTap: () => unawaited(openTelegram(context)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FocusCard(
        key: TelegramKeys.setup,
        radius: 24,
        onActivate: () => unawaited(openTelegram(context)),
        child: ActionLabel(text: label),
      ),
    );
  }

  static String _status(TelegramItem item) {
    final size = item.size > 0 ? formatBytes(item.size) : '';
    final p = item.progress;
    final state = item.isComplete
        ? 'Ready'
        : p != null && p > 0
            ? 'Downloading ${(p * 100).round()}%'
            : item.fromHistory
                ? 'Not downloaded'
                : 'Starting';
    return [if (size.isNotEmpty) size, state].join(' · ');
  }

  Widget _row(BuildContext context, TelegramService service, TelegramItem item, bool phone) {
    final key = ValueKey(TelegramKeys.item(item.media.messageId));
    if (phone) {
      return ListTile(
        key: key,
        minTileHeight: 56,
        leading: Icon(item.media.kind == TgMediaKind.audio ? Icons.audiotrack_rounded : Icons.movie_rounded),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_status(item)),
        onTap: () => unawaited(service.play(item)),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FocusCard(
        key: key,
        radius: 24,
        onActivate: () => unawaited(service.play(item)),
        child: ActionLabel(text: '${item.name}   ${_status(item)}'),
      ),
    );
  }
}
