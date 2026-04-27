// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Opens [bytes] in a new tab via a same-origin [blob:] URL (no Railway / Firebase URL in the bar).
Future<bool> openAttachmentBytesInSystemViewer(
  Uint8List bytes,
  String contentType,
  // ignore: avoid_unused_parameters
  String suggestedName,
) async {
  final blob = html.Blob([bytes], contentType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank', 'noopener,noreferrer');
  Timer(const Duration(minutes: 2), () => html.Url.revokeObjectUrl(url));
  return true;
}
