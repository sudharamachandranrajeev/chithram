import 'package:flutter/widgets.dart';

/// Widget keys the plugin tests look for.
abstract final class PluginKeys {
  static const page = ValueKey('plugins-page');
  static const addRepo = ValueKey('plugins-add-repo');
  static const addSingle = ValueKey('plugins-add-single');
  static const trustContinue = ValueKey('plugins-trust-continue');
  static const pickNext = ValueKey('plugins-pick-next');
  static const installConfirm = ValueKey('plugins-install-confirm');
  static const installAnyway = ValueKey('plugins-install-anyway');
  static const cancel = ValueKey('plugins-cancel');
  static const approveUpdate = ValueKey('plugins-approve-update');
  static const testRun = ValueKey('plugins-test');
  static const remove = ValueKey('plugins-remove');
  static const removeConfirm = ValueKey('plugins-remove-confirm');
  static const toggleEnabled = ValueKey('plugins-toggle-enabled');
  static const checkUpdate = ValueKey('plugins-check-update');
  static const undoUpdate = ValueKey('plugins-undo-update');
  static const unavailableBanner = ValueKey('plugins-unavailable');
  static ValueKey<String> plugin(String engineId) => ValueKey('plugin-$engineId');
  static ValueKey<String> pick(String engineId) => ValueKey('plugin-pick-$engineId');
  static ValueKey<String> status(String engineId) => ValueKey('plugin-status-$engineId');
  static ValueKey<String> repo(String name) => ValueKey('plugins-repo-$name');
}
