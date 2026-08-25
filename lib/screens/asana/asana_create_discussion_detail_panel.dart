import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../app_state.dart';
import '../../services/attachment_upload_service.dart';
import '../../services/database_service.dart';
import '../../services/llm_service.dart';
import '../../utils/attachment_file_pick.dart';
import '../asana_landing_screen.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';
import 'asana_inline_image_widgets.dart';
import 'asana_task_ai_assistant.dart';
import 'asana_theme.dart';

class _ForumInlineImageDraft {
  _ForumInlineImageDraft({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.bytes,
    required this.label,
    this.sortOrder = 0,
  });

  final String id;
  final String entityType;
  final String entityId;
  final Uint8List bytes;
  final String label;
  final String mimeType = 'image/*';
  final int sortOrder;
}

class _DiscussionAiSuggestion {
  const _DiscussionAiSuggestion({
    required this.id,
    required this.fieldLabel,
    required this.currentValue,
    required this.suggestedValue,
    required this.onAdopt,
  });

  final String id;
  final String fieldLabel;
  final String currentValue;
  final String suggestedValue;
  final VoidCallback onAdopt;
}

class AsanaCreateDiscussionDetailPanel extends StatefulWidget {
  const AsanaCreateDiscussionDetailPanel({
    super.key,
    required this.palette,
    required this.onClose,
    this.onCreated,
  });

  final AsanaLandingPalette palette;
  final VoidCallback onClose;
  final VoidCallback? onCreated;

  @override
  State<AsanaCreateDiscussionDetailPanel> createState() =>
      _AsanaCreateDiscussionDetailPanelState();
}

