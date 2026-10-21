import 'package:flutter/widgets.dart';

/// Widget keys for the receive prompt and screen, for tests.
abstract final class ReceiveKeys {
  static const prompt = ValueKey('receive-prompt');
  static const accept = ValueKey('receive-accept');
  static const reject = ValueKey('receive-reject');
  static const page = ValueKey('receive-page');
  static const addresses = ValueKey('receive-addresses');
}
