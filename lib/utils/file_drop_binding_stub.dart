import 'dart:ui';

import 'file_drop_binding.dart';
import 'picked_file_bytes.dart';

export 'file_drop_binding.dart';

class _NoopFileDropBinding implements FileDropBindingHandle {
  @override
  void dispose() {}
}

FileDropBindingHandle bindFileDrop({
  required bool Function() enabled,
  required bool imagesOnly,
  required bool Function(Offset globalPoint) contains,
  required void Function(bool hovering) onHover,
  required void Function(List<PickedFileBytes> files, int rejectedNonImages)
  onDrop,
}) {
  return _NoopFileDropBinding();
}
