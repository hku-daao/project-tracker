import 'picked_file_bytes.dart';

Future<PickedFileBytes?> pickOneFileWithBytes() async {
  throw UnsupportedError(
    'File picking is not supported on this platform build.',
  );
}

Future<List<PickedFileBytes>> pickFilesWithBytes({
  bool allowMultiple = true,
}) async {
  throw UnsupportedError(
    'File picking is not supported on this platform build.',
  );
}
