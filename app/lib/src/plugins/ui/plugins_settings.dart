import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import '../plugin_registry.dart';
import 'plugin_flows.dart';
import 'plugin_keys.dart';

/// Settings section: one card that opens the plugin manager.
class PluginsSettings extends StatelessWidget {
  const PluginsSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final registry = AppServices.of(context).plugins;
    return ListenableBuilder(
      listenable: Listenable.merge([registry.plugins, registry.repoChanges]),
      builder: (context, _) {
        final n = registry.plugins.value.length;
        return Padding(
          padding: const EdgeInsets.all(8),
          child: FocusCard(
            radius: 24,
            onActivate: () => openPluginsPage(context),
            child: ActionLabel(text: 'Search plugins: ${n == 0 ? 'none added' : '$n installed'}'),
          ),
        );
      },
    );
  }
}

Future<void> openPluginsPage(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PluginsPage()));

/// Install, enable, update, test and remove search plugins (nova3 format).
class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  List<PluginRepoView> _repos = const [];
  PluginRegistry? _registry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = AppServices.of(context).plugins;
    if (!identical(r, _registry)) {
      _registry?.repoChanges.removeListener(_reload);
      _registry = r..repoChanges.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _registry?.repoChanges.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final r = _registry;
    if (r == null) return;
    final repos = await r.repos();
    if (mounted) setState(() => _repos = repos);
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final registry = AppServices.of(context).plugins;
    return Scaffold(
      key: PluginKeys.page,
      appBar: AppBar(title: const Text('Search plugins')),
      body: ListenableBuilder(
        listenable: registry.plugins,
        builder: (context, _) {
          final plugins = registry.plugins.value;
          return ListView(
            padding: EdgeInsets.all(d.phone ? 12 : 24),
            children: [
              Text(
                'Plugins in the qBittorrent-compatible format (nova3). Chithram ships none: you add repositories or links you trust. '
                'Each plugin runs in a sandbox and can only reach the sites you approve.',
                style: TextStyle(color: ChithramColors.of(context).textDim, fontSize: d.t(14)),
              ),
              const SizedBox(height: 12),
              if (registry.unavailableReason != null)
                Card(
                  key: PluginKeys.unavailableBanner,
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Plugins cannot run here: ${registry.unavailableReason}'),
                  ),
                ),
              Wrap(spacing: 12, runSpacing: 8, children: [
                FilledButton.icon(
                  key: PluginKeys.addRepo,
                  autofocus: true,
                  onPressed: () => addRepoFlow(context),
                  icon: const Icon(Icons.library_add_outlined),
                  label: const Text('Add repository'),
                ),
                OutlinedButton.icon(
                  key: PluginKeys.addSingle,
                  onPressed: () => addSingleFlow(context),
                  icon: const Icon(Icons.link),
                  label: const Text('Add plugin from link'),
                ),
              ]),
              const SizedBox(height: 20),
              if (_repos.isNotEmpty) ...[
                Text('Repositories', style: Theme.of(context).textTheme.titleMedium),
                for (final r in _repos) _RepoTile(repo: r),
                const SizedBox(height: 16),
              ],
              Text('Installed', style: Theme.of(context).textTheme.titleMedium),
              if (plugins.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Nothing installed yet.', style: TextStyle(color: ChithramColors.of(context).textDim)),
                ),
              for (final p in plugins) _PluginTile(plugin: p),
            ],
          );
        },
      ),
    );
  }
}

