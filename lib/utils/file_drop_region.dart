import 'package:flutter/material.dart';

import 'file_drop_binding_stub.dart'
    if (dart.library.html) 'file_drop_binding_web.dart'
    as binding;
import 'picked_file_bytes.dart';

/// Highlights [child] while image or file drops are over it.
class AsanaFileDropRegion extends StatefulWidget {
  const AsanaFileDropRegion({
    super.key,
    required this.child,
    required this.enabled,
    required this.onFiles,
    this.imagesOnly = false,
  });

  final Widget child;
  final bool enabled;
  final void Function(List<PickedFileBytes> files, int rejectedNonImages)
  onFiles;
  final bool imagesOnly;

  @override
  State<AsanaFileDropRegion> createState() => _AsanaFileDropRegionState();
}

class _AsanaFileDropRegionState extends State<AsanaFileDropRegion> {
  final _key = GlobalKey();
  binding.FileDropBindingHandle? _handle;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _handle = binding.bindFileDrop(
      enabled: () => widget.enabled,
      imagesOnly: widget.imagesOnly,
      contains: _contains,
      onHover: (hovering) {
        if (!mounted || _hovering == hovering) return;
        setState(() => _hovering = hovering);
      },
      onDrop: (files, rejected) {
        if (!mounted || !widget.enabled) return;
        widget.onFiles(files, rejected);
      },
    );
  }

  @override
  void dispose() {
    _handle?.dispose();
    super.dispose();
  }

  bool _contains(Offset globalPoint) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return rect.contains(globalPoint);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _key,
      children: [
        widget.child,
        if (_hovering && widget.enabled)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x1A1565C0),
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0xFF1565C0), width: 2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Compact target shown beside the file add button.
class AsanaFileDropSlot extends StatelessWidget {
  const AsanaFileDropSlot({
    super.key,
    required this.enabled,
    required this.onFiles,
  });

  final bool enabled;
  final void Function(List<PickedFileBytes> files) onFiles;

  @override
  Widget build(BuildContext context) {
    return AsanaFileDropRegion(
      enabled: enabled,
      onFiles: (files, _) => onFiles(files),
      child: Container(
        constraints: const BoxConstraints(minWidth: 128, minHeight: 32),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFF7F5F4) : const Color(0xFFF3F1F0),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFD0CBC8)),
        ),
        child: Text(
          'Drop files here',
          style: TextStyle(
            fontSize: 12,
            color: enabled
                ? const Color(0xFF6D6E6F)
                : const Color(0xFFB0A9A6),
          ),
        ),
      ),
    );
  }
}

Widget asanaAttachmentValuesWithFileDrop({
  required bool enabled,
  required void Function(List<PickedFileBytes> files)? onDropFiles,
  required Widget child,
}) {
  if (onDropFiles == null) return child;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AsanaFileDropSlot(enabled: enabled, onFiles: onDropFiles),
      ),
      child,
    ],
  );
}
