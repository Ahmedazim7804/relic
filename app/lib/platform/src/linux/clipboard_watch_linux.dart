import 'dart:io';

import 'package:flutter/services.dart';

/// Linux clipboard-change notifications, delivered by our own GTK bridge
/// (linux/runner/clipboard_watch.cc — change the two together).
///
/// Relic does NOT use the clipboard_watcher plugin on Linux: its 0.3.0 Linux
/// implementation watches GDK_SELECTION_PRIMARY, so a Ctrl+C never arrives and
/// merely selecting text would capture. Verified on Ubuntu 24.04/Xorg.
///
/// This only signals "the clipboard changed owner"; the caller reads it with
/// the same cross-platform format ladder and guards as everywhere else.
const _ch = MethodChannel('relic/clipboard_watch');

void listenLinuxClipboard(void Function() onChanged) {
  _mirrorWaylandClipboard();
  _ch.setMethodCallHandler((call) async {
    if (call.method == 'onClipboardChanged') onChanged();
    return null;
  });
}

/// Stop listening (dispose). The native side keeps its GTK signal connected —
/// it is process-lifetime — so this just drops the Dart handler.
void stopListeningLinuxClipboard() {
  _ch.setMethodCallHandler(null);
  for (final p in _mirrors) {
    p.kill();
  }
  _mirrors.clear();
}

final _mirrors = <Process>[];

void _mirrorWaylandClipboard() {
  if (_mirrors.isNotEmpty ||
      (Platform.environment['WAYLAND_DISPLAY'] ?? '').isEmpty) {
    return;
  }
  const text = r'''t=$(cat; printf x); t=${t%x}
c=$(xclip -o -selection clipboard 2>/dev/null)
[ "$t" = "$c" ] || printf %s "$t" | xclip -i -selection clipboard''';
  const png = r'''f=$(mktemp); cat >"$f"
[ -s "$f" ] && xclip -i -selection clipboard -t image/png <"$f"; rm -f "$f"''';
  for (final a in [
    ['--type', 'text', '--watch', 'sh', '-c', text],
    ['--type', 'image/png', '--watch', 'sh', '-c', png],
  ]) {
    Process.start('wl-paste', a).then(_mirrors.add, onError: (_) {});
  }
}
