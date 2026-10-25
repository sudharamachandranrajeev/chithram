import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import '../services.dart';
import 'app_update.dart';

/// The button's text, and the line under it.
(String, String) updateLabels(AppUpdater u) {
  final v = u.available?.version ?? '';
  return switch (u.state) {
    UpdateState.idle => ('Check for updates', ''),
    UpdateState.checking => ('Checking for updates…', ''),
    UpdateState.upToDate => ('Chithram ${u.current} is up to date', 'Check again'),
    UpdateState.available => (u.manual ? 'Chithram $v is out' : 'Update to Chithram $v', u.message),
    UpdateState.downloading => ('Downloading $v… ${(u.progress * 100).round()}%', ''),
    UpdateState.installing => ('Installing $v…', ''),
    UpdateState.restart => ('Restart to finish the update', u.message),
    UpdateState.failed => ('Check for updates', u.message),
  };
}

/// One press: update when a newer version can be installed here, otherwise
/// look for one.
void _activate(AppUpdater u) {
  if (u.busy) return;
  if (u.state == UpdateState.available && !u.manual) {
    unawaited(u.install());
  } else {
    unawaited(u.check());
  }
}

/// The Settings entry on a TV or desktop.
class UpdateSettings extends StatelessWidget {
  const UpdateSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final u = AppServices.of(context).updates;
    final d = Dims.of(context);
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final (title, detail) = updateLabels(u);
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FocusCard(
                key: const ValueKey('settings-update'),
                radius: 24,
                onActivate: () => _activate(u),
                child: ActionLabel(
                  icon: u.state == UpdateState.available ? Icons.system_update_rounded : Icons.update_rounded,
                  text: title,
                  primary: u.state == UpdateState.available && !u.manual,
                ),
              ),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: Text(
                    detail,
                    style: TextStyle(color: ChithramColors.of(context).textDim, fontSize: d.t(14)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The Settings entry on a phone.
class PhoneUpdateTile extends StatelessWidget {
  const PhoneUpdateTile({super.key});

  @override
  Widget build(BuildContext context) {
    final u = AppServices.of(context).updates;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final (title, detail) = updateLabels(u);
        return ListTile(
          key: const ValueKey('settings-update'),
          minTileHeight: 56,
          leading: Icon(u.state == UpdateState.available ? Icons.system_update_rounded : Icons.update_rounded),
          title: Text(title),
          subtitle: detail.isEmpty ? null : Text(detail),
          trailing: u.state == UpdateState.downloading
              ? SizedBox.square(dimension: 24, child: CircularProgressIndicator(value: u.progress))
              : null,
          onTap: u.busy ? null : () => _activate(u),
        );
      },
    );
  }
}

/// The automatic check, a while after start and at most once a day. A newer
/// version is announced once; Settings has the button.
Future<void> dailyUpdateCheck(AppServices services, {Duration delay = const Duration(seconds: 20)}) async {
  await Future<void>.delayed(delay);
  final prefs = services.prefs;
  final found = await services.updates.dailyCheck(
    lastChecked: prefs.getString(updateCheckedPref),
    remember: (at) => prefs.set(updateCheckedPref, at),
  );
  final context = services.navigatorKey.currentContext;
  final version = services.updates.available?.version;
  if (!found || context == null || !context.mounted || version == null) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text('Chithram $version is out. Settings has the update.')),
  );
}