String _date(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

class _RepoTile extends StatelessWidget {
  const _RepoTile({required this.repo});
  final PluginRepoView repo;

  @override
  Widget build(BuildContext context) {
    final registry = AppServices.of(context).plugins;
    final bits = [
      'Key ${repo.keyId}',
      repo.lastCheckedAt == null ? 'not checked yet' : 'checked ${_date(repo.lastCheckedAt!)}',
      if (repo.keyChanged) 'SIGNED BY A DIFFERENT KEY - plugins blocked',
      if (repo.lastError != null && !repo.keyChanged) repo.lastError!,
    ];
    final newCount = repo.offers.where(repo.isNew).length;
    return Card(
      key: PluginKeys.repo(repo.name),
      child: ListTile(
        title: Text(repo.name),
        subtitle: Text('${Uri.tryParse(repo.url)?.host ?? repo.url}\n${bits.join(' - ')}'),
        isThreeLine: true,
        trailing: Wrap(spacing: 4, children: [
          if (repo.offers.isNotEmpty)
            TextButton(
              onPressed: () => installOffersFlow(context, repo),
              child: Text(newCount > 0 ? 'New ($newCount)' : 'Available (${repo.offers.length})'),
            ),
          IconButton(
            tooltip: 'Check now',
            icon: const Icon(Icons.refresh),
            onPressed: () => registry.checkRepo(repo.id, force: true),
          ),
          IconButton(
            tooltip: 'Remove repository',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmRemoveRepo(context, repo),
          ),
        ]),
      ),
    );
  }

  Future<void> _confirmRemoveRepo(BuildContext context, PluginRepoView repo) async {
    final registry = AppServices.of(context).plugins;
    final n = registry.plugins.value.where((p) => p.repoId == repo.id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${repo.name}?'),
        content: Text('This also removes its $n installed plugin${n == 1 ? '' : 's'} and forgets its signing key.'),
        actions: [
          TextButton(key: PluginKeys.cancel, autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(key: PluginKeys.removeConfirm, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await registry.removeRepo(repo.id);
  }
}

Color _statusColor(BuildContext context, PluginHealthStatus s) => switch (s) {
      PluginHealthStatus.healthy => const Color(0xFF3DDC84),
      PluginHealthStatus.degraded => const Color(0xFFFFC107),
      PluginHealthStatus.failing || PluginHealthStatus.blocked => const Color(0xFFFF5252),
      _ => ChithramColors.of(context).textDim,
    };

class _PluginTile extends StatelessWidget {
  const _PluginTile({required this.plugin});
  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final p = plugin;
    final lines = [
      '${p.signed ? 'Signed' : 'Unsigned'}${p.version == null ? '' : ' - v${p.version}'} - ${p.allowedHosts.join(', ')}',
      if (p.autoUpdatedAt != null) 'Updated automatically ${_date(p.autoUpdatedAt!)}',
      if (p.pending != null) 'Update needs approval',
      if (!p.enabled) 'Disabled',
    ];
    return Card(
      key: PluginKeys.plugin(p.engineId),
      child: ListTile(
        title: Text(p.name),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 1,
        trailing: Text(
          p.health.status.label,
          key: PluginKeys.status(p.engineId),
          style: TextStyle(color: _statusColor(context, p.health.status), fontWeight: FontWeight.w700),
        ),
        onTap: () => _showDetails(context, p),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context, InstalledPlugin p) {
    final registry = AppServices.of(context).plugins;
    return showDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: registry.plugins,
        builder: (ctx, _) {
          final cur = registry.plugins.value.where((x) => x.id == p.id).firstOrNull;
          if (cur == null) return const SizedBox.shrink();
          final h = cur.health;
          void close() => Navigator.of(ctx).pop();
          return SimpleDialog(
            title: Text(cur.name),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Site: ${cur.declaredUrl}'),
                  Text('Allowed: ${cur.allowedHosts.join(', ')}'),
                  Text('Status: ${h.status.label}'),
                  if (h.successRate != null) Text('Success: ${(h.successRate! * 100).round()}% of the last ${h.runs} runs'),
                  if (h.medianMs != null) Text('Median time: ${h.medianMs} ms'),
                  if (h.lastError != null) Text('Last error: ${h.lastError}'),
                  if (h.blockedHosts.isNotEmpty) Text('Blocked sites it tried: ${h.blockedHosts.join(', ')}'),
                  if (cur.autoUpdatedAt != null) Text('Updated automatically ${_date(cur.autoUpdatedAt!)}'),
                ]),
              ),
              SimpleDialogOption(
                key: PluginKeys.toggleEnabled,
                onPressed: () => registry.setEnabled(cur, !cur.enabled),
                child: Text(cur.enabled ? 'Disable' : 'Enable'),
              ),
              SimpleDialogOption(
                key: PluginKeys.testRun,
                onPressed: () {
                  close();
                  testPluginFlow(context, cur);
                },
                child: const Text('Test'),
              ),
              if (cur.pending != null)
                SimpleDialogOption(
                  key: PluginKeys.approveUpdate,
                  onPressed: () {
                    close();
                    reviewUpdateFlow(context, cur);
                  },
                  child: const Text('Update needs approval - review'),
                ),
              if (!cur.signed)
                SimpleDialogOption(
                  key: PluginKeys.checkUpdate,
                  onPressed: () {
                    close();
                    checkUnsignedFlow(context, cur);
                  },
                  child: const Text('Check for update'),
                ),
              if (cur.canUndo)
                SimpleDialogOption(
                  key: PluginKeys.undoUpdate,
                  onPressed: () async {
                    await registry.undoUpdate(cur);
                  },
                  child: const Text('Undo update'),
                ),
              SimpleDialogOption(
                key: PluginKeys.remove,
                onPressed: () async {
                  close();
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c2) => AlertDialog(
                      title: Text('Remove ${cur.name}?'),
                      actions: [
                        TextButton(key: PluginKeys.cancel, autofocus: true, onPressed: () => Navigator.of(c2).pop(false), child: const Text('Cancel')),
                        FilledButton(key: PluginKeys.removeConfirm, onPressed: () => Navigator.of(c2).pop(true), child: const Text('Remove')),
                      ],
                    ),
                  );
                  if (ok == true) await registry.removePlugin(cur);
                },
                child: const Text('Remove'),
              ),
            ],
          );
        },
      ),
    );
  }
}
