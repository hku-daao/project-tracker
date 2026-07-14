import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import 'attachment_open_bytes.dart';
import 'copyable_snackbar.dart';

/// Path after `/api/files/` when [raw] is a local backend file URL.
String? localAttachmentRelativePath(String raw) {
  const marker = '/api/files/';
  final idx = raw.indexOf(marker);
  if (idx < 0) return null;
  try {
    return Uri.decodeComponent(
      raw.substring(idx + marker.length).split('?').first,
    );
  } catch (_) {
    return null;
  }
}

/// True when [raw] looks like a legacy Firebase Storage download URL.
bool isLegacyFirebaseStorageUrl(String raw) {
  final t = raw.trim().toLowerCase();
  return t.contains('firebasestorage.googleapis.com') ||
      t.contains('storage.googleapis.com');
}

/// Use the current [ApiConfig.baseUrl] for `/api/files/…` links so images load
/// after deploy even when the DB still has localhost / Railway URLs.
String resolveAttachmentFetchUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final rel = localAttachmentRelativePath(trimmed);
  if (rel != null && rel.isNotEmpty) {
    final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/api/files/$rel';
  }
  return trimmed;
}

/// True when [raw] points at a local uploaded file (`/api/files/...`).
bool isLocalAttachmentUrl(String raw) {
  return raw.trim().contains('/api/files/');
}

/// Uploaded file attachment (local backend), not a user-pasted website link.
bool isUploadedFileAttachmentUrl(String raw) => isLocalAttachmentUrl(raw);

bool attachmentTextIsJsonNotAUrl(String s) => _looksLikeJsonNotAUrl(s);

bool _looksLikeJsonNotAUrl(String s) {
  final t = s.trim();
  if (!t.startsWith('{')) return false;
  if (t.contains('"contentType"')) return true;
  if (t.contains('"metadata"') && t.contains('"m0"')) return true;
  return false;
}

bool _looksLikeHttpUrl(String s) {
  final t = s.trim().toLowerCase();
  return t.startsWith('http://') || t.startsWith('https://');
}

bool looksLikeUuidStorageObjectFileName(String s) {
  final base = s.split(RegExp(r'[\\/]+')).last.trim();
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(\.[a-z0-9]{1,12})?$',
    caseSensitive: false,
  ).hasMatch(base);
}

String attachmentDisplayNameHint(String description, String url) {
  final d = description.trim();
  if (d.isEmpty) return '';
  if (_looksLikeHttpUrl(d)) return '';
  if (looksLikeUuidStorageObjectFileName(d)) return '';
  return d;
}

Future<void> openAttachmentUrl(
  BuildContext context,
  String raw, {
  String? displayFileName,
}) async {
  final t = raw.trim();
  if (t.isEmpty) return;

  if (_looksLikeJsonNotAUrl(t)) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'This is not a valid file link (stored value looks like JSON). '
      'Remove this row and re-upload the file.',
      backgroundColor: Colors.orange,
    );
    return;
  }

  final uri = Uri.tryParse(t);
  if (uri == null || !uri.hasScheme) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'This attachment is not a valid web link',
      backgroundColor: Colors.orange,
    );
    return;
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'Cannot open links of type “$scheme” from here',
      backgroundColor: Colors.orange,
    );
    return;
  }

  if (isLocalAttachmentUrl(t)) {
    try {
      final fetchUrl = resolveAttachmentFetchUrl(t);
      final uri = Uri.parse(fetchUrl);
      final resp = await http.get(uri).timeout(const Duration(minutes: 2));
      if (resp.statusCode == 200) {
        final ct =
            resp.headers['content-type']?.split(';').first.trim() ??
            'application/octet-stream';
        final opened = await openAttachmentBytesInSystemViewer(
          resp.bodyBytes,
          ct,
          displayFileName?.trim().isNotEmpty == true
              ? displayFileName!.trim()
              : 'attachment',
        );
        if (!opened && context.mounted) {
          showCopyableSnackBar(
            context,
            'Could not open the file viewer.',
            backgroundColor: Colors.orange,
          );
        }
        return;
      }
      if (!context.mounted) return;
      showCopyableSnackBar(
        context,
        'Could not load attachment (HTTP ${resp.statusCode}).',
        backgroundColor: Colors.orange,
      );
    } catch (e) {
      if (!context.mounted) return;
      showCopyableSnackBar(
        context,
        'Could not open attachment: $e',
        backgroundColor: Colors.orange,
      );
    }
    return;
  }

  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showCopyableSnackBar(
      context,
      'Could not open the link',
      backgroundColor: Colors.orange,
    );
  }
}
