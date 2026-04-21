import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List?> readPlatformFileBytes(PlatformFile file) async =>
    file.bytes;
