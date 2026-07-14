import 'dart:async';

import 'package:flutter/material.dart';

import '../asana_landing_screen.dart';
import 'asana_filter_widgets.dart';

/// Full-screen dimmed overlay with centered loading bar (task save, file upload, etc.).
class AsanaBlockingLoadingOverlay {
  AsanaBlockingLoadingOverlay._();

  static OverlayEntry? _entry;
  static int _depth = 0;
  static DateTime? _shownAt;
  static Timer? _pendingHide;
  static const Duration _minDisplayDuration = Duration(milliseconds: 250);

  static void show(BuildContext context) {
    dismissAsanaCheckboxFilterPanels();
    _pendingHide?.cancel();
    _pendingHide = null;
    if (_entry != null) {
      _depth++;
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _depth++;
    _shownAt = DateTime.now();

    _entry = OverlayEntry(
      builder: (ctx) {
        const palette = AsanaLandingPalette.asana;
        const logoHeight = 48.0;
        final dpr = MediaQuery.devicePixelRatioOf(ctx);
        final cacheH = (logoHeight * dpr).round().clamp(1, 4096);
        return Material(
          color: palette.banner.withValues(alpha: 0.92),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      height: logoHeight,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      cacheHeight: cacheH,
                      semanticLabel: 'Project Tracker logo',
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Project\nTracker',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: palette.onBanner,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Loading',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.onBanner,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(
                      minHeight: 6,
                      backgroundColor: Color(0x66FFFFFF),
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
  }

  static Future<void> showAfterFrame(BuildContext context) async {
    show(context);
    await WidgetsBinding.instance.endOfFrame;
  }

  static void hide() {
    if (_depth <= 0) return;
    _depth--;
    if (_depth > 0) return;
    _scheduleRemoveIfReady();
  }

  static void hideAll() {
    _pendingHide?.cancel();
    _pendingHide = null;
    _shownAt = null;
    _depth = 0;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  static void _scheduleRemoveIfReady() {
    final shownAt = _shownAt;
    if (shownAt == null || _entry == null) {
      _removeNow();
      return;
    }
    final remaining = _minDisplayDuration - DateTime.now().difference(shownAt);
    if (remaining <= Duration.zero) {
      _removeNow();
      return;
    }
    _pendingHide?.cancel();
    _pendingHide = Timer(remaining, () {
      _pendingHide = null;
      if (_depth <= 0) _removeNow();
    });
  }

  static void _removeNow() {
    _pendingHide?.cancel();
    _pendingHide = null;
    _shownAt = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _depth = 0;
  }
}
