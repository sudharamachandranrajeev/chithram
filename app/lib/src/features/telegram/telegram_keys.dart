import 'package:flutter/widgets.dart';

/// Widget keys for the Telegram screens, for tests.
abstract final class TelegramKeys {
  static const page = ValueKey('telegram-page');
  static const qr = ValueKey('telegram-qr');
  static const signIn = ValueKey('telegram-sign-in');
  static const usePhone = ValueKey('telegram-use-phone');
  static const enterPhone = ValueKey('telegram-enter-phone');
  static const enterCode = ValueKey('telegram-enter-code');
  static const enterPassword = ValueKey('telegram-enter-password');
  static const signOut = ValueKey('telegram-sign-out');
  static const clear = ValueKey('telegram-clear');
  static const unavailable = ValueKey('telegram-unavailable');
  static const section = ValueKey('telegram-receive-section');
  static const setup = ValueKey('telegram-setup');
  static String item(int messageId) => 'telegram-item-$messageId';
}
