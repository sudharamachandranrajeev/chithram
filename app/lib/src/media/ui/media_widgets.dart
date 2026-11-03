import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/status_chip.dart';
import '../../ui/common/text_entry.dart';
import '../../ui/common/tokens.dart';
import '../../ui/tv/focus_card.dart';
import '../../ui/tv/home_page.dart' show ActionLabel;
import '../gateway_client.dart';
import '../media_service.dart';
import '../models.dart';

/// The Media service of the app above [context].
MediaService mediaOf(BuildContext context) => AppServices.of(context).media;

/// What to tell the user about [e]. Never includes a token or a body.
String mediaErrorText(Object e) {
  if (e is GatewayException) return e.message;
  return 'Something went wrong. Try again.';
}

/// A pill button that works with touch, mouse, keyboard and a D-pad.
class MediaButton extends StatelessWidget {
  const MediaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.focusNode,
    this.section,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final SectionFocus? section;

  /// Longer text for a screen reader ("Approve request for Dune").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: semanticLabel ?? label,
        excludeSemantics: true,
        onTap: onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: FocusCard(
            focusNode: focusNode,
            section: section,
            radius: 24,
            onActivate: onPressed,
            child: ActionLabel(text: label, icon: icon, primary: primary),
          ),
        ),
      ),
    );
  }
}

/// Loading, empty and error states, one shape: an icon, a line of text and an
/// optional action.
class MediaMessage extends StatelessWidget {
  const MediaMessage({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.busy = false,
    this.focusNode,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    return Padding(
      padding: EdgeInsets.all(d.gutter),
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (busy)
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
            else
              Icon(icon, size: 32, color: c.textDim),
            const SizedBox(height: Space.s12),
            Text(text, style: d.type.body.copyWith(color: c.textDim)),
            if (actionLabel != null) ...[
              const SizedBox(height: Space.s12),
              MediaButton(label: actionLabel!, onPressed: onAction, focusNode: focusNode),
            ],
          ],
        ),
      ),
    );
  }
}

/// A request status as label plus shape (icon): never colour alone. Uses the
/// shared [StatusChip]; "Approved" has no chip there, so it is drawn here.
class MediaStatusChip extends StatelessWidget {
  const MediaStatusChip(this.status, {super.key, this.progress});

  final MediaStatus status;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final chip = status.chip;
    if (status == MediaStatus.none) return const SizedBox.shrink();
    if (chip != null) {
      return Semantics(
        label: 'Status: ${status.label}',
        excludeSemantics: true,
        child: StatusChip(chip, progress: progress),
      );
    }
    // Approved.
    final d = Dims.of(context);
    final colors = ChithramColors.of(context);
    final color = colors.status.searching;
    final height = switch (d.form) {
      FormFactor.desktop => 24.0,
      FormFactor.phone => 28.0,
      FormFactor.tv => 36.0,
    };
    return Semantics(
      label: 'Status: ${status.label}',
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        padding: EdgeInsets.symmetric(horizontal: d.tv ? Space.s12 : Space.s8, vertical: 2),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: 0.16), colors.surface),
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.thumb_up_alt_rounded, size: height * 0.58, color: color),
            const SizedBox(width: Space.s4),
            Flexible(child: Text(status.label, style: d.type.meta.copyWith(color: color, height: 1.1))),
          ],
        ),
      ),
    );
  }
}

/// A text input that suits the form factor: a real [TextField] on phone and
/// desktop; on a TV a focusable row that opens the on-screen keyboard
/// ([askText], number pad for [TextEntryKind.number]).
class MediaField extends StatefulWidget {
  const MediaField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onSubmitted,
    this.kind = TextEntryKind.url,
    this.hint,
    this.focusNode,
    this.section,
    this.fieldKey,
    this.maxLength,
    this.autofillHidden = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEntryKind kind;
  final String? hint;
  final FocusNode? focusNode;
  final SectionFocus? section;
  final Key? fieldKey;
  final int? maxLength;

  /// Hide what is typed (pairing code).
  final bool autofillHidden;

  @override
  State<MediaField> createState() => _MediaFieldState();
}

