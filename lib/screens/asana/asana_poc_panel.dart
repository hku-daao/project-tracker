import 'package:flutter/material.dart';

import '../../services/attachment_upload_service.dart';
import '../../services/llm_service.dart';
import '../../utils/file_drop_region.dart';
import '../../utils/picked_file_bytes.dart';
import 'asana_detail_widgets.dart';
import 'asana_poc_file_text.dart';
import 'asana_theme.dart';
import '../asana_landing_screen.dart';

/// Super-admin proof of concept: files plus an optional note become a work bibliography.
class AsanaPocPanel extends StatefulWidget {
  const AsanaPocPanel({super.key, required this.palette});

  final AsanaLandingPalette palette;

  @override
  State<AsanaPocPanel> createState() => _AsanaPocPanelState();
}

class _AsanaPocPanelState extends State<AsanaPocPanel> {
  final _note = TextEditingController();
  final _files = <PickedFileBytes>[];
  bool _analyzing = false;
  String _bibliography = '';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _addFiles(List<PickedFileBytes> incoming) {
    if (incoming.isEmpty || _analyzing) return;
    final accepted = <PickedFileBytes>[];
    for (final file in incoming) {
      final error = AttachmentUploadService.uploadSizeError(
        file.bytes.length,
        file.name,
      );
      if (error != null) {
        showAsanaInfoDialog(
          context: context,
          title: 'File too large',
          content: error,
          palette: widget.palette,
        );
        continue;
      }
      accepted.add(file);
    }
    if (accepted.isEmpty) return;
    setState(() => _files.addAll(accepted));
  }

  Future<void> _pickFiles() async {
    if (_analyzing) return;
    final picked = await AttachmentUploadService.pickFilesForUpload(
      allowMultiple: true,
    );
    if (!mounted) return;
    if (picked.error != null) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Could not add files',
        content: picked.error!,
        palette: widget.palette,
      );
      return;
    }
    _addFiles([
      for (final file in picked.files)
        PickedFileBytes(name: file.label, bytes: file.bytes),
    ]);
  }

  Future<void> _analyze() async {
    if (_analyzing) return;
    if (_files.isEmpty) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Add a file',
        content: 'Drop or choose at least one file to analyze.',
        palette: widget.palette,
      );
      return;
    }
    setState(() => _analyzing = true);
    try {
      final parts = <String>[];
      var readable = 0;
      for (final file in _files) {
        final extracted = PocFileTextReader.read(file);
        if (extracted.readable) {
          readable++;
          parts.add('--- ${extracted.name} ---\n${extracted.text}');
        } else {
          parts.add(
            '--- ${extracted.name} ---\n${extracted.unreadReason ?? 'No readable text.'}',
          );
        }
      }
      final note = _note.text.trim();
      if (readable == 0 && note.isEmpty) {
        if (!mounted) return;
        await showAsanaInfoDialog(
          context: context,
          title: 'Nothing to read',
          content:
              'These files have no text that can be read. Add a note, or use a text, Word, or Outlook message file.',
          palette: widget.palette,
        );
        return;
      }
      var materials = parts.join('\n\n');
      const cap = 100000;
      if (materials.length > cap) {
        materials = '${materials.substring(0, cap)}\n[later files truncated]';
      }
      final summary = await LlmService.summarizeWorkBibliography(
        materials: materials,
        readerNote: note,
      );
      if (!mounted) return;
      setState(() => _bibliography = summary);
    } catch (e) {
      if (!mounted) return;
      final message = e is LlmHttpException
          ? (e.detail ?? e.message)
          : e.toString().replaceFirst('Bad state: ', '');
      await showAsanaInfoDialog(
        context: context,
        title: 'Could not analyze',
        content: message,
        palette: widget.palette,
      );
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compactTitle = MediaQuery.sizeOf(context).width < 600;
    return ColoredBox(
      color: widget.palette.panelBackground,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Text(
            'POC',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: compactTitle ? 14 : 18,
              fontWeight: FontWeight.w600,
              color: kAsanaTextPrimary,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: AsanaFileDropRegion(
                  enabled: !_analyzing,
                  onFiles: (files, _) => _addFiles(files),
                  child: Container(
                    height: 160,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: _analyzing
                          ? const Color(0xFFF3F1F0)
                          : const Color(0xFFF7F5F4),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFD0CBC8)),
                    ),
                    child: Text(
                      'Drop files here',
                      style: TextStyle(
                        fontSize: 14,
                        color: _analyzing
                            ? const Color(0xFFB0A9A6)
                            : const Color(0xFF6D6E6F),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AsanaDetailCircleAddButton(
                enabled: !_analyzing,
                tooltip: 'Add file',
                size: 32,
                onTap: (_) => _pickFiles(),
              ),
            ],
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var i = 0; i < _files.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _files[i].name.trim().isEmpty ? 'file' : _files[i].name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: kAsanaTextPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: _analyzing
                          ? null
                          : () => setState(() => _files.removeAt(i)),
                      icon: const Icon(Icons.close, size: 18),
                      color: kAsanaTextSecondary,
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 8),
          AsanaHoverTextField(
            controller: _note,
            canEdit: !_analyzing,
            readOnly: _analyzing,
            showOutline: true,
            maxLines: 4,
            minLines: 3,
            hintText: 'What are these files about? Optional',
            style: asanaDetailMultilineValueStyle(context),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _analyzing ? null : _analyze,
              style: FilledButton.styleFrom(
                backgroundColor: widget.palette.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: widget.palette.accent.withValues(
                  alpha: 0.4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              child: Text(_analyzing ? 'Analyzing…' : 'Analyze'),
            ),
          ),
          if (_bibliography.isNotEmpty) ...[
            const SizedBox(height: 20),
            SelectableText(
              _bibliography,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: kAsanaTextPrimary,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
