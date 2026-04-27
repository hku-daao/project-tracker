import 'dart:typed_data';

import 'attachment_open_bytes_stub.dart'
    if (dart.library.html) 'attachment_open_bytes_web.dart' as impl;

/// Opens downloaded attachment bytes in the system viewer / new tab.
Future<bool> openAttachmentBytesInSystemViewer(
  Uint8List bytes,
  String contentType,
  String suggestedName,
) =>
    impl.openAttachmentBytesInSystemViewer(bytes, contentType, suggestedName);