class _MediaFieldState extends State<MediaField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(MediaField old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final v = await askText(
      context,
      title: widget.label,
      hint: widget.hint,
      initial: widget.value,
      kind: widget.kind,
    );
    if (v == null || !mounted) return;
    widget.onChanged(v);
    widget.onSubmitted?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    if (d.tv) {
      final shown = widget.value.isEmpty
          ? (widget.hint ?? 'Select to type')
          : (widget.autofillHidden ? '•' * widget.value.length : widget.value);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s4),
        child: Semantics(
          textField: true,
          label: widget.label,
          value: widget.autofillHidden ? '' : widget.value,
          excludeSemantics: true,
          onTap: _ask,
          child: FocusCard(
            key: widget.fieldKey,
            focusNode: widget.focusNode,
            section: widget.section,
            radius: Radii.button,
            onActivate: _ask,
            child: Container(
              color: c.surfaceHigh,
              padding: const EdgeInsets.symmetric(horizontal: Space.s16, vertical: Space.s12),
              child: Row(
                children: [
                  Icon(Icons.keyboard_rounded, color: c.textDim, size: 22),
                  const SizedBox(width: Space.s12),
                  Expanded(
                    child: Text(
                      '${widget.label}: $shown',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: d.type.card.copyWith(color: widget.value.isEmpty ? c.textDim : c.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s4),
      child: TextField(
        key: widget.fieldKey,
        controller: _c,
        focusNode: widget.focusNode,
        maxLength: widget.maxLength,
        obscureText: widget.autofillHidden,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: switch (widget.kind) {
          TextEntryKind.number || TextEntryKind.pin => TextInputType.number,
          TextEntryKind.search => TextInputType.text,
          _ => TextInputType.url,
        },
        textInputAction: widget.onSubmitted == null ? TextInputAction.next : TextInputAction.done,
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint, counterText: ''),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

/// A gateway image fetched with the token header (never a URL parameter).
/// A placeholder shows while loading, when there is no image, and on error.
class MediaImage extends StatefulWidget {
  const MediaImage({super.key, required this.path, required this.label, this.aspect = 2 / 3});

  final String? path;

  /// What the picture is, for a screen reader.
  final String label;
  final double aspect;

  @override
  State<MediaImage> createState() => _MediaImageState();
}

class _MediaImageState extends State<MediaImage> {
  Future<dynamic>? _future;
  String? _for;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = widget.path;
    if (p != _for) {
      _for = p;
      _future = validImagePath(p) ? mediaOf(context).image(p!).then<dynamic>((b) => b, onError: (_) => null) : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ChithramColors.of(context);
    Widget placeholder([IconData icon = Icons.movie_outlined]) =>
        ColoredBox(color: c.surfaceHigh, child: Center(child: Icon(icon, color: c.textDim, size: 32)));
    final f = _future;
    return Semantics(
      image: true,
      label: widget.label,
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: widget.aspect,
        child: f == null
            ? placeholder()
            : FutureBuilder<dynamic>(
                future: f,
                builder: (context, snap) {
                  final data = snap.data;
                  if (snap.connectionState != ConnectionState.done) return placeholder(Icons.hourglass_empty_rounded);
                  if (data == null) return placeholder(Icons.broken_image_outlined);
                  return Image.memory(
                    data,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => placeholder(Icons.broken_image_outlined),
                  );
                },
              ),
      ),
    );
  }
}

/// Runs [load] and shows loading / error / data. Pass [reload] to run it again.
class AsyncBody<T> extends StatefulWidget {
  const AsyncBody({
    super.key,
    required this.load,
    required this.builder,
    this.emptyText,
    this.isEmpty,
    this.entry,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final String? emptyText;
  final bool Function(T data)? isEmpty;
  final FocusNode? entry;

  @override
  State<AsyncBody<T>> createState() => _AsyncBodyState<T>();
}

class _AsyncBodyState<T> extends State<AsyncBody<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final gen = ++_gen;
    if (mounted) setState(() => _loading = true);
    try {
      final v = await widget.load();
      if (!mounted || gen != _gen) return;
      setState(() {
        _data = v;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const MediaMessage(icon: Icons.hourglass_empty_rounded, text: 'Loading…', busy: true);
    }
    if (_error != null && _data == null) {
      return MediaMessage(
        icon: Icons.error_outline_rounded,
        text: mediaErrorText(_error!),
        actionLabel: 'Try again',
        onAction: _run,
        focusNode: widget.entry,
      );
    }
    final data = _data as T;
    if (widget.isEmpty?.call(data) ?? false) {
      return MediaMessage(
        icon: Icons.inbox_outlined,
        text: widget.emptyText ?? 'Nothing here yet.',
        actionLabel: 'Refresh',
        onAction: _run,
        focusNode: widget.entry,
      );
    }
    return widget.builder(context, data, _run);
  }
}
