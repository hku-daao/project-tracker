import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/backend_api.dart';
import '../../services/supabase_service.dart';
import '../../utils/attachment_url_launch.dart';
import 'asana_detail_widgets.dart';

final RegExp _inlineImageMarkerPattern = RegExp(
  r'(?:^|\n)\s*\[image:[^\]]+\]\s*',
  caseSensitive: false,
);

const String inlineImageOnlyCommentPlaceholder = '[inline-image]';

String stripInlineImageMarkers(String text) {
  return text
      .replaceAll(inlineImageOnlyCommentPlaceholder, '')
      .replaceAll(_inlineImageMarkerPattern, '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class InlineImageToolbar extends StatelessWidget {
  const InlineImageToolbar({super.key, required this.enabled, required this.onAdd});

  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: enabled ? onAdd : null,
        icon: const Icon(Icons.image_outlined, size: 16),
        label: const Text('Add inline image'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class InlineImagePreviewList extends StatelessWidget {
  const InlineImagePreviewList({super.key, required this.images});

  final List<InlineAttachmentRow> images;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final image in images) ...[
            _InlineImagePreview(image: image),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _InlineImagePreview extends StatefulWidget {
  const _InlineImagePreview({required this.image});

  final InlineAttachmentRow image;

  @override
  State<_InlineImagePreview> createState() => _InlineImagePreviewState();
}

class _InlineImagePreviewState extends State<_InlineImagePreview> {
  late Future<_InlineImageBytes> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadInlineImageBytes(widget.image.url);
  }

  @override
  void didUpdateWidget(covariant _InlineImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.url != widget.image.url) {
      _future = _loadInlineImageBytes(widget.image.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 260),
        color: const Color(0xFFF9FAFB),
        child: FutureBuilder<_InlineImageBytes>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data != null && data.bytes.isNotEmpty) {
              return Image.memory(data.bytes, fit: BoxFit.contain);
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final label = widget.image.description?.trim().isNotEmpty == true
                ? widget.image.description!.trim()
                : widget.image.url;
            return Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFF3F4F6),
              child: Text(
                data?.error == null ? label : '$label\n${data!.error}',
                style: asanaDetailLabelStyle(context),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InlineImageBytes {
  const _InlineImageBytes({required this.bytes, this.error});

  final Uint8List bytes;
  final String? error;
}

String? _firebaseStorageObjectPathFromUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  if (!isAppFirebaseStorageAttachmentUrl(raw)) return null;
  final i = uri.path.indexOf('/o/');
  if (i < 0) return null;
  final encoded = uri.path.substring(i + 3);
  if (encoded.isEmpty) return null;
  try {
    return Uri.decodeComponent(encoded);
  } catch (_) {
    return null;
  }
}

Future<_InlineImageBytes> _loadInlineImageBytes(String rawUrl) async {
  final url = rawUrl.trim();
  if (url.isEmpty) {
    return _InlineImageBytes(bytes: Uint8List(0), error: 'Missing image URL.');
  }

  final objectPath = _firebaseStorageObjectPathFromUrl(url);
  if (objectPath != null && objectPath.isNotEmpty) {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (idToken != null && idToken.isNotEmpty) {
      try {
        final proxy = await BackendApi().createAttachmentProxyStreamUrl(
          idToken: idToken,
          objectPath: objectPath,
        );
        final proxyUri = proxy == null ? null : Uri.tryParse(proxy);
        if (proxyUri != null && proxyUri.hasScheme) {
          final resp = await http
              .get(proxyUri, headers: {'Authorization': 'Bearer $idToken'})
              .timeout(const Duration(minutes: 2));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            return _InlineImageBytes(bytes: resp.bodyBytes);
          }
          debugPrint(
            'inline image proxy HTTP ${resp.statusCode}: ${resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body}',
          );
        }
      } catch (e, st) {
        debugPrint('inline image proxy load: $e\n$st');
      }
    }
  }

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return _InlineImageBytes(bytes: Uint8List(0), error: 'Invalid image URL.');
  }
  try {
    final resp = await http.get(uri).timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
      return _InlineImageBytes(bytes: resp.bodyBytes);
    }
    return _InlineImageBytes(
      bytes: Uint8List(0),
      error: 'Could not load image (HTTP ${resp.statusCode}).',
    );
  } catch (e, st) {
    debugPrint('inline image direct load: $e\n$st');
    return _InlineImageBytes(bytes: Uint8List(0), error: 'Could not load image.');
  }
}
