import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/api.dart';
import '../data/recovery.dart';
import '../data/selfhost_link.dart';
import '../data/worker_repo.dart';
import '../theme/relic_theme.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import 'add_device.dart';

class OnboardingFlow extends StatefulWidget {
  final String defaultDeviceName;
  final bool autoVault;
  final void Function(WorkerRepo repo) onConnected;
  final bool startAtSignIn;
  final VoidCallback? onBrowseOnly;
  final bool startReturning;
  final Object? pairingLink;

  const OnboardingFlow({
    super.key,
    required this.onConnected,
    this.defaultDeviceName = 'Phone',
    this.autoVault = true,
    this.startAtSignIn = false,
    this.startReturning = false,
    this.pairingLink,
    this.onBrowseOnly,
  });

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum MobileStep {
  doors,
  selfHost,
  selfHostScan,
  recoveryKit,
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  MobileStep _step = MobileStep.doors;
  bool _busy = false;
  String? _error;
  String _deviceName = '';

  WorkerRepo? _pendingRepo;
  bool _kitDownloaded = false;

  final _shUrl = TextEditingController();
  final _shPass = TextEditingController();
  final _shSecret = TextEditingController();
  bool _shAdvanced = false;
  bool _shScanned = false;

  @override
  void initState() {
    super.initState();
    _deviceName = widget.defaultDeviceName;
    if (widget.startAtSignIn) {
      _step = MobileStep.selfHost;
    }
  }

  @override
  void dispose() {
    _shUrl.dispose();
    _shPass.dispose();
    _shSecret.dispose();
    super.dispose();
  }

  void _go(MobileStep s) => setState(() {
        _error = null;
        _step = s;
      });

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } catch (e) {
      setState(() => _error = _human(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _human(Object e) {
    if (e is RecoveryKitException) {
      return e.kind == RecoveryKitError.format
          ? "That doesn't look like a Relic recovery kit."
          : 'That recovery kit looks mistyped. Check it and try again.';
    }
    final s = e.toString().replaceFirst('StateError: ', '').replaceFirst('Exception: ', '');
    return s.isEmpty ? 'Something went wrong.' : s;
  }

  void _enterRecoveryKit(WorkerRepo repo) {
    _pendingRepo = repo;
    _kitDownloaded = false;
    _go(MobileStep.recoveryKit);
  }

  Future<void> _downloadKit(String kit) async {
    try {
      final saved = await downloadRecoveryKit(kit);
      if (mounted) {
        setState(() => _kitDownloaded = _kitDownloaded || saved);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(saved ? 'Recovery kit saved' : 'Not saved yet')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save the recovery kit')));
      }
    }
  }

  Future<void> _connectSelfHost() async {
    var url = _shUrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Enter your server address.');
      return;
    }
    if (!url.contains('://')) url = 'http://$url';
    if (_shPass.text.isEmpty) {
      setState(() => _error = 'Enter your passphrase.');
      return;
    }
    await _run(() async {
      final repo = await WorkerRepo.connectSelfHost(
        baseUrl: url,
        passphrase: _shPass.text,
        enrollSecret:
            _shAdvanced && _shSecret.text.trim().isNotEmpty ? _shSecret.text.trim() : null,
        deviceLabel: _deviceName,
        autoVault: widget.autoVault,
        deviceId: await DeviceId.get(),
      );
      if (repo.vaultJustCreated) {
        _enterRecoveryKit(repo);
      } else {
        widget.onConnected(repo);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = RelicTheme.of(context);
    return Theme(
      data: materialThemeFor(c),
      child: Scaffold(
        backgroundColor: c.base,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: Motion.panel,
            child: _body(c),
          ),
        ),
      ),
    );
  }

  Widget _body(RelicColors c) {
    switch (_step) {
      case MobileStep.doors:
        return _doors(c);
      case MobileStep.selfHost:
        return _selfHostForm(c);
      case MobileStep.selfHostScan:
        return _selfHostScanView(c);
      case MobileStep.recoveryKit:
        return _recoveryKitView(c);
    }
  }

  Widget _scroll(List<Widget> children, {Key? key}) => SingleChildScrollView(
        key: key,
        padding: const EdgeInsets.fromLTRB(
            Insets.xxl, Insets.xxxl, Insets.xxl, Insets.xxxl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _doors(RelicColors c) => _scroll(key: const ValueKey('doors'), [
        const SizedBox(height: Insets.xxxl),
        Center(child: RelicWordmark(markSize: 40, color: c.text)),
        const SizedBox(height: Insets.xxxl),
        Text('Connect to your server',
            textAlign: TextAlign.center,
            style: RelicTheme.headline(size: 26, color: c.text, height: 1.2)),
        const SizedBox(height: Insets.md),
        Text(
            'Sync your clipboard end-to-end encrypted with your own Relic server.',
            textAlign: TextAlign.center,
            style: RelicTheme.sans(size: 14, color: c.textSecondary, height: 1.5)),
        const SizedBox(height: Insets.section),
        _doorTile(
            c,
            Icons.dns_outlined,
            'Connect your server',
            'Enter your server address and vault passphrase.',
            () => _go(MobileStep.selfHost)),
        _doorTile(
            c,
            Icons.qr_code_scanner,
            'Scan server QR',
            'Scan the QR code shown under Settings on another device.',
            () => _go(MobileStep.selfHostScan)),
        if (widget.onBrowseOnly != null)
          _quietBtn(c, 'Use offline (no sync)', _busy ? null : widget.onBrowseOnly),
      ]);

  Widget _selfHostForm(RelicColors c) => _scroll(key: const ValueKey('selfhost'), [
        _header(c, 'Your own server',
            'Sync through a server you run. End-to-end encrypted — it only ever sees ciphertext.'),
        _field(c, _shUrl, 'http://192.168.1.10:8787',
            keyboard: TextInputType.url, mono: true),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy
                ? null
                : () {
                    _shScanned = false;
                    _go(MobileStep.selfHostScan);
                  },
            style: TextButton.styleFrom(
                foregroundColor: c.accentDeep,
                backgroundColor: c.tagBg,
                disabledForegroundColor: c.textFaintest,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.pill)),
                padding: const EdgeInsets.symmetric(horizontal: Insets.lg)),
            icon: const Icon(Icons.qr_code_scanner, size: 17),
            label: Text('Scan QR from another device',
                style: RelicTheme.sans(size: 13, weight: FontWeight.w500)),
          ),
        ),
        const SizedBox(height: Insets.md),
        _field(c, _shPass, 'Vault passphrase', obscure: true, mono: true),
        Padding(
          padding: const EdgeInsets.only(bottom: Insets.md, left: Insets.xs),
          child: Text('Same passphrase on every device.',
              style: RelicTheme.sans(size: 12, color: c.textMuted)),
        ),
        GestureDetector(
          onTap: () => setState(() => _shAdvanced = !_shAdvanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.sm),
            child: Row(children: [
              Icon(_shAdvanced ? Icons.expand_more : Icons.chevron_right,
                  size: 18, color: c.textMuted),
              const SizedBox(width: Insets.xs),
              Text('Advanced',
                  style: RelicTheme.sans(
                      size: 13, weight: FontWeight.w600, color: c.textSecondary)),
            ]),
          ),
        ),
        if (_shAdvanced) ...[
          const SizedBox(height: Insets.sm),
          _field(c, _shSecret, 'Enrollment secret', obscure: true, mono: true),
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm, left: Insets.xs),
            child: Text('Only if your server sets RELIC_ENROLL_SECRET.',
                style: RelicTheme.sans(size: 12, color: c.textMuted)),
          ),
        ],
        if (_error != null) _errorText(c, _error!),
        const SizedBox(height: Insets.lg),
        _primaryBtn(c, 'Connect', _busy ? null : _connectSelfHost),
        _backBtn(c, () => _go(MobileStep.doors)),
      ]);

  Widget _selfHostScanView(RelicColors c) =>
      Column(key: const ValueKey('selfhostscan'), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Insets.xxl, Insets.xxl, Insets.xxl, Insets.sm),
          child: _header(c, 'Scan the QR',
              'On the connected device: Settings → Add a device → Show QR, then point this camera at it.'),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.xxl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.cardLarge),
              child: MobileScanner(onDetect: (capture) {
                if (_shScanned) return;
                final raw = capture.barcodes
                    .map((b) => b.rawValue)
                    .firstWhere(
                        (v) => v != null && v.startsWith(SelfHostLink.prefix),
                        orElse: () => null);
                if (raw == null) return;
                final parsed = SelfHostLink.parse(raw);
                if (parsed == null) return;
                _shScanned = true;
                _shUrl.text = parsed.url;
                if (parsed.secret != null) {
                  _shSecret.text = parsed.secret!;
                  _shAdvanced = true;
                }
                _go(MobileStep.selfHost);
              }),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Insets.xxl, Insets.md, Insets.xxl, Insets.xxl),
          child: _backBtn(c, () {
            _shScanned = false;
            _go(MobileStep.selfHost);
          }),
        ),
      ]);

  Widget _recoveryKitView(RelicColors c) {
    final repo = _pendingRepo!;
    final kit = RecoveryKit.fromMk(repo.masterKey!, repo.accountEmail ?? '');
    return _scroll(key: const ValueKey('kit'), [
      _header(c, 'Save your recovery kit',
          'The only way back into your data if you forget your vault passphrase. We cannot recover it for you.'),
      Container(
        padding: const EdgeInsets.all(Insets.xl),
        decoration: BoxDecoration(
            color: c.tagBg,
            borderRadius: BorderRadius.circular(Radii.card)),
        child: SelectableText(kit,
            style: RelicTheme.mono(size: 13, color: c.tagText, height: 1.8)),
      ),
      const SizedBox(height: Insets.md),
      Row(children: [
        Expanded(
          child: _secondaryBtn(c, 'Copy', () {
            Clipboard.setData(ClipboardData(text: kit));
            setState(() => _kitDownloaded = true);
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Recovery kit copied')));
          }),
        ),
        const SizedBox(width: Insets.md),
        Expanded(child: _secondaryBtn(c, 'Download', () => _downloadKit(kit))),
      ]),
      if (!_kitDownloaded) ...[
        const SizedBox(height: Insets.md),
        Text('Copy or download the kit to continue.',
            style: RelicTheme.sans(size: 12.5, color: c.textMuted, height: 1.45)),
      ],
      const SizedBox(height: Insets.lg),
      _primaryBtn(c, 'Continue', _kitDownloaded ? () => widget.onConnected(repo) : null),
    ]);
  }

  Widget _header(RelicColors c, String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: Insets.xxl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: RelicTheme.headline(size: 26, color: c.text)),
          const SizedBox(height: Insets.md),
          Text(sub, style: RelicTheme.sans(size: 14, color: c.textMuted, height: 1.5)),
        ]),
      );

  Widget _field(RelicColors c, TextEditingController ctrl, String hint,
      {bool obscure = false,
      TextInputType? keyboard,
      int maxLines = 1,
      bool mono = false,
      ValueChanged<String>? onChanged}) {
    final style = mono
        ? RelicTheme.mono(size: 14, color: c.text)
        : RelicTheme.sans(size: 15, color: c.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        maxLines: obscure ? 1 : maxLines,
        onChanged: onChanged,
        style: style,
        cursorColor: c.accent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: style.copyWith(color: c.textFaintest),
          filled: true,
          fillColor: c.surface,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: Insets.lg, vertical: Insets.lg),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.input),
              borderSide: BorderSide(color: c.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.input),
              borderSide: BorderSide(color: c.accent, width: 1.5)),
        ),
      ),
    );
  }

  Widget _primaryBtn(RelicColors c, String label, VoidCallback? onTap) {
    final on = onTap != null;
    final shape = BorderRadius.circular(Radii.pill);
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: on ? Gradients.gold : null,
        color: on ? null : c.track,
        borderRadius: shape,
        boxShadow: on ? Shadows.gold : null,
      ),
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: c.onAccent,
          disabledForegroundColor: c.textFaintest,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: shape),
        ),
        child: _busy && on
            ? SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent))
            : Text(label, style: RelicTheme.sans(size: 15, weight: FontWeight.w600)),
      ),
    );
  }

  Widget _secondaryBtn(RelicColors c, String label, VoidCallback? onTap) => SizedBox(
        height: 52,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: c.text,
            disabledForegroundColor: c.textFaintest,
            backgroundColor: c.panel,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.pill)),
          ),
          child: Text(label, style: RelicTheme.sans(size: 15, weight: FontWeight.w600)),
        ),
      );

  Widget _quietBtn(RelicColors c, String label, VoidCallback? onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: c.textMuted,
          disabledForegroundColor: c.textFaintest,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.pill)),
        ),
        child: Text(label, style: RelicTheme.sans(size: 13.5, weight: FontWeight.w500)),
      );

  Widget _doorTile(RelicColors c, IconData icon, String title, String sub,
          VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Insets.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            boxShadow: Shadows.card(c),
          ),
          child: Material(
            color: c.panel,
            borderRadius: BorderRadius.circular(Radii.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.card),
              onTap: _busy ? null : onTap,
              child: Container(
                padding: const EdgeInsets.all(Insets.lg),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.card),
                    border: Border.all(color: c.border)),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c.selectedTile,
                      borderRadius: BorderRadius.circular(Radii.tile),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 19, color: c.accent),
                  ),
                  const SizedBox(width: Insets.lg),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          style: RelicTheme.sans(
                              size: 14, weight: FontWeight.w600, color: c.text)),
                      const SizedBox(height: Insets.xs),
                      Text(sub, style: RelicTheme.sans(size: 12, color: c.textMuted)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: c.textFaintest),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _backBtn(RelicColors c, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: Insets.sm),
        child: _quietBtn(c, 'Back', _busy ? null : onTap),
      );

  Widget _errorText(RelicColors c, String e) => Padding(
        padding: const EdgeInsets.only(top: Insets.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg, vertical: Insets.md),
          decoration: BoxDecoration(
            color: c.dangerBg,
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Text(e,
              style: RelicTheme.sans(size: 13, color: c.dangerText, height: 1.5)),
        ),
      );
}
