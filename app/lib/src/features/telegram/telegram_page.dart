import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/text_entry.dart';
import '../../ui/phone/phone_widgets.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import 'telegram_keys.dart';
import 'telegram_received.dart';
import 'telegram_service.dart';

/// Opens Settings > Telegram: sign in (QR code first, phone number as the
/// fallback), see what arrived, sign out.
Future<void> openTelegram(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TelegramPage()));
}

class TelegramPage extends StatefulWidget {
  const TelegramPage({super.key});

  @override
  State<TelegramPage> createState() => _TelegramPageState();
}

class _TelegramPageState extends State<TelegramPage> {
  final _focus = SectionFocus();
  late final TelegramService _service = AppServices.of(context).telegram;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.entry.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _ask(String title, String hint, TextEntryKind kind, Future<String?> Function(String) submit) async {
    final text = await askText(context, title: title, hint: hint, kind: kind, acceptFromPhone: true);
    if (text == null || text.trim().isEmpty || !mounted) return;
    final error = await submit(text);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Widget _button(String label, VoidCallback onTap, {Key? key, bool entry = false}) {
    final d = Dims.of(context);
    if (d.phone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: phoneGutter, vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(key: key, onPressed: onTap, child: Text(label)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: FocusCard(
        key: key,
        focusNode: entry ? _focus.entry : null,
        section: entry ? _focus : null,
        radius: 24,
        onActivate: onTap,
        child: ActionLabel(text: label),
      ),
    );
  }

  Widget _text(String text, {bool strong = false, bool error = false}) {
    final d = Dims.of(context);
    final style = TextStyle(
      color: error ? Colors.redAccent : (strong ? Colors.white : ChithramColors.of(context).textDim),
      fontSize: d.t(14),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: d.phone ? phoneGutter : 8, vertical: 6),
      child: Text(text, style: style),
    );
  }

  List<Widget> _content(TelegramState s) {
    switch (s.status) {
      case TelegramStatus.unavailable:
        return [
          KeyedSubtree(key: TelegramKeys.unavailable, child: _text(s.message ?? 'Telegram is not available in this build.')),
          _text('The project owner has to register a Telegram app id for builds to sign in.'),
        ];
      case TelegramStatus.signedOut:
        return [
          _text(
            'Sign in with your own Telegram account. Videos and audio you send or forward to your '
            'Saved Messages are downloaded here and start playing. Chithram reads only Saved Messages.',
          ),
          _button('Sign in', () => unawaited(_service.start()), key: TelegramKeys.signIn, entry: true),
        ];
      case TelegramStatus.starting:
        return [_text('Connecting to Telegram...')];
      case TelegramStatus.qr:
        return [
          _text('On your phone, open Telegram > Settings > Devices > Link Desktop Device and scan this code.'),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(key: TelegramKeys.qr, data: s.qrLink ?? '', size: Dims.of(context).phone ? 220 : 280),
              ),
            ),
          ),
          _button('Use a phone number instead', _service.usePhoneNumber, key: TelegramKeys.usePhone, entry: true),
        ];
      case TelegramStatus.phone:
        return [
          if (s.message != null) _text(s.message!, error: true),
          _text('Enter the phone number of your Telegram account, with the country code.'),
          _button(
            'Enter phone number',
            () => _ask('Phone number', '+353 ...', TextEntryKind.search, _service.submitPhone),
            key: TelegramKeys.enterPhone,
            entry: true,
          ),
        ];
      case TelegramStatus.code:
        return [
          _text('Telegram sent a code to your Telegram app${s.phone == null || s.phone!.isEmpty ? '' : ' (${s.phone})'}.'),
          _button(
            'Enter code',
            () => _ask('Login code', '12345', TextEntryKind.search, _service.submitCode),
            key: TelegramKeys.enterCode,
            entry: true,
          ),
        ];
      case TelegramStatus.password:
        return [
          _text('This account has a two-step password${s.hint == null || s.hint!.isEmpty ? '' : ' (hint: ${s.hint})'}.'),
          _button(
            'Enter password',
            () => _ask('Two-step password', '', TextEntryKind.pin, _service.submitPassword),
            key: TelegramKeys.enterPassword,
            entry: true,
          ),
        ];
      case TelegramStatus.loggingOut:
        return [_text('Signing out...')];
      case TelegramStatus.error:
        return [
          _text(s.message ?? 'Telegram failed.', error: true),
          _button('Try again', () => unawaited(_service.start()), entry: true),
        ];
      case TelegramStatus.ready:
        return [
          _text('Signed in. Send or forward a video or audio file to your Saved Messages and it plays here.', strong: true),
          const TelegramReceiveSection(embedded: true),
          _button('Clear Telegram downloads', () => unawaited(_clear()), key: TelegramKeys.clear, entry: true),
          _button('Sign out', () => unawaited(_service.signOut()), key: TelegramKeys.signOut),
        ];
    }
  }

  Future<void> _clear() async {
    await _service.clearDownloads();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Telegram downloads cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final body = ValueListenableBuilder<TelegramState>(
      valueListenable: _service.state,
      builder: (context, state, _) => ListView(
        padding: EdgeInsets.only(bottom: 24, top: d.phone ? 0 : 8),
        children: _content(state),
      ),
    );
    if (d.phone) {
      return Scaffold(key: TelegramKeys.page, appBar: AppBar(title: const Text('Telegram')), body: SafeArea(child: body));
    }
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Scaffold(
        key: TelegramKeys.page,
        body: Overscan(
          child: FocusScope(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Telegram', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
