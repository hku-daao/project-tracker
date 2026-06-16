import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/backend_api.dart';
import '../../utils/attachment_open_bytes.dart';
import '../../services/supabase_service.dart';
import 'asana_blocking_loading_overlay.dart';

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
  const InlineImageToolbar({
    super.key,
    required this.enabled,
    required this.onAdd,
  });

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
  const InlineImagePreviewList({
    super.key,
    required this.images,
    this.onRemove,
  });

  final List<InlineImagePreviewItem> images;
  final void Function(InlineImagePreviewItem image)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final image in images)
            _InlineImagePreview(
              key: ValueKey(image.id),
              image: image,
              onRemove: onRemove,
            ),
        ],
      ),
    );
  }
}

class InlineImageThumbnail extends StatelessWidget {
  const InlineImageThumbnail({
    super.key,
    required this.image,
    this.onRemove,
    this.width = 92,
    this.height = 92,
  });

  final InlineImagePreviewItem image;
  final void Function(InlineImagePreviewItem image)? onRemove;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _InlineImagePreview(
      image: image,
      onRemove: onRemove,
      width: width,
      height: height,
    );
  }
}

class InlineImagePreviewItem {
  const InlineImagePreviewItem({
    required this.id,
    this.inlineAttachment,
    this.bytes,
    this.url,
    this.description,
    this.mimeType,
    this.canRemove = false,
  });

  factory InlineImagePreviewItem.saved(InlineAttachmentRow row) {
    return InlineImagePreviewItem(
      id: row.id,
      inlineAttachment: row,
      url: row.url,
      description: row.description,
      mimeType: row.mimeType,
    );
  }

  final String id;
  final InlineAttachmentRow? inlineAttachment;
  final Uint8List? bytes;
  final String? url;
  final String? description;
  final String? mimeType;
  final bool canRemove;

  bool get isSaved => inlineAttachment != null;
}

class _InlineImagePreview extends StatefulWidget {
  const _InlineImagePreview({
    super.key,
    required this.image,
    this.onRemove,
    this.width = 92,
    this.height = 92,
  });

  final InlineImagePreviewItem image;
  final void Function(InlineImagePreviewItem image)? onRemove;
  final double width;
  final double height;

  @override
  State<_InlineImagePreview> createState() => _InlineImagePreviewState();
}

