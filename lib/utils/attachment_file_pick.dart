export 'picked_file_bytes.dart';

import 'picked_file_bytes.dart';

import 'attachment_file_pick_stub.dart'
    if (dart.library.html) 'attachment_file_pick_web.dart'
    if (dart.library.io) 'attachment_file_pick_io.dart'
    as impl;

/// Single file as bytes. On **browser (HTML)** uses a native `<input type="file">` so file_picker
/// plugin registration is not required. On **VM** uses [file_picker].
Future<PickedFileBytes?> pickOneFileWithBytes() => impl.pickOneFileWithBytes();

/// Multiple files as bytes. Used by attachment uploads so users can select
/// several files in the native picker before saving.
/// [accept] is a file-input accept string, such as `image/*`.
Future<List<PickedFileBytes>> pickFilesWithBytes({
  bool allowMultiple = true,
  String accept = '*/*',
}) => impl.pickFilesWithBytes(allowMultiple: allowMultiple, accept: accept);

/// Several image files for inline images in a description or comment.
Future<List<PickedFileBytes>> pickInlineImageFiles() =>
    pickFilesWithBytes(allowMultiple: true, accept: 'image/*');
