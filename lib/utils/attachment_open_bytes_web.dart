// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Opens [bytes] via a programmatic download so the browser uses [suggestedName]
/// (not a Firebase URL or storage object id).
Future<bool> openAttachmentBytesInSystemViewer(
  Uint8List bytes,
  String contentType,
  String suggestedName,
) async {
  final safeName = _sanitizeDownloadFileName(suggestedName, contentType);
  final blob = html.Blob([bytes], contentType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = safeName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(minutes: 2), () => html.Url.revokeObjectUrl(url));
  return true;
}

String _sanitizeDownloadFileName(String suggestedName, String contentType) {
  var name = suggestedName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
  if (name.isEmpty) name = 'attachment';
  if (name.length > 180) name = '${name.substring(0, 177)}...';
  if (!_hasReasonableExtension(name)) {
    name = '$name${_inferExtension(contentType)}';
  }
  return name;
}

bool _hasReasonableExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot >= name.length - 1) return false;
  final ext = name.substring(dot).toLowerCase();
  return ext.length <= 14 &&
      RegExp(r'^\.[a-z0-9.]+$').hasMatch(ext);
}

String _inferExtension(String contentType) {
  final ct = contentType.toLowerCase();
  if (ct.contains('pdf')) return '.pdf';
  if (ct.contains('png')) return '.png';
  if (ct.contains('jpeg') || ct.contains('jpg')) return '.jpg';
  if (ct.contains('webp')) return '.webp';
  if (ct.contains('gif')) return '.gif';
  if (ct.contains('text')) return '.txt';
  return '.bin';
}