class _InlineImagePreviewState extends State<_InlineImagePreview> {
  late Future<_InlineImageBytes> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadInlineImageBytes(widget.image);
  }

  @override
  void didUpdateWidget(covariant _InlineImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.id != widget.image.id ||
        oldWidget.image.url != widget.image.url ||
        oldWidget.image.bytes != widget.image.bytes) {
      _future = _loadInlineImageBytes(widget.image);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openInlineImageOverlay(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FutureBuilder<_InlineImageBytes>(
                      future: _future,
                      builder: (context, snapshot) {
                        final data = snapshot.data;
                        if (data != null && data.bytes.isNotEmpty) {
                          return Image.memory(data.bytes, fit: BoxFit.cover);
                        }
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        return Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.grey.shade500,
                            size: 22,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.image.canRemove && widget.onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: InkWell(
                onTap: () => widget.onRemove!(widget.image),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFD1D5DB)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openInlineImageOverlay(BuildContext context) async {
    // Keep the preview controls usable even if a previous global loading overlay is stale.
    AsanaBlockingLoadingOverlay.hideAll();
    final data = await _future;
    if (!context.mounted || data.bytes.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(dialogContext).size.width * 0.88,
                    maxHeight: MediaQuery.of(dialogContext).size.height * 0.84,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Material(
                          color: Colors.white,
                          child: InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 4,
                            child: Image.memory(
                              data.bytes,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _OverlayCircleButton(
                              icon: Icons.download_outlined,
                              tooltip: 'Download',
                              onTap: () async {
                                AsanaBlockingLoadingOverlay.hideAll();
                                await openAttachmentBytesInSystemViewer(
                                  data.bytes,
                                  data.contentType,
                                  _downloadName(),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _OverlayCircleButton(
                              icon: Icons.close,
                              tooltip: 'Close',
                              onTap: () {
                                AsanaBlockingLoadingOverlay.hideAll();
                                Navigator.of(dialogContext).pop();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _downloadName() {
    final raw = widget.image.description?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return 'inline-image';
  }
}

class _OverlayCircleButton extends StatelessWidget {
  const _OverlayCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: const Color(0xFF374151)),
          ),
        ),
      ),
    );
  }
}

class _InlineImageBytes {
  const _InlineImageBytes({
    required this.bytes,
    this.contentType = 'image/*',
    this.error,
  });

  final Uint8List bytes;
  final String contentType;
  final String? error;
}

String? _firebaseStorageObjectPathFromUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host != 'firebasestorage.googleapis.com' &&
      host != 'storage.googleapis.com') {
    return null;
  }
  if (host == 'storage.googleapis.com') {
    final segments = uri.pathSegments;
    if (segments.length < 2) return null;
    return segments.skip(1).join('/');
  }
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

Future<_InlineImageBytes> _loadInlineImageBytes(
  InlineImagePreviewItem image,
) async {
  final localBytes = image.bytes;
  if (localBytes != null && localBytes.isNotEmpty) {
    return _InlineImageBytes(bytes: localBytes);
  }
  final url = image.url?.trim() ?? '';
  if (url.isEmpty) {
    debugPrint(
      'attachment thumbnail load failed: missing image URL id=${image.id}',
    );
    return _InlineImageBytes(bytes: Uint8List(0), error: 'Missing image URL.');
  }

  final objectPath = _firebaseStorageObjectPathFromUrl(url);
  debugPrint(
    'attachment thumbnail load start: id=${image.id} urlHost=${Uri.tryParse(url)?.host ?? '(invalid)'} objectPath=${objectPath ?? '(none)'} mimeType=${image.mimeType ?? '(none)'}',
  );
  if (objectPath != null && objectPath.isNotEmpty) {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (user == null) {
      debugPrint('attachment thumbnail proxy skipped: Firebase user is null');
    } else if (idToken == null || idToken.isEmpty) {
      debugPrint(
        'attachment thumbnail proxy skipped: Firebase ID token is empty',
      );
    }
    if (idToken != null && idToken.isNotEmpty) {
      try {
        final proxy = await BackendApi().createAttachmentProxyStreamUrl(
          idToken: idToken,
          objectPath: objectPath,
        );
        final proxyUri = proxy == null ? null : Uri.tryParse(proxy);
        debugPrint(
          'attachment thumbnail proxy session: objectPath=$objectPath proxy=${proxyUri == null ? '(null/invalid)' : proxyUri.toString()}',
        );
        if (proxyUri != null && proxyUri.hasScheme) {
          final resp = await http
              .get(proxyUri, headers: {'Authorization': 'Bearer $idToken'})
              .timeout(const Duration(minutes: 2));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            debugPrint(
              'attachment thumbnail proxy success: bytes=${resp.bodyBytes.length} contentType=${resp.headers['content-type'] ?? '(none)'}',
            );
            return _InlineImageBytes(
              bytes: resp.bodyBytes,
              contentType:
                  resp.headers['content-type']?.split(';').first.trim() ??
                  image.mimeType ??
                  'image/*',
            );
          }
          debugPrint(
            'attachment thumbnail proxy HTTP ${resp.statusCode}: ${resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body}',
          );
        }
      } catch (e, st) {
        debugPrint('attachment thumbnail proxy exception: $e\n$st');
      }
    }
  } else {
    debugPrint(
      'attachment thumbnail proxy skipped: no Firebase object path parsed',
    );
  }

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    debugPrint('attachment thumbnail direct skipped: invalid URL $url');
    return _InlineImageBytes(bytes: Uint8List(0), error: 'Invalid image URL.');
  }
  try {
    final resp = await http.get(uri).timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
      debugPrint(
        'attachment thumbnail direct success: bytes=${resp.bodyBytes.length} contentType=${resp.headers['content-type'] ?? '(none)'}',
      );
      return _InlineImageBytes(
        bytes: resp.bodyBytes,
        contentType:
            resp.headers['content-type']?.split(';').first.trim() ??
            image.mimeType ??
            'image/*',
      );
    }
    debugPrint(
      'attachment thumbnail direct HTTP ${resp.statusCode}: ${resp.body.length > 200 ? '${resp.body.substring(0, 200)}...' : resp.body}',
    );
    return _InlineImageBytes(
      bytes: Uint8List(0),
      error: 'Could not load image (HTTP ${resp.statusCode}).',
    );
  } catch (e, st) {
    debugPrint('attachment thumbnail direct exception: $e\n$st');
    return _InlineImageBytes(
      bytes: Uint8List(0),
      error: 'Could not load image.',
    );
  }
}
