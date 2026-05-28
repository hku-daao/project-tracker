import 'package:flutter/material.dart';

/// Full-screen dimmed overlay with centered loading bar (task save, file upload, etc.).
class AsanaBlockingLoadingOverlay {
  AsanaBlockingLoadingOverlay._();

  static OverlayEntry? _entry;
  static int _depth = 0;

  static void show(BuildContext context) {
    _depth++;
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (ctx) => Material(
        color: const Color(0x80000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Loading',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
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
      ),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    if (_depth <= 0) return;
    _depth--;
    if (_depth > 0) return;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _depth = 0;
  }

  static void hideAll() {
    _depth = 0;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}
