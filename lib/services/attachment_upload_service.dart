import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../utils/attachment_file_pick.dart';

/// Local file uploads via the Node backend (`POST /api/files/upload`).
class AttachmentUploadService {
  AttachmentUploadService._();

  static const List<({Uint8List bytes, String label})> _emptyPickedUploads =
      <({Uint8List bytes, String label})>[];

  static const List<({String url, String label})> _emptyUploadedFiles =
      <({String url, String label})>[];

  static const int _maxBytes = 50 * 1024 * 1024;
  static const int aclMetadataSlotCount = 10;
  static const String storageMetadataOriginalFileNameKey = 'originalFileName';

  static Map<String, String> aclMetadataFromStaffKeys(Iterable<String?> keys) {
    final seen = <String>{};
    final out = <String, String>{};
    var i = 0;
    for (final raw in keys) {
      final s = raw?.trim();
      if (s == null || s.isEmpty || seen.contains(s)) continue;
      seen.add(s);
      out['m$i'] = s;
      i++;
      if (i >= aclMetadataSlotCount) break;
    }
    return out;
  }

  static Future<String?> fetchOriginalFileNameFromMetadata(
    String objectPath,
  ) async {
    final base = objectPath.split('/').last;
    if (base.contains('.')) return null;
    return null;
  }

  static String _contentTypeForFilename(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.txt')) return 'text/plain';
    if (n.endsWith('.csv')) return 'text/csv';
    return 'application/octet-stream';
  }

  static String? objectPathFromStorageDownloadUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return null;
    const marker = '/api/files/';
    final idx = rawUrl.indexOf(marker);
    if (idx >= 0) {
      return Uri.decodeComponent(rawUrl.substring(idx + marker.length).split('?').first);
    }
    return null;
  }

  static bool storageObjectPathBelongsToCurrentUser(String objectPath) {
    return objectPath.trim().isNotEmpty;
  }

  static bool storageDownloadUrlBelongsToCurrentUser(String rawUrl) {
    final t = rawUrl.trim();
    if (t.contains('/api/files/')) return true;
    final objectPath = objectPathFromStorageDownloadUrl(t);
    return objectPath != null && objectPath.isNotEmpty;
  }

  static Future<String?> deleteUploadedObjectByUrl(String rawUrl) async {
    // Local files remain on disk; DB rows are soft-deleted separately.
    if (storageDownloadUrlBelongsToCurrentUser(rawUrl)) return null;
    return 'Unsupported attachment URL.';
  }

  static Future<({Uint8List? bytes, String? label, String? error})>
  pickFileForUpload() async {
    final picked = await pickFilesForUpload(allowMultiple: false);
    if (picked.error != null) {
      return (bytes: null, label: null, error: picked.error);
    }
    if (picked.files.isEmpty) {
      return (bytes: null, label: null, error: null);
    }
    final first = picked.files.first;
    return (bytes: first.bytes, label: first.label, error: null);
  }

  static Future<
    ({List<({Uint8List bytes, String label})> files, String? error})
  >
  pickFilesForUpload({bool allowMultiple = true}) async {
    try {
      final picked = await pickFilesWithBytes(allowMultiple: allowMultiple);
      if (picked.isEmpty) {
        return (files: _emptyPickedUploads, error: null);
      }
      final files = <({Uint8List bytes, String label})>[];
      for (final file in picked) {
        final label = file.name.trim().isEmpty ? 'attachment' : file.name.trim();
        if (file.bytes.length > _maxBytes) {
          return (
            files: _emptyPickedUploads,
            error: 'File too large (max 50 MB): $label',
          );
        }
        files.add((bytes: file.bytes, label: label));
      }
      return (files: files, error: null);
    } catch (e, st) {
      debugPrint('pickFilesForUpload: $e\n$st');
      return (files: _emptyPickedUploads, error: e.toString());
    }
  }

  static Future<({String? url, String? label, String? error})> _uploadBytes({
    required String entityType,
    required String entityId,
    required String originalFilename,
    required Uint8List bytes,
    required List<String?> aclStaffKeys,
  }) async {
    if (aclMetadataFromStaffKeys(aclStaffKeys).isEmpty) {
      return (
        url: null,
        label: null,
        error:
            'Cannot upload: no staff keys for attachment access (creator / PIC / assignees).',
      );
    }
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/files/upload');
      final req = http.MultipartRequest('POST', uri)
        ..fields['entity_type'] = entityType
        ..fields['entity_id'] = entityId.trim()
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: originalFilename,
          ),
        );
      final streamed = await req.send().timeout(const Duration(minutes: 2));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        return (
          url: null,
          label: null,
          error: 'Upload failed (HTTP ${streamed.statusCode}): $body',
        );
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final url = json['url']?.toString().trim();
      if (url == null || url.isEmpty) {
        return (
          url: null,
          label: null,
          error: 'Upload did not return a file URL.',
        );
      }
      return (
        url: url,
        label: json['filename']?.toString() ?? originalFilename,
        error: null,
      );
    } catch (e, st) {
      debugPrint('_uploadBytes: $e\n$st');
      return (url: null, label: null, error: e.toString());
    }
  }

  static Future<({String? url, String? label, String? error})> uploadBytesForTask(
    String taskId, {
    required Uint8List bytes,
    required String originalFilename,
    required List<String?> aclStaffKeys,
    void Function()? onUploadPhaseStarted,
    void Function()? onUploadPhaseEnded,
  }) async {
    if (taskId.trim().isEmpty) {
      return (url: null, label: null, error: 'Missing task id');
    }
    try {
      onUploadPhaseStarted?.call();
      return await _uploadBytes(
        entityType: 'task',
        entityId: taskId,
        originalFilename: originalFilename,
        bytes: bytes,
        aclStaffKeys: aclStaffKeys,
      );
    } finally {
      onUploadPhaseEnded?.call();
    }
  }

  static Future<({String? url, String? label, String? error})>
  uploadBytesForProject(
    String projectId, {
    required Uint8List bytes,
    required String originalFilename,
    required List<String?> aclStaffKeys,
    void Function()? onUploadPhaseStarted,
    void Function()? onUploadPhaseEnded,
  }) async {
    if (projectId.trim().isEmpty) {
      return (url: null, label: null, error: 'Missing project id');
    }
    try {
      onUploadPhaseStarted?.call();
      return await _uploadBytes(
        entityType: 'project',
        entityId: projectId,
        originalFilename: originalFilename,
        bytes: bytes,
        aclStaffKeys: aclStaffKeys,
      );
    } finally {
      onUploadPhaseEnded?.call();
    }
  }

  static Future<({String? url, String? label, String? error})>
  uploadBytesForSubtask(
    String subtaskId, {
    required Uint8List bytes,
    required String originalFilename,
    required List<String?> aclStaffKeys,
    void Function()? onUploadPhaseStarted,
    void Function()? onUploadPhaseEnded,
  }) async {
    if (subtaskId.trim().isEmpty) {
      return (url: null, label: null, error: 'Missing subtask id');
    }
    try {
      onUploadPhaseStarted?.call();
      return await _uploadBytes(
        entityType: 'subtask',
        entityId: subtaskId,
        originalFilename: originalFilename,
        bytes: bytes,
        aclStaffKeys: aclStaffKeys,
      );
    } finally {
      onUploadPhaseEnded?.call();
    }
  }

  static Future<({List<({String url, String label})> files, String? error})>
  pickUploadFilesForTask(
    String taskId, {
    required List<String?> aclStaffKeys,
    void Function()? onUploadPhaseStarted,
    void Function()? onUploadPhaseEnded,
    bool allowMultiple = true,
  }) async {
    final picked = await pickFilesForUpload(allowMultiple: allowMultiple);
    if (picked.error != null) {
      return (files: _emptyUploadedFiles, error: picked.error);
    }
    final uploaded = <({String url, String label})>[];
    for (final file in picked.files) {
      final upload = await uploadBytesForTask(
        taskId,
        bytes: file.bytes,
        originalFilename: file.label,
        aclStaffKeys: aclStaffKeys,
        onUploadPhaseStarted: onUploadPhaseStarted,
        onUploadPhaseEnded: onUploadPhaseEnded,
      );
      if (upload.error != null) return (files: uploaded, error: upload.error);
      final url = upload.url?.trim();
      if (url == null || url.isEmpty) {
        return (
          files: uploaded,
          error: 'File upload did not return a download link.',
        );
      }
      uploaded.add((url: url, label: upload.label ?? file.label));
    }
    return (files: uploaded, error: null);
  }

  static Future<({List<({String url, String label})> files, String? error})>
  pickUploadFilesForProject(
    String projectId, {
    required List<String?> aclStaffKeys,
    void Function()? onUploadPhaseStarted,
    void Function()? onUploadPhaseEnded,
    bool allowMultiple = true,
  }) async {
    final picked = await pickFilesForUpload(allowMultiple: allowMultiple);
    if (picked.error != null) {
      return (files: _emptyUploadedFiles, error: picked.error);
    }
    final uploaded = <({String url, String label})>[];
    for (final file in picked.files) {
      final upload = await uploadBytesForProject(
        projectId,
        bytes: file.bytes,
        originalFilename: file.label,
        aclStaffKeys: aclStaffKeys,
        onUploadPhaseStarted: onUploadPhaseStarted,
        onUploadPhaseEnded: onUploadPhaseEnded,
      );
      if (upload.error != null) return (files: uploaded, error: upload.error);
      final url = upload.url?.trim();
      if (url == null || url.isEmpty) {
        return (
          files: uploaded,
          error: 'File upload did not return a download link.',
        );
      }
      uploaded.add((url: url, label: upload.label ?? file.label));
    }
    return (files: uploaded, error: null);
  }

  static Future<({List<({String url, String label})> files, String? error})>
  pickUploadFilesForSubtask(
    String subtaskId, {
    required List<String?> aclStaffKeys,
    void Function()? onUploadPhaseStarted,
    void Function()? onUploadPhaseEnded,
    bool allowMultiple = true,
  }) async {
    final picked = await pickFilesForUpload(allowMultiple: allowMultiple);
    if (picked.error != null) {
      return (files: _emptyUploadedFiles, error: picked.error);
    }
    final uploaded = <({String url, String label})>[];
    for (final file in picked.files) {
      final upload = await uploadBytesForSubtask(
        subtaskId,
        bytes: file.bytes,
        originalFilename: file.label,
        aclStaffKeys: aclStaffKeys,
        onUploadPhaseStarted: onUploadPhaseStarted,
        onUploadPhaseEnded: onUploadPhaseEnded,
      );
      if (upload.error != null) return (files: uploaded, error: upload.error);
      final url = upload.url?.trim();
      if (url == null || url.isEmpty) {
        return (
          files: uploaded,
          error: 'File upload did not return a download link.',
        );
      }
      uploaded.add((url: url, label: upload.label ?? file.label));
    }
    return (files: uploaded, error: null);
  }

  static Future<({String? url, String? label, String? error})> pickUploadForTask(
    String taskId, {
    required List<String?> aclStaffKeys,
    void Function()? onUploadPhaseStarted,
    void Function()? onUploadPhaseEnded,
  }) async {
    final uploaded = await pickUploadFilesForTask(
      taskId,
      aclStaffKeys: aclStaffKeys,
      onUploadPhaseStarted: onUploadPhaseStarted,
      onUploadPhaseEnded: onUploadPhaseEnded,
      allowMultiple: false,
    );
    if (uploaded.error != null) {
      return (url: null, label: null, error: uploaded.error);
    }
    if (uploaded.files.isEmpty) {
      return (url: null, label: null, error: null);
    }
    final first = uploaded.files.first;
    return (url: first.url, label: first.label, error: null);
  }

  static Future<({String? url, String? label, String? error})>
  pickUploadForSubtask(
    String subtaskId, {
    required List<String?> aclStaffKeys,
    void Function()? onUploadPhaseStarted,
    void Function()? onUploadPhaseEnded,
  }) async {
    final uploaded = await pickUploadFilesForSubtask(
      subtaskId,
      aclStaffKeys: aclStaffKeys,
      onUploadPhaseStarted: onUploadPhaseStarted,
      onUploadPhaseEnded: onUploadPhaseEnded,
      allowMultiple: false,
    );
    if (uploaded.error != null) {
      return (url: null, label: null, error: uploaded.error);
    }
    if (uploaded.files.isEmpty) {
      return (url: null, label: null, error: null);
    }
    final first = uploaded.files.first;
    return (url: first.url, label: first.label, error: null);
  }
}
