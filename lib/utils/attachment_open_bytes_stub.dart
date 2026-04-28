import 'dart:io';
import 'dart:typed_data';

import 'package:url_launcher/url_launcher.dart';

/// Opens [bytes] with the OS default app (temp file). VM / mobile / desktop only.
Future<bool> openAttachmentBytesInSystemViewer(
  Uint8List bytes,
  String contentType,
  String suggestedName,
) async {
  final fileName = _normalizeTempAttachmentFilename(suggestedName, contentType);
  final path = await _allocateUniqueTempFilePath(fileName);
  final f = File(path);
  await f.writeAsBytes(bytes, flush: true);
  return launchUrl(Uri.file(f.path), mode: LaunchMode.externalApplication);
}

String _normalizeTempAttachmentFilename(String suggestedName, String contentType) {
  var name = suggestedName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
  if (name.isEmpty) name = 'attachment';
  if (name.length > 180) name = '${name.substring(0, 177)}...';
  if (!_hasReasonableFileExtension(name)) {
    name = '$name${_inferExtensionFromContentType(contentType, name)}';
  }
  return name;
}

bool _hasReasonableFileExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot >= name.length - 1) return false;
  final ext = name.substring(dot).toLowerCase();
  return ext.length <= 14 &&
      RegExp(r'^\.[a-z0-9.]+$').hasMatch(ext);
}

Future<String> _allocateUniqueTempFilePath(String fileName) async {
  final dir = Directory.systemTemp.path;
  var path = '$dir${Platform.pathSeparator}$fileName';
  if (!await File(path).exists()) return path;
  final dot = fileName.lastIndexOf('.');
  final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
  final ext = dot > 0 ? fileName.substring(dot) : '';
  for (var i = 2; i < 10000; i++) {
    path = '$dir${Platform.pathSeparator}${stem}_$i$ext';
    if (!await File(path).exists()) return path;
  }
  path =
      '$dir${Platform.pathSeparator}${stem}_${DateTime.now().millisecondsSinceEpoch}$ext';
  return path;
}

String _inferExtensionFromContentType(String contentType, String suggestedName) {
  final fromName = suggestedName.trim();
  final dot = fromName.lastIndexOf('.');
  if (dot > 0 && dot < fromName.length - 1) {
    final e = fromName.substring(dot).toLowerCase();
    if (e.length <= 14 && RegExp(r'^\.[a-z0-9.]+$').hasMatch(e)) return e;
  }
  final ct = contentType.toLowerCase();
  if (ct.contains('pdf')) return '.pdf';
  if (ct.contains('png')) return '.png';
  if (ct.contains('jpeg') || ct.contains('jpg')) return '.jpg';
  if (ct.contains('webp')) return '.webp';
  if (ct.contains('gif')) return '.gif';
  if (ct.contains('text')) return '.txt';
  return '.bin';
}
