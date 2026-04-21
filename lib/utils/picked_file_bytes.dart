import 'dart:typed_data';

/// Result of a single-file pick (web uses [dart:html]; IO uses [file_picker]).
class PickedFileBytes {
  const PickedFileBytes({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}
