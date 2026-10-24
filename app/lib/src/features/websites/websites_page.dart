import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_media/web_media.dart';

import '../../core/services.dart';
import '../../player/play_request.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/sections.dart';
import '../../ui/common/text_entry.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import 'websites_service.dart';

/// Widget keys for Websites (tests look for them).
abstract final class WebsitesKeys {
  static const add = ValueKey('websites-add');
  static ValueKey<String> site(Uri url) => ValueKey('websites-site-$url');
  static ValueKey<String> remove(Uri url) => ValueKey('websites-remove-$url');
  static ValueKey<String> media(int i) => ValueKey('websites-media-$i');
  static ValueKey<String> link(int i) => ValueKey('websites-link-$i');
}

const _promise = 'Chithram reads the page and plays its video in its own player. '
    'The site\'s ads, pop-ups and scripts never run, and ad breaks inside streams are cut out.';

/// Websites: sites the user added. Opening one shows the videos on its page
/// and the links to its other pages.
class WebsitesPage extends StatefulWidget {
  const WebsitesPage({super.key, required this.focus});

  final SectionFocus focus;

  @override
  State<WebsitesPage> createState() => _WebsitesPageState();
}

class _WebsitesPageState extends State<WebsitesPage> {
  WebsitesService? _service;
  List<SavedWebsite>? _sites;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppServices.of(context).websites;
    if (!identical(s, _service)) {
      _service?.removeListener(_reload);
      _service = s..addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    _service?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final sites = await _service!.sites();
    if (mounted) setState(() => _sites = sites);
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final sites = _sites;
    return Padding(
      padding: EdgeInsets.all(d.gutter),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Section.websites.icon, size: d.u(48), color: c.accent),
            const SizedBox(height: 16),
            Text('Websites', style: TextStyle(fontSize: d.t(32), fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_promise, style: TextStyle(color: c.textDim, fontSize: d.t(14))),
            const SizedBox(height: 24),
            if (sites == null)
              const Center(child: CircularProgressIndicator())
            else
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _Tile(
                    key: WebsitesKeys.add,
                    focusNode: widget.focus.entry,
                    section: widget.focus,
                    icon: Icons.add_rounded,
                    title: 'Add website',
                    detail: 'A link to a site or a video page',
                    onTap: () => addWebsite(context, _service!),
                  ),
                  for (final s in sites)
                    SizedBox(
                      width: d.u(300),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Tile(
                            key: WebsitesKeys.site(s.url),
                            section: widget.focus,
                            icon: Icons.public_rounded,
                            title: s.name,
                            detail: s.url.host,
                            onTap: () => openWebPage(context, s.url, title: s.name),
                          ),
                          const SizedBox(height: 8),
                          FocusCard(
                            key: WebsitesKeys.remove(s.url),
                            section: widget.focus,
                            radius: 24,
                            onActivate: () => _confirmRemove(context, s),
                            child: const ActionLabel(text: 'Remove', icon: Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, SavedWebsite s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${s.name}?'),
        content: const Text('It is removed from Websites on this device.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _service!.remove(s.url);
  }
}

/// Asks for a site's link and a name, then adds it. [url] skips the first
/// question (a shared link).
Future<void> addWebsite(BuildContext c, WebsitesService service, {String? url}) async {
  final entered = url ?? await askText(c, title: 'Website link', hint: 'https://...');
  if (entered == null || entered.trim().isEmpty || !c.mounted) return;
  final bad = websiteUrlProblem(entered);
  if (bad != null) {
    ScaffoldMessenger.maybeOf(c)?.showSnackBar(SnackBar(content: Text(bad)));
    return;
  }
  final link = Uri.parse(entered.trim());
  final name = await askText(c, title: 'Name', hint: 'My site', initial: link.host, kind: TextEntryKind.search);
  if (name == null || !c.mounted) return;
  await service.add(link, name);
}

/// Opens [url] in the Websites reader.
Future<void> openWebPage(BuildContext context, Uri url, {String? title}) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => WebPageScreen(url: url, title: title)),
    );

/// One page of a site, read without running it: the videos on it (best
/// first) and links to its other pages.
class WebPageScreen extends StatefulWidget {
  const WebPageScreen({super.key, required this.url, this.title});

  final Uri url;
  final String? title;

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  final _focus = SectionFocus();
  late final _service = AppServices.of(context).websites;
  late Future<PageScan?> _scan = _load();

  Future<PageScan?> _load() async {
    final scan = await _service.resolver.scan(widget.url);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.entry.requestFocus();
    });
    return scan;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  String _mediaLabel(MediaCandidate m, int i) {
    final quality = m.label ?? (m.height == null ? null : '${m.height}p');
    final kind = switch (m.kind) {
      MediaKind.hls || MediaKind.dash => 'Stream',
      MediaKind.file => 'Video',
    };
    return [if (i == 0) 'Play' else '$kind ${i + 1}', ?quality, m.url.host].join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        appBar: d.phone ? AppBar(title: Text(widget.title ?? widget.url.host)) : null,
        body: Overscan(
          child: FocusScope(
            child: FutureBuilder<PageScan?>(
              future: _scan,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final scan = snap.data;
                final title = scan?.title ?? widget.title ?? widget.url.host;
                final media = scan?.media ?? const <MediaCandidate>[];
                final links = scan?.links ?? const <PageLink>[];
                final note = scan == null
                    ? 'Could not open this page.'
                    : (media.isEmpty
                        ? (links.isEmpty
                            ? 'Nothing Chithram can read here. Sites that build their pages with scripts are not supported.'
                            : 'No video on this page. Pick one of its links.')
                        : null);
                return ListView(
                  padding: EdgeInsets.fromLTRB(d.gutter, 24, d.gutter, 32),
                  children: [
                    if (!d.phone)
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: d.t(28), fontWeight: FontWeight.w700)),
                    Text(widget.url.toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textDim, fontSize: d.t(13))),
                    const SizedBox(height: 16),
                    if (note != null) ...[
                      Text(note, style: TextStyle(fontSize: d.t(15))),
                      const SizedBox(height: 16),
                    ],
                    if (scan == null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FocusCard(
                          focusNode: _focus.entry,
                          section: _focus,
                          radius: 24,
                          onActivate: () => setState(() => _scan = _load()),
                          child: const ActionLabel(text: 'Retry', icon: Icons.refresh_rounded, primary: true),
                        ),
                      ),
                    if (media.isNotEmpty)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (var i = 0; i < media.length && i < 12; i++)
                            FocusCard(
                              key: WebsitesKeys.media(i),
                              focusNode: i == 0 ? _focus.entry : null,
                              section: _focus,
                              radius: 24,
                              onActivate: () => openPlayer(context, _service.playRequest(media[i], title: title)),
                              child: ActionLabel(
                                text: _mediaLabel(media[i], i),
                                icon: Icons.play_arrow_rounded,
                                primary: i == 0,
                              ),
                            ),
                        ],
                      ),
                    if (links.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('On this page', style: TextStyle(fontSize: d.t(18), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (var i = 0; i < links.length; i++)
                        _LinkRow(
                          key: WebsitesKeys.link(i),
                          link: links[i],
                          section: _focus,
                          focusNode: media.isEmpty && i == 0 ? _focus.entry : null,
                          onTap: () => openWebPage(context, links[i].url, title: links[i].text),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    required this.section,
    this.focusNode,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final SectionFocus section;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    return SizedBox(
      width: d.u(300),
      child: FocusCard(
        focusNode: focusNode,
        section: section,
        radius: 18,
        onActivate: onTap,
        child: Container(
          color: c.surfaceHigh,
          padding: EdgeInsets.all(d.u(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: c.accent, size: d.u(28)),
              const SizedBox(height: 8),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: d.t(18), fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(detail,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: d.t(13), color: c.textDim)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({super.key, required this.link, required this.section, required this.onTap, this.focusNode});

  final PageLink link;
  final SectionFocus section;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final image = link.image;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FocusCard(
        focusNode: focusNode,
        section: section,
        radius: 12,
        onActivate: onTap,
        child: Container(
          color: c.surface,
          height: d.u(64),
          padding: EdgeInsets.symmetric(horizontal: d.u(12)),
          child: Row(
            children: [
              SizedBox(
                width: d.u(80),
                height: d.u(48),
                child: image == null
                    ? Icon(Icons.link_rounded, color: c.textDim)
                    : Image.network(image.toString(),
                        cacheWidth: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(Icons.link_rounded, color: c.textDim)),
              ),
              SizedBox(width: d.u(16)),
              Expanded(
                child: Text(link.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: d.t(15))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
