import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'asana_detail_widgets.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_inline_image_widgets.dart';
import 'asana_website_link_launch.dart';
import 'asana_theme.dart';

/// Asana-styled chip for a staged task attachment (file or website link).
class AsanaAttachmentDraftTile extends StatefulWidget {
  const AsanaAttachmentDraftTile({
    super.key,
    required this.isWebsiteLink,
    required this.title,
    this.url,
    this.subtitle,
    this.enabled = true,
    this.onRemove,
    this.onEditLink,
    this.onOpenFile,
    this.onDownload,
    this.imageBytes,
    this.mimeType,
    this.showImagePreview = false,
  });

  final bool isWebsiteLink;
  final String title;
  final String? url;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onRemove;
  final VoidCallback? onEditLink;
  final VoidCallback? onOpenFile;
  final VoidCallback? onDownload;
  final Uint8List? imageBytes;
  final String? mimeType;
  final bool showImagePreview;

  @override
  State<AsanaAttachmentDraftTile> createState() =>
      _AsanaAttachmentDraftTileState();
}

class _AsanaAttachmentDraftTileState extends State<AsanaAttachmentDraftTile> {
  bool _hovering = false;

  static const _border = Color(0xFFEDEAE9);
  static const _bg = Color(0xFFFFFFFF);
  static const _bgHover = Color(0xFFF9FAFB);
  static const _linkBlue = Color(0xFF4573D2);

