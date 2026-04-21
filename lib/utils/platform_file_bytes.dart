import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'platform_file_bytes_stub.dart'
    if (dart.library.io) 'platform_file_bytes_io.dart' as impl;

Future<Uint8List?> readPlatformFileBytes(PlatformFile file) =>
    impl.readPlatformFileBytes(file);
