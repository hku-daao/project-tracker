import 'dart:io';
import 'dart:typed_data';

import 'package:url_launcher/url_launcher.dart';

/// Opens [bytes] with the OS default app (temp file). VM / mobile / desktop only.
Future<bool> openAttachmentBytesInSystemViewer(
  Uint8List bytes,
  String contentType,
  String suggestedName,
) async {
  final ext = _extensionFromContentType(contentType, suggestedName);
  final base = suggestedName.trim().replaceAll(RegExp(r'[\\/]+'), '_');
  final stem = base.isEmpty
      ? 'attachment'
      : (base.length > 80 ? base.substring(0, 80) : base);
  final name =
      '${stem}_${DateTime.now().millisecondsSinceEpoch}$ext';
  final path = '${Directory.systemTemp.path}${Platform.pathSeparator}$name';
  final f = File(path);
  await f.writeAsBytes(bytes, flush: true);
  return launchUrl(Uri.file(f.path), mode: LaunchMode.externalApplication);
}

String _extensionFromContentType(String contentType, String suggestedName) {
  final fromName = suggestedName.trim();
  final dot = fromName.lastIndexOf('.');
  if (dot > 0 && dot < fromName.length - 1) {
    final e = fromName.substring(dot).toLowerCase();
    if (e.length <= 12 && RegExp(r'^\.[a-z0-9.]+$').hasMatch(e)) return e;
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