  @override
  Widget build(BuildContext context) {
    final canRemove = widget.enabled && widget.onRemove != null;
    final canDownload = widget.enabled && widget.onDownload != null;
    final openFile = widget.onOpenFile ?? _openFilePreviewOverlay;
    final showRemove = canRemove;
    final showActions = showRemove || canDownload;

    if (!widget.isWebsiteLink && widget.showImagePreview) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InlineImageThumbnail(
          image: InlineImagePreviewItem(
            id: widget.url?.trim().isNotEmpty == true
                ? widget.url!.trim()
                : widget.title,
            url: widget.url,
            bytes: widget.imageBytes,
            description: widget.title,
            mimeType: widget.mimeType,
            canRemove: canRemove,
          ),
          onRemove: canRemove ? (_) => widget.onRemove?.call() : null,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Material(
          color: _hovering ? _bgHover : _bg,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: !widget.isWebsiteLink ? openFile : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _border),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AttachmentLeadingIcon(
                        isWebsiteLink: widget.isWebsiteLink,
                        attemptImagePreview: widget.showImagePreview,
                        filename: widget.title,
                        imageUrl: widget.url,
                        imageBytes: widget.imageBytes,
                        mimeType: widget.mimeType,
                        onEditLink: widget.onEditLink,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child:
                            widget.isWebsiteLink &&
                                (widget.url ?? '').isNotEmpty
                            ? _LinkBody(
                                title: widget.title,
                                url: widget.url!,
                                onEdit: widget.enabled
                                    ? widget.onEditLink
                                    : null,
                              )
                            : _PlainBody(
                                title: widget.title,
                                subtitle: widget.subtitle,
                              ),
                      ),
                      if (showActions)
                        SizedBox(width: canDownload && showRemove ? 46 : 22),
                    ],
                  ),
                  if (showActions)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (canDownload)
                            _TileCircleAction(
                              icon: Icons.download_outlined,
                              tooltip: 'Download',
                              onTap: widget.onDownload!,
                            ),
                          if (canDownload && showRemove)
                            const SizedBox(width: 4),
                          if (showRemove)
                            _TileCircleAction(
                              icon: Icons.close,
                              tooltip: 'Remove',
                              onTap: widget.onRemove!,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFilePreviewOverlay() async {
    // A read-only preview should never be blocked by a stale save/upload overlay.
    AsanaBlockingLoadingOverlay.hideAll();
    final kind = _fileKindFor(
      filename: widget.title,
      mimeType: widget.mimeType,
    );
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
                    maxWidth: MediaQuery.of(dialogContext).size.width * 0.72,
                    maxHeight: MediaQuery.of(dialogContext).size.height * 0.72,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Material(
                          color: Colors.white,
                          child: SizedBox(
                            width: 460,
                            height: 320,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                32,
                                48,
                                32,
                                32,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _FileKindIcon(kind: kind, size: 92),
                                  const SizedBox(height: 24),
                                  Text(
                                    widget.title,
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: asanaDetailValueStyle(context)
                                        .copyWith(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
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
                            if (widget.onDownload != null) ...[
                              _OverlayCircleButton(
                                icon: Icons.download_outlined,
                                tooltip: 'Download',
                                onTap: () {
                                  AsanaBlockingLoadingOverlay.hideAll();
                                  widget.onDownload!();
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
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
}

class _TileCircleAction extends StatelessWidget {
  const _TileCircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: Color(0xFF6D6E6F),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 12, color: Colors.white),
          ),
        ),
      ),
    );
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

class _AttachmentLeadingIcon extends StatelessWidget {
  const _AttachmentLeadingIcon({
    required this.isWebsiteLink,
    required this.attemptImagePreview,
    required this.filename,
    required this.imageUrl,
    required this.imageBytes,
    required this.mimeType,
    this.onEditLink,
  });

  final bool isWebsiteLink;
  final bool attemptImagePreview;
  final String filename;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final String? mimeType;
  final VoidCallback? onEditLink;

  @override
  Widget build(BuildContext context) {
    final fileKind = _fileKindFor(filename: filename, mimeType: mimeType);
    if (attemptImagePreview) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: InlineImageThumbnail(
          image: InlineImagePreviewItem(
            id: imageUrl?.trim().isNotEmpty == true ? imageUrl!.trim() : 'file',
            url: imageUrl,
            bytes: imageBytes,
            mimeType: mimeType,
            canRemove: false,
          ),
          width: 38,
          height: 38,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: isWebsiteLink && onEditLink != null
          ? InkWell(
              onTap: onEditLink,
              borderRadius: BorderRadius.circular(4),
              child: Icon(
                Icons.language_outlined,
                size: 18,
                color: kAsanaTextSecondary,
              ),
            )
          : isWebsiteLink
          ? Icon(Icons.language_outlined, size: 18, color: kAsanaTextSecondary)
          : _FileKindIcon(kind: fileKind, size: 20),
    );
  }
}

enum _FileIconKind {
  generic,
  word,
  excel,
  powerpoint,
  pdf,
  text,
  code,
  archive,
  video,
  audio,
  email,
}

_FileIconKind _fileKindFor({required String filename, String? mimeType}) {
  final name = filename.toLowerCase().trim();
  final mime = mimeType?.toLowerCase().trim() ?? '';
  if (name.endsWith('.doc') ||
      name.endsWith('.docx') ||
      mime == 'application/msword' ||
      mime ==
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
    return _FileIconKind.word;
  }
  if (name.endsWith('.xls') ||
      name.endsWith('.xlsx') ||
      name.endsWith('.csv') ||
      mime == 'application/vnd.ms-excel' ||
      mime == 'text/csv' ||
      mime ==
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
    return _FileIconKind.excel;
  }
  if (name.endsWith('.ppt') ||
      name.endsWith('.pptx') ||
      mime == 'application/vnd.ms-powerpoint' ||
      mime ==
          'application/vnd.openxmlformats-officedocument.presentationml.presentation') {
    return _FileIconKind.powerpoint;
  }
  if (name.endsWith('.pdf') || mime == 'application/pdf') {
    return _FileIconKind.pdf;
  }
  if (name.endsWith('.txt') ||
      name.endsWith('.md') ||
      mime.startsWith('text/plain') ||
      mime == 'text/markdown') {
    return _FileIconKind.text;
  }
  if (name.endsWith('.json') ||
      name.endsWith('.xml') ||
      name.endsWith('.html') ||
      name.endsWith('.htm') ||
      name.endsWith('.css') ||
      name.endsWith('.js') ||
      name.endsWith('.ts') ||
      name.endsWith('.dart') ||
      mime == 'application/json' ||
      mime == 'application/xml' ||
      mime == 'text/xml' ||
      mime == 'text/html' ||
      mime == 'text/css' ||
      mime == 'application/javascript' ||
      mime == 'text/javascript') {
    return _FileIconKind.code;
  }
  if (name.endsWith('.zip') ||
      name.endsWith('.rar') ||
      name.endsWith('.7z') ||
      mime == 'application/zip' ||
      mime == 'application/x-rar-compressed' ||
      mime == 'application/x-7z-compressed') {
    return _FileIconKind.archive;
  }
  if (name.endsWith('.mp4') ||
      name.endsWith('.mov') ||
      name.endsWith('.avi') ||
      name.endsWith('.mkv') ||
      mime.startsWith('video/')) {
    return _FileIconKind.video;
  }
  if (name.endsWith('.mp3') ||
      name.endsWith('.wav') ||
      name.endsWith('.m4a') ||
      mime.startsWith('audio/')) {
    return _FileIconKind.audio;
  }
  if (name.endsWith('.eml') ||
      name.endsWith('.msg') ||
      mime == 'message/rfc822' ||
      mime == 'application/vnd.ms-outlook') {
    return _FileIconKind.email;
  }
  return _FileIconKind.generic;
}

IconData _iconForFileKind(_FileIconKind kind) {
  return switch (kind) {
    _FileIconKind.generic => Icons.insert_drive_file_outlined,
    _FileIconKind.word => Icons.article_outlined,
    _FileIconKind.excel => Icons.table_chart_outlined,
    _FileIconKind.powerpoint => Icons.slideshow_outlined,
    _FileIconKind.pdf => Icons.picture_as_pdf_outlined,
    _FileIconKind.text => Icons.notes_outlined,
    _FileIconKind.code => Icons.code_outlined,
    _FileIconKind.archive => Icons.archive_outlined,
    _FileIconKind.video => Icons.movie_outlined,
    _FileIconKind.audio => Icons.audiotrack_outlined,
    _FileIconKind.email => Icons.email_outlined,
  };
}

Color _colorForFileKind(_FileIconKind kind) {
  return switch (kind) {
    _FileIconKind.generic => kAsanaTextSecondary,
    _FileIconKind.word => const Color(0xFF2B579A),
    _FileIconKind.excel => const Color(0xFF217346),
    _FileIconKind.powerpoint => const Color(0xFFD24726),
    _FileIconKind.pdf => const Color(0xFFE53935),
    _FileIconKind.text => const Color(0xFF6B7280),
    _FileIconKind.code => const Color(0xFF7B1FA2),
    _FileIconKind.archive => const Color(0xFF8D6E63),
    _FileIconKind.video => const Color(0xFF00897B),
    _FileIconKind.audio => const Color(0xFF3949AB),
    _FileIconKind.email => const Color(0xFF546E7A),
  };
}

class _FileKindIcon extends StatelessWidget {
  const _FileKindIcon({required this.kind, required this.size});

  final _FileIconKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = _officeBadgeForFileKind(kind);
    if (badge != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: badge.color,
          borderRadius: BorderRadius.circular(size * 0.2),
        ),
        alignment: Alignment.center,
        child: Text(
          badge.label,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.58,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return Icon(
      _iconForFileKind(kind),
      size: size,
      color: _colorForFileKind(kind),
    );
  }
}

({String label, Color color})? _officeBadgeForFileKind(_FileIconKind kind) {
  return switch (kind) {
    _FileIconKind.word => (label: 'W', color: const Color(0xFF2B579A)),
    _FileIconKind.excel => (label: 'X', color: const Color(0xFF217346)),
    _FileIconKind.powerpoint => (label: 'P', color: const Color(0xFFD24726)),
    _ => null,
  };
}

class _PlainBody extends StatelessWidget {
  const _PlainBody({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: asanaDetailValueStyle(context)),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: asanaDetailLabelStyle(context)),
        ],
      ],
    );
  }
}

class _LinkBody extends StatelessWidget {
  const _LinkBody({required this.title, required this.url, this.onEdit});

  final String title;
  final String url;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final urlStyle = asanaDetailValueStyle(context).copyWith(
      color: _AsanaAttachmentDraftTileState._linkBlue,
      decoration: TextDecoration.underline,
      decorationColor: _AsanaAttachmentDraftTileState._linkBlue,
    );
    final titleStyle = asanaDetailValueStyle(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                title,
                style: titleStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: url,
                style: urlStyle,
                recognizer: TapGestureRecognizer()
                  ..onTap = () => openWebsiteUrlInNewTab(url),
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (onEdit != null)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(4),
              child: const SizedBox(width: double.infinity, height: 6),
            ),
          ),
      ],
    );
  }
}
