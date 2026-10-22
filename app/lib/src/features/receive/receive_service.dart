import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_rx/localsend_rx.dart';

import '../../core/paths.dart';
import '../../core/prefs.dart';
import '../../intake/intake.dart';
import '../../ui/common/dims.dart';
import 'receive_prompt.dart';

enum ReceiveStatus { stopped, starting, listening, error }

class ReceiveState {
  const ReceiveState(this.status, {this.addresses = const [], this.error, this.alias = '', this.note});

  final ReceiveStatus status;

  /// Private addresses the phone can type in when discovery is blocked.
  final List<String> addresses;
  final String? error;

  /// The name phones see in their device list.
  final String alias;

  /// Something worth telling the user while listening (discovery is off).
  final String? note;
}

class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Prefs keys.
abstract final class ReceivePrefs {
  static const alias = 'receive.alias';
  static const pin = 'receive.pin';
  static const keep = 'receive.keep';
}

/// Runs the LocalSend receiver while the Receive screen is open (or, when the
/// user turned it on, for as long as the app runs). Every transfer is shown in
/// a prompt first; what arrives goes through the intake path and never plays
/// by itself.
class ReceiveService {
  ReceiveService({
    required this.navigatorKey,
    required this.paths,
    required this.prefs,
    this.testConfig,
    this.testIdentity,
  }) {
    if (prefs.getBool(ReceivePrefs.keep)) unawaited(Future(_ensure));
  }

  final GlobalKey<NavigatorState> navigatorKey;
  final AppPaths paths;
  final Prefs prefs;

  /// Tests only: replaces the receiver config (loopback, fixed port).
  final LsReceiverConfig Function(LsReceiverConfig base)? testConfig;
  final LsIdentity? testIdentity;

  static const _channel = MethodChannel('dev.chithram/net');

  final _state = ValueNotifier(const ReceiveState(ReceiveStatus.stopped));
  final _closePrompt = _Signal();
  LsReceiver? _receiver;
  StreamSubscription<LsIncoming>? _sub;
  Future<LsIdentity>? _identity;
  int _holders = 0;
  bool _busy = false;

  /// Texts the user already chose an action for in the prompt.
  final _confirmed = <String>{};

  /// Open text fields that take accepted phone text (newest last).
  final _sinks = <void Function(String)>[];

  /// While a field with `acceptFromPhone` is open, accepted LocalSend text goes
  /// into it instead of the intake path (keys and long tokens). The offer
  /// prompt is still shown first. Returns the remover; call it when the field
  /// closes.
  VoidCallback routeTextTo(void Function(String text) sink) {
    _sinks.add(sink);
    return () => _sinks.remove(sink);
  }

  ValueListenable<ReceiveState> get state => _state;

  /// The name phones see: the stored one, else `Chithram on <device>`.
  String get alias {
    final custom = prefs.getString(ReceivePrefs.alias);
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    final host = Platform.isAndroid ? 'Android' : Platform.localHostname;
    return host.isEmpty ? 'Chithram' : 'Chithram on $host';
  }

  /// Called by the Receive screen when it opens.
  Future<void> start() {
    _holders++;
    return _ensure();
  }

  /// Called by the Receive screen when it closes.
  Future<void> stop() {
    if (_holders > 0) _holders--;
    return _maybeStop();
  }

  /// The "keep receiving while Chithram is open" setting changed.
  Future<void> keepChanged() => prefs.getBool(ReceivePrefs.keep) ? _ensure() : _maybeStop();

  /// The alias or PIN changed: a running receiver picks it up.
  Future<void> settingsChanged() async {
    if (_receiver == null) return;
    await _shutdown();
    await _ensure();
  }

  bool get _wanted => _holders > 0 || prefs.getBool(ReceivePrefs.keep);

  Future<void> _maybeStop() async {
    if (!_wanted) await _shutdown();
  }

  Future<void> _ensure() async {
    if (_receiver != null || _busy) return;
    _busy = true;
    _state.value = ReceiveState(ReceiveStatus.starting, alias: alias);
    try {
      final identity = await (_identity ??= testIdentity != null
          ? Future.value(testIdentity)
          : LsIdentity.loadOrCreate(Directory('${paths.support.path}/localsend')));
      if (!_wanted) {
        _state.value = const ReceiveState(ReceiveStatus.stopped);
        return;
      }
      var config = LsReceiverConfig(
        alias: alias,
        deviceType: _deviceType(),
        pin: _pin(),
      );
      config = testConfig?.call(config) ?? config;
      final rx = LsReceiver(identity: identity, config: config, onOffer: _onOffer);
      await rx.start();
      _receiver = rx;
      _sub = rx.received.listen(_onIncoming);
      await _multicastLock(true);
      _state.value = ReceiveState(
        ReceiveStatus.listening,
        addresses: [for (final a in rx.addresses) a.address],
        alias: config.alias,
        note: rx.discoveryError,
      );
    } on LsBindException catch (e) {
      _identity = null;
      _state.value = ReceiveState(ReceiveStatus.error, error: e.message, alias: alias);
    } catch (e) {
      _identity = null;
      _state.value = ReceiveState(ReceiveStatus.error, error: 'Could not start receiving: $e', alias: alias);
    } finally {
      _busy = false;
    }
  }

  Future<void> _shutdown() async {
    final rx = _receiver;
    _receiver = null;
    _closePrompt.fire();
    await _sub?.cancel();
    _sub = null;
    await rx?.dispose();
    await _multicastLock(false);
    _state.value = const ReceiveState(ReceiveStatus.stopped);
  }

  Future<void> _multicastLock(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('multicastLock', on);
    } on PlatformException {
      // Discovery is best effort; the address list is the fallback.
    } on MissingPluginException {
      // Not running inside the app (tests).
    }
  }

  String? _pin() {
    final pin = prefs.getString(ReceivePrefs.pin);
    return pin != null && RegExp(r'^\d{4,8}$').hasMatch(pin) ? pin : null;
  }

  String _deviceType() {
    final context = navigatorKey.currentContext;
    if (context == null) return 'desktop';
    return Dims.of(context).phone ? 'mobile' : 'desktop';
  }

  // ---- transfers ---------------------------------------------------------

  Future<bool> _onOffer(LsOffer offer) async {
    // A choice only covers the transfer it was made for.
    _confirmed.clear();
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return false;
    final single = offer.files.length == 1 ? offer.files.single : null;
    final text = single?.preview;
    final torrent = single != null && text == null && single.name.toLowerCase().endsWith('.torrent');
    final choice = await showReceivePrompt(context, offer, dismiss: _closePrompt);
    if (!choice) return false;
    // The user picked the action in the prompt: skip the second dialog.
    if (text != null && intakeActionLabel(classify(text)) != null) _confirmed.add(text);
    if (torrent) _confirmed.add(single.name);
    return true;
  }

  @visibleForTesting
  void debugIncoming(LsIncoming item) => _onIncoming(item);

  void _onIncoming(LsIncoming item) {
    if (item is TextIncoming && _sinks.isNotEmpty) {
      _confirmed.remove(item.text);
      _sinks.last(item.text);
      return;
    }
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    switch (item) {
      case TextIncoming(:final text, :final fromAlias):
        unawaited(handleIntake(context, TextPayload(text, from: fromAlias), confirmed: _confirmed.remove(text)));
      case FileIncoming(:final name, :final bytes, :final fromAlias):
        unawaited(handleIntake(context, TorrentFilePayload(bytes, name, from: fromAlias), confirmed: _confirmed.remove(name)));
    }
  }
}
