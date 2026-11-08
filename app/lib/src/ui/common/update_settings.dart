// Settings > Updates: look for a newer Chithram on GitHub, then download,
// check and install it (Windows and the Linux AppImage). Where the app cannot
// install itself (Android), it names the version and where to get it.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/updater.dart';
import '../../theme.dart';
import '../tv/focus_card.dart';
import '../tv/home_page.dart' show ActionLabel;
import 'dims.dart';

/// What the button says and does, and the line under it, for [u]'s state.
({String action, String? detail, VoidCallback? run}) updateView(UpdateManager u) {
  final next = u.available?.version;
  void check() => unawaited(u.check());
  return switch (u.state) {
    UpdateState.checking => (action: 'Checking for updates…', detail: null, run: null),
    UpdateState.downloading =>
      (action: 'Downloading $next… ${(u.progress * 100).round()}%', detail: null, run: null),
    UpdateState.installing => (action: 'Installing $next…', detail: 'Chithram closes while it installs.', run: null),
    UpdateState.ready => (action: 'Updated to $next', detail: u.message, run: null),
    UpdateState.available when u.canInstall => (
        action: 'Install version $next',
        detail: 'Downloads it from GitHub, checks it, and restarts Chithram.',
        run: () => unawaited(u.downloadAndInstall()),
      ),
    UpdateState.available => (
        action: 'Version $next is out',
        detail: 'Get it from $releasePageUrl',
        run: check,
      ),
    UpdateState.upToDate => (action: 'Check for updates', detail: 'Chithram ${u.version} is the newest.', run: check),
    UpdateState.failed => (action: 'Check for updates', detail: u.message, run: check),
    UpdateState.idle => (action: 'Check for updates', detail: null, run: check),
  };
}

/// TV and desktop: a focusable button with the state below it.
class UpdateSettings extends StatelessWidget {
  const UpdateSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = AppServices.of(context).updates;
    final d = Dims.of(context);
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final v = updateView(updates);
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FocusCard(
                key: const ValueKey('settings-update'),
                radius: 24,
                onActivate: v.run ?? () {},
                child: ActionLabel(
                  text: v.action,
                  icon: Icons.system_update_alt_rounded,
                  primary: updates.state == UpdateState.available && updates.canInstall,
                ),
              ),
              if (v.detail != null && v.detail!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    v.detail!,
                    style: TextStyle(color: ChithramColors.of(context).textDim, fontSize: d.t(13)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Phone: one list tile.
class PhoneUpdateTile extends StatelessWidget {
  const PhoneUpdateTile({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = AppServices.of(context).updates;
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final v = updateView(updates);
        return ListTile(
          key: const ValueKey('settings-update'),
          minTileHeight: 56,
          leading: const Icon(Icons.system_update_alt_rounded),
          title: Text(v.action),
          subtitle: v.detail == null || v.detail!.isEmpty ? null : Text(v.detail!),
          enabled: v.run != null,
          onTap: v.run,
        );
      },
    );
  }
}
