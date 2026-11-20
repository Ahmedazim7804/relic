import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../platform/app_activation.dart';
import '../platform/input_injector.dart';
import '../theme/relic_theme.dart';
import '../theme/tokens.dart';
import '../widgets/brand.dart';
import '../widgets/controls.dart';

class DesktopOnboarding extends StatefulWidget {
  final Future<String?> Function(
    String url,
    String passphrase,
    String? enrollSecret,
  )?
  onConnectSelfHost;
  final VoidCallback onCancel;
  final VoidCallback onTryDemo;
  final bool startAtSignIn;
  final bool startReturning;
  final Future<void> Function(bool away)? onBrowserHandoff;
  final Future<void> Function(bool pinned)? onPinWindow;

  const DesktopOnboarding({
    super.key,
    this.onConnectSelfHost,
    required this.onCancel,
    required this.onTryDemo,
    this.startAtSignIn = false,
    this.startReturning = false,
    this.onBrowserHandoff,
    this.onPinWindow,
  });

  @override
  State<DesktopOnboarding> createState() => _DesktopOnboardingState();
}

bool shouldShowAccessibilityIntro({
  required bool isMacOS,
  required bool trusted,
  required bool startAtSignIn,
}) => isMacOS && !trusted && !startAtSignIn;

@visibleForTesting
DesktopStep firstDesktopStep({
  required bool startAtSignIn,
  required bool startReturning,
  required bool isMacOS,
}) {
  if (isMacOS) return DesktopStep.accessibility;
  return DesktopStep.doors;
}

@visibleForTesting
DesktopStep stepAfterAccessibility({required bool returning}) =>
    DesktopStep.doors;

@visibleForTesting
class AccessibilityGrantWatcher {
  static const interval = Duration(seconds: 1);
  static const window = Duration(minutes: 3);

  final Future<bool> Function() probe;
  final VoidCallback onGranted;

  Timer? _timer;
  int _left = 0;
  bool _probing = false;

  AccessibilityGrantWatcher({required this.probe, required this.onGranted});

  bool get watching => _timer != null;

  void start() {
    cancel();
    _left = window.inMicroseconds ~/ interval.inMicroseconds;
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_probing) return;
    _probing = true;
    final bool trusted;
    try {
      trusted = await probe();
    } finally {
      _probing = false;
    }
    if (_timer == null) return;
    if (trusted) {
      cancel();
      onGranted();
      return;
    }
    if (--_left <= 0) cancel();
  }
}

enum DesktopStep { accessibility, doors, selfHost }

class _DesktopOnboardingState extends State<DesktopOnboarding> {
  DesktopStep _step = DesktopStep.doors;
  bool _busy = false;
  String? _error;

  final _url = TextEditingController();
  final _pass = TextEditingController();
  final _secret = TextEditingController();
  bool _advanced = false;

  bool _axAsked = false;
  late final AccessibilityGrantWatcher _axWatcher;

  @override
  void initState() {
    super.initState();
    _axWatcher = AccessibilityGrantWatcher(
      probe: () => inputInjectionAvailable(prompt: false),
      onGranted: () {
        if (!mounted) return;
        unawaited(widget.onPinWindow?.call(true));
        unawaited(activateSelf());
        _go(DesktopStep.doors);
      },
    );
    if (Platform.isMacOS) {
      _step = firstDesktopStep(
        startAtSignIn: widget.startAtSignIn,
        startReturning: widget.startReturning,
        isMacOS: true,
      );
    } else {
      _step = DesktopStep.doors;
    }
  }