class _AsanaCreateDiscussionDetailPanelState
    extends State<AsanaCreateDiscussionDetailPanel> {
  static const List<String> _categories = [
    'General',
    'Announcement',
    'Suggestion',
    'Feature idea',
    'Bug report',
  ];

  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _aiPromptController = TextEditingController();
  final List<_ForumInlineImageDraft> _pendingInlineImageAdds = [];
  final LayerLink _categoryAnchorLink = LayerLink();
  final LayerLink _statusAnchorLink = LayerLink();
  String _category = 'General';
  String _status = 'Open';
  bool _saving = false;
  bool _aiBusy = false;
  String? _aiMessage;
  List<_DiscussionAiSuggestion> _aiSuggestions = const [];
  int _anchoredPickerReopenBlockedUntilMs = 0;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _aiPromptController.dispose();
    _pendingInlineImageAdds.clear();
    super.dispose();
  }

  Future<void> _askAi() async {
    final prompt = _aiPromptController.text.trim();
    if (prompt.isEmpty || !LlmService.isConfigured) return;
    setState(() {
      _aiBusy = true;
      _aiMessage = null;
    });
    try {
      final raw = await LlmService.suggestDiscussionThreadDraft(
        userPrompt: prompt,
        formContext:
            '''
Current forum draft:
- title: ${_titleController.text.trim().isEmpty ? "(empty)" : _titleController.text.trim()}
- category: $_category
- status: $_status
- content: ${_contentController.text.trim().isEmpty ? "(empty)" : _contentController.text.trim()}
''',
      );
      if (!mounted) return;
      final title = raw['title']?.toString().trim();
      final content = raw['content']?.toString().trim();
      final category = raw['category']?.toString().trim();
      final status = raw['status']?.toString().trim();
      final suggestions = <_DiscussionAiSuggestion>[];
      void addSuggestion({
        required String id,
        required String label,
        required String current,
        required String? suggested,
        required VoidCallback onAdopt,
      }) {
        final value = suggested?.trim();
        if (value == null || value.isEmpty) return;
        if (_sameNormalizedText(value, current)) return;
        suggestions.add(
          _DiscussionAiSuggestion(
            id: id,
            fieldLabel: label,
            currentValue: current.trim().isEmpty ? '(empty)' : current.trim(),
            suggestedValue: value,
            onAdopt: onAdopt,
          ),
        );
      }

      addSuggestion(
        id: 'title',
        label: 'Topic',
        current: _titleController.text,
        suggested: title,
        onAdopt: () => _titleController.text = title ?? '',
      );
      addSuggestion(
        id: 'content',
        label: 'Content',
        current: _contentController.text,
        suggested: content,
        onAdopt: () => _contentController.text = content ?? '',
      );
      if (category != null && _categories.contains(category)) {
        addSuggestion(
          id: 'category',
          label: 'Category',
          current: _category,
          suggested: category,
          onAdopt: () => _category = category,
        );
      }
      if (status != null &&
          const {'Open', 'Resolved', 'Closed'}.contains(status)) {
        addSuggestion(
          id: 'status',
          label: 'Status',
          current: _status,
          suggested: status,
          onAdopt: () => _status = status,
        );
      }
      setState(() {
        _aiMessage = raw['overallComment']?.toString().trim();
        _aiSuggestions = suggestions;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiMessage = e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  static bool _sameNormalizedText(String a, String b) {
    String norm(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');
    return norm(a) == norm(b);
  }

  void _acceptAiSuggestion(_DiscussionAiSuggestion suggestion) {
    setState(() {
      suggestion.onAdopt();
      _aiSuggestions = _aiSuggestions
          .where((s) => s.id != suggestion.id)
          .toList();
    });
  }

  void _dismissAiSuggestion(_DiscussionAiSuggestion suggestion) {
    setState(() {
      _aiSuggestions = _aiSuggestions
          .where((s) => s.id != suggestion.id)
          .toList();
    });
  }

  bool get _canOpenAnchoredPicker =>
      DateTime.now().millisecondsSinceEpoch >
      _anchoredPickerReopenBlockedUntilMs;

  void _blockAnchoredPickerReopen() {
    _anchoredPickerReopenBlockedUntilMs =
        DateTime.now().millisecondsSinceEpoch + 400;
  }

  Future<void> _pickCategory(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker) return;
    final choice = await showAsanaAnchoredOptionMenu<String>(
      anchorLink: _categoryAnchorLink,
      anchorContext: anchorContext,
      onClosed: _blockAnchoredPickerReopen,
      options: _categories
          .map((v) => AsanaAnchoredOption(value: v, label: v))
          .toList(),
    );
    if (choice != null && mounted) {
      setState(() => _category = choice);
    }
  }

  Future<void> _pickStatus(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker) return;
    const options = [
      AsanaAnchoredOption(value: 'Open', label: 'Open'),
      AsanaAnchoredOption(value: 'Resolved', label: 'Resolved'),
      AsanaAnchoredOption(value: 'Closed', label: 'Closed'),
    ];
    final choice = await showAsanaAnchoredOptionMenu<String>(
      anchorLink: _statusAnchorLink,
      anchorContext: anchorContext,
      onClosed: _blockAnchoredPickerReopen,
      options: options,
    );
    if (choice != null && mounted) {
      setState(() => _status = choice);
    }
  }

  Future<void> _create() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Missing content',
        content: 'Please fill in both title and content.',
        palette: widget.palette,
      );
      return;
    }
    final state = context.read<AppState>();
    final threadId = const Uuid().v4();
    final rootPostId = const Uuid().v4();
    setState(() => _saving = true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await DatabaseService.createForumThread(
        title: title,
        content: content,
        category: _category,
        status: _status,
        threadIdOverride: threadId,
        rootPostIdOverride: rootPostId,
        creatorStaffLookupKey: state.effectiveStaffAppId,
      );
      if (err != null && mounted) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not create discussion',
          content: err,
          palette: widget.palette,
        );
        return;
      }
      final inlineErr = await _commitPendingInlineImages(
        rootPostId: rootPostId,
        state: state,
      );
      if (inlineErr != null && mounted) {
        await _showInfo('Inline image upload failed', inlineErr);
        return;
      }
      widget.onCreated?.call();
      widget.onClose();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showInfo(String title, String content) async {
    if (!mounted) return;
    await showAsanaInfoDialog(
      context: context,
      title: title,
      content: content,
      palette: widget.palette,
    );
  }

  Future<void> _addDraftContentInlineImage() async {
    final picked = await pickOneFileWithBytes();
    if (!mounted || picked == null) return;
    if (picked.bytes.isEmpty) {
      await _showInfo(
        'Inline image upload failed',
        'Could not read file data.',
      );
      return;
    }
    final label = picked.name.trim().isNotEmpty ? picked.name.trim() : 'image';
    setState(
      () => _pendingInlineImageAdds.add(
        _ForumInlineImageDraft(
          id: 'draft_${DateTime.now().microsecondsSinceEpoch}',
          entityType: 'forum_post_content',
          entityId: 'draft_content',
          bytes: picked.bytes,
          label: label,
          sortOrder: _pendingInlineImageAdds
              .where(
                (draft) =>
                    draft.entityType == 'forum_post_content' &&
                    draft.entityId == 'draft_content',
              )
              .length,
        ),
      ),
    );
  }

  void _removeInlineImagePreview(InlineImagePreviewItem image) {
    setState(() {
      _pendingInlineImageAdds.removeWhere((draft) => draft.id == image.id);
    });
  }

  List<InlineImagePreviewItem> _inlinePreviewItems({
    required String entityType,
    required String entityId,
  }) {
    return _pendingInlineImageAdds
        .where(
          (draft) =>
              draft.entityType == entityType && draft.entityId == entityId,
        )
        .map(
          (draft) => InlineImagePreviewItem(
            id: draft.id,
            bytes: draft.bytes,
            description: draft.label,
            mimeType: draft.mimeType,
            canRemove: true,
          ),
        )
        .toList();
  }

  Future<String?> _commitPendingInlineImages({
    required String rootPostId,
    required AppState state,
  }) async {
    for (final draft in List<_ForumInlineImageDraft>.from(
      _pendingInlineImageAdds,
    )) {
      final upload = await AttachmentUploadService.uploadBytesForEntity(
        entityType: 'forum_post_content',
        entityId: rootPostId,
        bytes: draft.bytes,
        originalFilename: draft.label,
        aclStaffKeys: [state.effectiveStaffAppId],
      );
      if (upload.error != null) return upload.error;
      final url = upload.url?.trim();
      if (url == null || url.isEmpty) {
        return 'Inline image upload did not return a download link.';
      }
      final ins = await DatabaseService.insertInlineAttachment(
        entityType: 'forum_post_content',
        entityId: rootPostId,
        url: url,
        description: upload.label ?? draft.label,
        mimeType: draft.mimeType,
        creatorStaffLookupKey: state.effectiveStaffAppId,
        sortOrder: draft.sortOrder,
      );
      if (ins.error != null) return ins.error;
    }
    _pendingInlineImageAdds.clear();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AsanaSlideChrome(widget.palette);
    return AsanaDetailSlideScaffold(
      backgroundColor: chrome.body,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DiscussionAiDock(
            promptController: _aiPromptController,
            busy: _aiBusy,
            message: _aiMessage,
            suggestions: _aiSuggestions,
            enabled: !_saving && LlmService.isConfigured,
            palette: widget.palette,
            footerBorder: chrome.footerBorder,
            onAsk: _askAi,
            onAcceptSuggestion: _acceptAiSuggestion,
            onDismissSuggestion: _dismissAiSuggestion,
          ),
          AsanaDetailSlideFooter(
            backgroundColor: chrome.footer,
            borderColor: chrome.footerBorder,
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _create,
                style: AsanaTaskDetailActionStyles.createFilled(
                  widget.palette,
                  context: context,
                ),
                child: Text(_saving ? 'Creating' : 'Create'),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AsanaHoverTextField(
            controller: _titleController,
            canEdit: true,
            readOnly: _saving,
            maxLines: 3,
            minLines: 1,
            hintText: 'Please fill in discussion topic',
            style: asanaDetailTitleStyle(context),
          ),
          const SizedBox(height: 10),
          AsanaDetailLabelValue(
            label: 'Content',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsanaHoverTextField(
                  controller: _contentController,
                  canEdit: true,
                  readOnly: _saving,
                  showOutline: true,
                  maxLines: 12,
                  minLines: 6,
                  hintText:
                      'Share your suggestion, issue report, feature idea, or announcement details.',
                  style: asanaDetailMultilineValueStyle(context),
                ),
                InlineImageToolbar(
                  enabled: !_saving,
                  onAdd: _addDraftContentInlineImage,
                ),
                InlineImagePreviewList(
                  images: _inlinePreviewItems(
                    entityType: 'forum_post_content',
                    entityId: 'draft_content',
                  ),
                  onRemove: _removeInlineImagePreview,
                ),
              ],
            ),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Category',
            child: Builder(
              builder: (anchorContext) => CompositedTransformTarget(
                link: _categoryAnchorLink,
                child: AsanaHoverTapValue(
                  value: _category,
                  canEdit: !_saving,
                  emptyPlaceholder: 'Select category',
                  onTap: _saving ? null : (_) => _pickCategory(anchorContext),
                ),
              ),
            ),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Status',
            child: Builder(
              builder: (anchorContext) => CompositedTransformTarget(
                link: _statusAnchorLink,
                child: AsanaHoverTapValue(
                  value: _status,
                  canEdit: !_saving,
                  emptyPlaceholder: 'Select status',
                  onTap: _saving ? null : (_) => _pickStatus(anchorContext),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscussionAiDock extends StatefulWidget {
  const _DiscussionAiDock({
    required this.promptController,
    required this.busy,
    required this.message,
    required this.suggestions,
    required this.enabled,
    required this.palette,
    required this.footerBorder,
    required this.onAsk,
    required this.onAcceptSuggestion,
    required this.onDismissSuggestion,
  });

  final TextEditingController promptController;
  final bool busy;
  final String? message;
  final List<_DiscussionAiSuggestion> suggestions;
  final bool enabled;
  final AsanaLandingPalette palette;
  final Color footerBorder;
  final Future<void> Function() onAsk;
  final ValueChanged<_DiscussionAiSuggestion> onAcceptSuggestion;
  final ValueChanged<_DiscussionAiSuggestion> onDismissSuggestion;

  @override
  State<_DiscussionAiDock> createState() => _DiscussionAiDockState();
}

class _DiscussionAiDockState extends State<_DiscussionAiDock> {
  bool _expanded = false;

  Future<void> _ask() async {
    await widget.onAsk();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AsanaTaskAiColors.fromPalette(widget.palette);
    final summary = widget.message?.trim();
    return Material(
      color: colors.boxBackground,
      elevation: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: widget.footerBorder)),
        ),
        child: SafeArea(
          top: false,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI assistant',
                            style: asanaDetailValueStyle(
                              context,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          color: kAsanaTextSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_expanded && summary != null && summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      summary,
                      style: asanaDetailLabelStyle(
                        context,
                      ).copyWith(color: kAsanaTextSecondary, height: 1.35),
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_expanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Describe the forum post, then press Enter or tap Analyse. Shift+Enter adds a new line.',
                          style: asanaDetailLabelStyle(context),
                        ),
                        if (!LlmService.isConfigured) ...[
                          const SizedBox(height: 8),
                          Text(
                            'HKU IT LLM not configured. Set LOCAL_LLM_BASE_URL and LOCAL_LLM_MODEL.',
                            style: asanaDetailLabelStyle(
                              context,
                            ).copyWith(color: const Color(0xFFC62828)),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Focus(
                          onKeyEvent: (node, event) {
                            if (event is! KeyDownEvent ||
                                event.logicalKey != LogicalKeyboardKey.enter) {
                              return KeyEventResult.ignored;
                            }
                            final keys =
                                HardwareKeyboard.instance.logicalKeysPressed;
                            final shiftPressed =
                                keys.contains(LogicalKeyboardKey.shiftLeft) ||
                                keys.contains(LogicalKeyboardKey.shiftRight);
                            if (shiftPressed) return KeyEventResult.ignored;
                            if (widget.enabled && !widget.busy) _ask();
                            return KeyEventResult.handled;
                          },
                          child: TextField(
                            controller: widget.promptController,
                            readOnly: !widget.enabled,
                            minLines: 2,
                            maxLines: 6,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              labelText: 'Your prompt',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              alignLabelWithHint: true,
                              filled: true,
                              fillColor: widget.palette.listSurface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: colors.boxBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(
                                  color: colors.accent,
                                  width: 2,
                                ),
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: widget.enabled && !widget.busy
                                ? _ask
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.accent,
                              foregroundColor: widget.palette.darkChrome
                                  ? Colors.white
                                  : widget.palette.onBanner,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: widget.busy
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: widget.palette.darkChrome
                                          ? Colors.white
                                          : widget.palette.onBanner,
                                    ),
                                  )
                                : const Text('Analyse prompt'),
                          ),
                        ),
                        if (summary != null && summary.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SelectableText(
                            summary,
                            style: asanaDetailLabelStyle(context).copyWith(
                              color: kAsanaTextSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (widget.suggestions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          for (final suggestion in widget.suggestions)
                            _DiscussionAiSuggestionCard(
                              suggestion: suggestion,
                              colors: colors,
                              onAccept: () =>
                                  widget.onAcceptSuggestion(suggestion),
                              onDismiss: () =>
                                  widget.onDismissSuggestion(suggestion),
                            ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscussionAiSuggestionCard extends StatelessWidget {
  const _DiscussionAiSuggestionCard({
    required this.suggestion,
    required this.colors,
    required this.onAccept,
    required this.onDismiss,
  });

  final _DiscussionAiSuggestion suggestion;
  final AsanaTaskAiColors colors;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.boxBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.fieldLabel,
                      style: asanaDetailLabelStyle(context).copyWith(
                        color: colors.suggestedLabel,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      suggestion.suggestedValue,
                      style: asanaDetailValueStyle(
                        context,
                      ).copyWith(fontWeight: FontWeight.w500, height: 1.35),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Dismiss suggestion',
                child: IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(
                    Icons.cancel_outlined,
                    size: 20,
                    color: Color(0xFFC62828),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                ),
              ),
              Tooltip(
                message: 'Apply this suggestion',
                child: IconButton(
                  onPressed: onAccept,
                  icon: Icon(
                    Icons.check_circle_outline,
                    size: 20,
                    color: colors.adoptIcon,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
