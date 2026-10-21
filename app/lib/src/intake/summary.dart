import 'package:flutter/material.dart';

import '../core/redact.dart';

const _maxShown = 200;

/// What a piece of text looks like in a prompt: credentials masked, cut to
/// 200 characters, and for a link the host in bold so a look-alike path cannot
/// pass for the real site.
class IntakeSummary extends StatelessWidget {
  const IntakeSummary(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(TextSpan(style: base, children: intakeSpans(text, base)));
  }
}

/// The spans behind [IntakeSummary]; separate so tests can read them.
List<InlineSpan> intakeSpans(String text, TextStyle base) {
  final shown = maskUrlCredentials(text.trim());
  final cut = shown.length > _maxShown ? '${shown.substring(0, _maxShown)}...' : shown;
  final uri = Uri.tryParse(shown);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
    final hostAt = cut.toLowerCase().indexOf(uri.host.toLowerCase());
    if (hostAt >= 0 && hostAt + uri.host.length <= cut.length) {
      return [
        TextSpan(text: cut.substring(0, hostAt)),
        TextSpan(
          text: cut.substring(hostAt, hostAt + uri.host.length),
          style: base.copyWith(fontWeight: FontWeight.w800),
        ),
        TextSpan(text: cut.substring(hostAt + uri.host.length)),
      ];
    }
  }
  return [TextSpan(text: cut)];
}