  @override
  void dispose() {
    _axWatcher.cancel();
    _url.dispose();
    _pass.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _go(DesktopStep s) {
    setState(() {
      _step = s;
      _error = null;
      _busy = false;
    });
  }

  Future<void> _openAccessibility() async {
    _axAsked = true;
    _axWatcher.start();
    await widget.onPinWindow?.call(false);
    await openAccessibilityPreferences();
  }

  String? _normalizedUrl() {
    var s = _url.text.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    return s.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> _connectSelfHost() async {
    final url = _normalizedUrl();
    if (url == null) {
      setState(() => _error = 'Enter your server address.');
      return;
    }
    final pass = _pass.text;
    if (pass.isEmpty) {
      setState(() => _error = 'Enter your vault passphrase.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final secret =
          _advanced && _secret.text.trim().isNotEmpty
              ? _secret.text.trim()
              : null;
      final err = await widget.onConnectSelfHost?.call(url, pass, secret);
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _busy = false;
          _error = err;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = RelicTheme.of(context);
    return Theme(
      data: materialThemeFor(c),
      child: Container(
        decoration: BoxDecoration(
          color: c.base,
          borderRadius: BorderRadius.circular(Radii.popup),
          border: Border.all(color: c.borderStrong, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Insets.xxl),
              child: _body(c),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(RelicColors c) {
    switch (_step) {
      case DesktopStep.accessibility:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
              c,
              'Let Relic paste for you',
              'macOS asks permission before any app can press keys for you. Relic uses it to paste the item you pick straight into the app you were just in, and to grab your selection when you press the save and annotate hotkey.',
            ),
            _card(
              c,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.info, size: 16, color: c.accent),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: RelicTheme.sans(
                          size: 12.5,
                          color: c.textSecondary,
                          height: 1.5,
                        ),
                        children: [
                          const TextSpan(
                            text:
                                'Skipping is fine. Relic still keeps everything '
                                'you copy, and picking an item still copies it. '
                                'You just press ',
                          ),
                          TextSpan(
                            text: '⌘V',
                            style: RelicTheme.mono(
                              size: 11.5,
                              color: c.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const TextSpan(text: ' yourself.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Insets.xl),
            _primary(
              'Open Accessibility settings',
              _busy ? null : _openAccessibility,
            ),
            _secondary(
              _axAsked ? 'Done, continue' : 'Skip for now',
              _busy
                  ? null
                  : () {
                    _axWatcher.cancel();
                    unawaited(widget.onPinWindow?.call(true));
                    _go(DesktopStep.doors);
                  },
            ),
          ],
        );

      case DesktopStep.doors:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Insets.xs),
            Center(child: RelicWordmark(markSize: 34, color: c.text)),
            const SizedBox(height: Insets.xxl),
            Text(
              'Welcome to Relic',
              textAlign: TextAlign.center,
              style: RelicTheme.headline(size: 22, color: c.text, height: 1.25),
            ),
            const SizedBox(height: Insets.sm),
            Text(
              'Encrypted clipboard vault. Use it completely offline or sync with your own server.',
              textAlign: TextAlign.center,
              style: RelicTheme.sans(
                size: 13,
                color: c.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: Insets.xxl),
            _door(
              c,
              LucideIcons.hardDrive,
              'Use offline (no sync)',
              'Keep everything you copy stored only on this computer.',
              widget.onCancel,
            ),
            _door(
              c,
              LucideIcons.server,
              'Connect your own server',
              'End-to-end encrypted sync with your self-hosted instance.',
              () => _go(DesktopStep.selfHost),
            ),
            const SizedBox(height: Insets.xs),
            Center(
              child: GhostButton(
                label: 'Just exploring? Try the demo  →',
                size: 34,
                fontSize: 12.5,
                onTap: _busy ? null : widget.onTryDemo,
              ),
            ),
            _back(widget.onCancel, label: 'Not now'),
          ],
        );

      case DesktopStep.selfHost:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
              c,
              'Your own server',
              'End-to-end encrypted. Your server only ever sees ciphertext.',
            ),
            _label(c, 'Server address'),
            _field(
              c,
              _url,
              mono: true,
              hint: 'http://192.168.1.10:8787',
              leading: LucideIcons.server,
            ),
            const SizedBox(height: Insets.lg),
            _label(c, 'Vault passphrase'),
            _field(
              c,
              _pass,
              obscure: true,
              hint: 'Your vault passphrase',
              leading: LucideIcons.keyRound,
            ),
            const SizedBox(height: Insets.md),
            GestureDetector(
              onTap: () => setState(() => _advanced = !_advanced),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  children: [
                    Icon(
                      _advanced
                          ? LucideIcons.chevronDown
                          : LucideIcons.chevronRight,
                      size: 14,
                      color: c.textMuted,
                    ),
                    const SizedBox(width: Insets.xs),
                    Text(
                      'Advanced',
                      style: RelicTheme.sans(
                        size: 12,
                        weight: FontWeight.w500,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_advanced) ...[
              const SizedBox(height: Insets.md),
              _label(c, 'Enrollment secret'),
              _field(
                c,
                _secret,
                obscure: true,
                mono: true,
                hint: 'Optional RELIC_ENROLL_SECRET',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Insets.md),
              _banner(c, _error!, danger: true),
            ],
            const SizedBox(height: Insets.xxl),
            _primary(
              _busy ? 'Connecting…' : 'Connect',
              _busy ? null : _connectSelfHost,
            ),
            _secondary('Back', _busy ? null : () => _go(DesktopStep.doors)),
          ],
        );
    }
  }

  Widget _header(RelicColors c, String title, String sub) => Column(
    children: [
      Text(
        title,
        textAlign: TextAlign.center,
        style: RelicTheme.headline(size: 22, color: c.text, height: 1.25),
      ),
      const SizedBox(height: Insets.sm),
      Text(
        sub,
        textAlign: TextAlign.center,
        style: RelicTheme.sans(size: 13, color: c.textSecondary, height: 1.5),
      ),
      const SizedBox(height: Insets.xl),
    ],
  );

  Widget _card(RelicColors c, {required Widget child}) => Container(
    padding: const EdgeInsets.all(Insets.lg),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      border: Border.all(color: c.borderStrong, width: 1),
    ),
    child: child,
  );

  Widget _door(
    RelicColors c,
    IconData icon,
    String title,
    String sub,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: Insets.md),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(Radii.card),
        hoverColor: c.hover,
        child: Container(
          padding: const EdgeInsets.all(Insets.lg),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: c.borderStrong, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(Radii.badge),
                  border: Border.all(color: c.border, width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: c.accent),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: RelicTheme.headline(size: 14, color: c.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: RelicTheme.sans(
                        size: 12,
                        color: c.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 16, color: c.textMuted),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _label(RelicColors c, String t) => Padding(
    padding: const EdgeInsets.only(bottom: Insets.sm),
    child: Text(t.toUpperCase(), style: RelicTheme.label(c.textMuted)),
  );

  Widget _field(
    RelicColors c,
    TextEditingController ctl, {
    bool mono = false,
    bool obscure = false,
    IconData? leading,
    String? hint,
  }) => Container(
    padding: const EdgeInsets.all(Insets.md),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(Radii.input),
      border: Border.all(color: c.borderStrong, width: 1),
    ),
    child: Row(
      children: [
        if (leading != null) ...[
          Icon(leading, size: 15, color: c.textMuted),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: TextField(
            controller: ctl,
            obscureText: obscure,
            style:
                mono
                    ? RelicTheme.mono(size: 13, color: c.text)
                    : RelicTheme.sans(size: 13.5, color: c.text),
            cursorColor: c.accent,
            maxLines: 1,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: hint,
              hintStyle:
                  mono
                      ? RelicTheme.mono(size: 13, color: c.textMuted)
                      : RelicTheme.sans(size: 13.5, color: c.textMuted),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _banner(RelicColors c, String msg, {bool danger = false}) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: Insets.md,
      vertical: Insets.sm,
    ),
    decoration: BoxDecoration(
      color: danger ? c.dangerBg : c.panel,
      borderRadius: BorderRadius.circular(Radii.input),
      border: Border.all(color: danger ? c.dangerBorder : c.border),
    ),
    child: Text(
      msg,
      style: RelicTheme.sans(
        size: 12,
        color: danger ? c.dangerText : c.textSecondary,
      ),
    ),
  );

  Widget _primary(String label, VoidCallback? onTap) => Padding(
    padding: const EdgeInsets.only(top: Insets.md),
    child: PrimaryButton(
      label: label,
      size: 38,
      fontSize: 13,
      bold: true,
      onTap: onTap,
    ),
  );

  Widget _secondary(String label, VoidCallback? onTap) => Padding(
    padding: const EdgeInsets.only(top: Insets.sm),
    child: GhostButton(
      label: label,
      size: 34,
      fontSize: 12.5,
      style: GhostStyle.soft,
      onTap: onTap,
    ),
  );

  Widget _back(VoidCallback? onTap, {String label = 'Back'}) => Padding(
    padding: const EdgeInsets.only(top: Insets.sm),
    child: Center(
      child: GhostButton(
        label: label,
        size: 30,
        fontSize: 12,
        onTap: onTap,
      ),
    ),
  );
}
