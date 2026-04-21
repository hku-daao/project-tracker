import 'package:file_picker/file_picker.dart';

import 'picked_file_bytes.dart';
import 'platform_file_bytes.dart';

Future<PickedFileBytes?> pickOneFileWithBytes() async {
  final pick = await FilePicker.pickFiles(
    withData: true,
    allowMultiple: false,
  );
  if (pick == null || pick.files.isEmpty) return null;
  final f = pick.files.single;
  final name = f.name.trim().isEmpty ? 'attachment' : f.name.trim();
  var bytes = await readPlatformFileBytes(f);
  bytes ??= f.bytes;
  if (bytes == null || bytes.isEmpty) return null;
  return PickedFileBytes(name: name, bytes: bytes);
}
