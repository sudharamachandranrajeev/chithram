import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../ui/common/dims.dart';
import '../../ui/common/text_entry.dart';
import '../../ui/common/tokens.dart';
import '../../ui/tv/focus_card.dart';
import '../gateway_client.dart';
import '../media_service.dart';
import 'media_widgets.dart';

/// Pair this device with the gateway: server address, the certificate
/// fingerprint to pin (printed by the gateway), and the 6-digit code from the
/// admin's terminal. Nothing is stored unless the gateway accepts the code.
class PairingView extends StatefulWidget {
  const PairingView({super.key, required this.service, this.focus});

  final MediaService service;
  final SectionFocus? focus;

  @override
  State<PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends State<PairingView> {
  late String _address;
  late String _fingerprint;
  String _code = '';
  bool _busy = false;
  String? _error;
  Timer? _cooldownTimer;
  DateTime? _blockedUntil;

  @override
  void initState() {
    super.initState();
    final cfg = widget.service.config;
    _address = cfg.host == null ? '' : cfg.host.toString();
    _fingerprint = cfg.fingerprint ?? '';
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  bool get _blocked => _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  Future<void> _pair() async {
    if (_busy || _blocked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.pair(address: _address, fingerprint: _fingerprint, code: _code);
      if (!mounted) return;
      _code = '';
      setState(() => _busy = false);
    } on GatewayException catch (e) {
      if (!mounted) return;
      if (e.kind == GatewayErrorKind.rateLimited && e.retryAfter != null) {
        _blockedUntil = DateTime.now().add(e.retryAfter!);
        _cooldownTimer?.cancel();
        _cooldownTimer = Timer(e.retryAfter!, () {
          if (mounted) setState(() {});
        });
      }
      setState(() {
        _busy = false;
        _error = e.message;
        // A code is single use: after the server saw it, a new one is needed.
        if (e.kind != GatewayErrorKind.invalidInput) _code = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = mediaErrorText(e);
        _code = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(d.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pair with your media server', style: d.type.h1),
          const SizedBox(height: Space.s8),
          Text(
            'Ask the server admin for its address, its certificate fingerprint and a 6-digit pairing code '
            '(the gateway prints them). The fingerprint is checked on every connection: this app trusts '
            'that one certificate and nothing else.',
            style: d.type.body.copyWith(color: c.textDim),
          ),
          const SizedBox(height: Space.s16),
          MediaField(
            fieldKey: const ValueKey('media-address'),
            label: 'Server address',
            hint: 'media.local or 192.168.1.20:8443',
            value: _address,
            kind: TextEntryKind.url,
            focusNode: widget.focus?.entry,
            section: widget.focus,
            onChanged: (v) => setState(() => _address = v),
          ),
          MediaField(
            fieldKey: const ValueKey('media-fingerprint'),
            label: 'Certificate fingerprint (SHA-256)',
            hint: 'AA:BB:CC:...',
            value: _fingerprint,
            kind: TextEntryKind.url,
            section: widget.focus,
            onChanged: (v) => setState(() => _fingerprint = v),
          ),
          MediaField(
            fieldKey: const ValueKey('media-code'),
            label: 'Pairing code',
            hint: '6 digits',
            value: _code,
            kind: TextEntryKind.number,
            maxLength: 6,
            autofillHidden: true,
            section: widget.focus,
            onChanged: (v) => setState(() => _code = v.trim()),
            // Enter pairs once the other two fields are filled.
            onSubmitted: (_) {
              if (_address.isNotEmpty && _fingerprint.isNotEmpty) unawaited(_pair());
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.s8),
            Semantics(
              liveRegion: true,
              child: Text(_error!, key: const ValueKey('media-pair-error'), style: d.type.body.copyWith(color: c.status.failed)),
            ),
          ],
          const SizedBox(height: Space.s12),
          MediaButton(
            key: const ValueKey('media-pair'),
            label: _busy ? 'Pairing…' : 'Pair',
            icon: Icons.link_rounded,
            primary: true,
            section: widget.focus,
            onPressed: _busy || _blocked ? null : _pair,
          ),
          const SizedBox(height: Space.s8),
          Text(
            'Plain http:// addresses are refused. The pairing code works once and expires after 10 minutes.',
            style: d.type.meta.copyWith(color: c.textDim),
          ),
        ],
      ),
    );
  }
}

/// The paired state: who and what role, where, and Unpair. Also where the
/// section is switched off.
class MediaServerView extends StatelessWidget {
  const MediaServerView({super.key, required this.service, this.focus});

  final MediaService service;
  final SectionFocus? focus;

  @override
  Widget build(BuildContext context) {
    final d = Dims.of(context);
    final c = ChithramColors.of(context);
    final cfg = service.config;
    final me = service.me;
    Widget row(String k, String v, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s4),
          child: Semantics(
            container: true,
            label: '$k: $v',
            excludeSemantics: true,
            child: Wrap(
              spacing: Space.s8,
              children: [
                Text('$k:', style: d.type.body.copyWith(color: c.textDim)),
                Text(v, key: key, style: d.type.body.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
    return SingleChildScrollView(
      padding: EdgeInsets.all(d.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This device', style: d.type.h1),
          const SizedBox(height: Space.s12),
          row('Signed in as', me?.user ?? 'unknown'),
          row('Role', me?.role.label ?? 'unknown', key: const ValueKey('media-role')),
          row('Server', cfg.host?.toString() ?? 'not set'),
          row('Pinned certificate', cfg.fingerprint ?? 'not set'),
          const SizedBox(height: Space.s16),
          Wrap(
            children: [
              MediaButton(
                key: const ValueKey('media-unpair'),
                label: 'Unpair this device',
                icon: Icons.link_off_rounded,
                section: focus,
                onPressed: () => unawaited(service.unpair()),
              ),
              MediaButton(
                key: const ValueKey('media-switch-off'),
                label: 'Switch Media off',
                icon: Icons.power_settings_new_rounded,
                section: focus,
                onPressed: () => unawaited(service.setEnabled(false)),
              ),
            ],
          ),
          const SizedBox(height: Space.s8),
          Text(
            'Unpairing forgets the token on this device. To revoke the device on the server, remove it with the gateway CLI.',
            style: d.type.meta.copyWith(color: c.textDim),
          ),
        ],
      ),
    );
  }
}
