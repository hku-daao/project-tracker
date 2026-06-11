import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'picked_file_bytes.dart';
import 'platform_file_bytes.dart';

Future<Uint8List?> _collectReadStream(Stream<List<int>> stream) async {
  final b = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    b.add(chunk);
  }
  return b.takeBytes();
}

/// Picks one file for upload. Uses `withData: false` so the OS shows the native
/// picker and returns a cache path (recommended for iOS/Android; `withData: true`
/// can prevent the picker or fail on iCloud/large files). Bytes are read from
/// [PlatformFile.path], then [PlatformFile.bytes], then [PlatformFile.readStream].
Future<PickedFileBytes?> pickOneFileWithBytes() async {
  final files = await pickFilesWithBytes(allowMultiple: false);
  return files.isEmpty ? null : files.first;
}

Future<List<PickedFileBytes>> pickFilesWithBytes({
  bool allowMultiple = true,
}) async {
  final pick = await FilePicker.pickFiles(
    type: FileType.any,
    allowMultiple: allowMultiple,
    withData: false,
    compressionQuality: 0,
  );
  if (pick == null || pick.files.isEmpty) return const [];
  final out = <PickedFileBytes>[];
  for (final f in pick.files) {
    final picked = await _readPickedFile(f);
    if (picked != null) out.add(picked);
  }
  return out;
}

Future<PickedFileBytes?> _readPickedFile(PlatformFile f) async {
  final name = f.name.trim().isEmpty ? 'attachment' : f.name.trim();
  var bytes = await readPlatformFileBytes(f);
  bytes ??= f.bytes;
  if ((bytes == null || bytes.isEmpty) && f.readStream != null) {
    bytes = await _collectReadStream(f.readStream!);
  }
  if (bytes == null) return null;
  return PickedFileBytes(name: name, bytes: bytes);
}
