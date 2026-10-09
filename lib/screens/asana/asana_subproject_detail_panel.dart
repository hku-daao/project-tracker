import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/postgrest_config.dart';
import '../../models/singular_comment.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/subproject_record.dart';
import '../../models/task.dart';
import '../../services/attachment_upload_service.dart';
import '../../services/database_service.dart';
import '../../utils/attachment_file_pick.dart';
import '../../utils/attachment_url_launch.dart';
import '../../utils/file_drop_region.dart';
import 'asana_inline_image_widgets.dart';
import '../../utils/hierarchy_cascade.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_assignee_field.dart';
import 'asana_assignee_picker.dart';
import 'asana_attachment_draft_tile.dart';
import 'asana_attachment_menu.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';
import 'asana_project_detail_panel.dart';
import 'asana_subproject_ai_assistant.dart';
import 'asana_task_ai_assistant.dart';
import 'asana_theme.dart';

class _SubprojectInlineImageDraft {
  _SubprojectInlineImageDraft({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.bytes,
    required this.label,
    this.mimeType = 'image/*',
    this.sortOrder = 0,
  });

  final String id;
  final String entityType;
  final String entityId;
  final Uint8List bytes;
  final String label;
  final String mimeType;
  final int sortOrder;
}

class _SubprojectAttachmentDraft {
  _SubprojectAttachmentDraft({
    this.id,
    String? url,
    String? desc,
    this.mimeType,
    this.isWebsiteLink = false,
  }) : urlController = TextEditingController(text: url ?? ''),
       descController = TextEditingController(text: desc ?? '');

  final String? id;
  final TextEditingController urlController;
  final TextEditingController descController;
  Uint8List? pendingBytes;
  String? pendingFilename;
  String? mimeType;
  bool isWebsiteLink;

  bool get isPendingFile => pendingBytes != null;

  void dispose() {
    urlController.dispose();
    descController.dispose();
  }
}

class AsanaSubprojectDetailPanel extends StatefulWidget {
  const AsanaSubprojectDetailPanel({
    super.key,
    required this.palette,
    required this.projectId,
    this.subprojectId,
    this.createMode = false,
    this.refreshToken = 0,
    required this.onClose,
    this.onCreated,
    this.onChanged,
    this.onPushCreateTask,
    this.onPushTask,
  });

  final AsanaLandingPalette palette;
  final String projectId;
  final String? subprojectId;
  final bool createMode;
  final int refreshToken;
  final VoidCallback onClose;
  final void Function(String subprojectId)? onCreated;
  final VoidCallback? onChanged;
  final VoidCallback? onPushCreateTask;
  final void Function(String taskId)? onPushTask;

  @override
  State<AsanaSubprojectDetailPanel> createState() =>
      _AsanaSubprojectDetailPanelState();
}

class _AsanaSubprojectDetailPanelState
    extends State<AsanaSubprojectDetailPanel> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _commentController = TextEditingController();
  final List<_SubprojectAttachmentDraft> _attachments = [];
  final List<ProjectCommentRowDisplay> _comments = [];
  List<InlineAttachmentRow> _descriptionInlineImages = [];
  final Map<String, List<InlineAttachmentRow>> _commentInlineImages = {};
  final List<_SubprojectInlineImageDraft> _pendingInlineImageAdds = [];
  final List<InlineAttachmentRow> _pendingInlineImageDeletes = [];
  DateTime? _startDate;
  DateTime? _endDate;
  String _draftStatus = 'Not started';
  bool _saving = false;
  bool _loading = false;
  String? _myStaffUuid;
  SubprojectRecord? _row;
  List<Task> _tasks = [];
  bool _assigneePickerLoading = false;
  String? _assigneePickerError;
  List<OfficeOptionRow> _pickerOffices = [];
  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  final Set<String> _assigneeIds = {};
  final Set<String> _picAssigneeIds = {};
  final ValueNotifier<AsanaAssigneePickerSnapshot> _assigneeSnapshot =
      ValueNotifier(const AsanaAssigneePickerSnapshot(loading: true));
  final ValueNotifier<AsanaAssigneePickerSnapshot> _picSnapshot = ValueNotifier(
    const AsanaAssigneePickerSnapshot(loading: true),
  );
  final LayerLink _assigneeAnchorLink = LayerLink();
  final LayerLink _picAnchorLink = LayerLink();
  final LayerLink _statusAnchorLink = LayerLink();
  final LayerLink _attachmentAddAnchorLink = LayerLink();
  final GlobalKey _detailPopupWidthAlignKey = GlobalKey();
  int _anchoredPickerReopenBlockedUntilMs = 0;
  AsanaTaskAiController? _subprojectAi;

  bool get _createMode => widget.createMode || widget.subprojectId == null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final lk = context.read<AppState>().userStaffAppId?.trim();
    if (lk != null && lk.isNotEmpty) {
      _myStaffUuid = await DatabaseService.staffRowIdForAssigneeKey(lk);
    }
    _loadAssigneePicker();
    if (!_createMode) {
      _hydrateFromState();
      await _loadExisting();
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant AsanaSubprojectDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subprojectId != widget.subprojectId ||
        oldWidget.projectId != widget.projectId) {
      _subprojectAi?.clearAllSuggestions();
      _bootstrap();
    } else if (oldWidget.refreshToken != widget.refreshToken && !_createMode) {
      _loadSubprojectTasks();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _commentController.dispose();
    for (final attachment in _attachments) {
      attachment.dispose();
    }
    _assigneeSnapshot.dispose();
    _picSnapshot.dispose();
    _subprojectAi?.dispose();
    super.dispose();
  }

  bool get _canOpenAnchoredPicker =>
      DateTime.now().millisecondsSinceEpoch >
      _anchoredPickerReopenBlockedUntilMs;

  void _blockAnchoredPickerReopen() {
    _anchoredPickerReopenBlockedUntilMs =
        DateTime.now().millisecondsSinceEpoch + 400;
  }

  void _hydrateFromState() {
    final id = widget.subprojectId?.trim();
    if (id == null || id.isEmpty) return;
    final row = context.read<AppState>().subprojectById(id);
    if (row == null) return;
    _applyRow(row);
  }

  void _applyRow(SubprojectRecord row) {
    _row = row;
    _nameController.text = row.name;
    _descController.text = row.description;
    _startDate = row.startDate;
    _endDate = row.endDate;
    _draftStatus = row.isPaused ? 'Paused' : row.status;
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      await DatabaseService.fetchAllSubprojects().then((rows) {
        if (!mounted) return;
        context.read<AppState>().applySubprojects(rows);
        final id = widget.subprojectId?.trim();
        final row = context.read<AppState>().subprojectById(id);
        if (row != null) {
          setState(() => _applyRow(row));
        }
      });
      await _syncAssigneeKeys();
      await _loadAttachments();
      await _loadDescriptionInlineImages();
      await _loadComments();
      await _loadSubprojectTasks();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncAssigneeKeys() async {
    final row = _row;
    if (row == null) return;
    final keys = <String>{};
    final picKeys = <String>{};
    for (final u in row.assigneeStaffUuids) {
      keys.add(await DatabaseService.assigneeListKeyFromStaffUuid(u));
    }
    for (final u in row.picStaffUuids) {
      picKeys.add(await DatabaseService.assigneeListKeyFromStaffUuid(u));
    }
    if (!mounted) return;
    setState(() {
      _assigneeIds
        ..clear()
        ..addAll(keys);
      _picAssigneeIds
        ..clear()
        ..addAll(picKeys);
    });
    _publishAssigneeSnapshots();
  }

  Future<void> _loadComments() async {
    final id = widget.subprojectId?.trim();
    if (id == null || id.isEmpty) return;
    final list = await DatabaseService.fetchSubprojectComments(id);
    if (mounted) {
      setState(() {
        _comments
          ..clear()
          ..addAll(list);
      });
      await _loadCommentInlineImages(list);
    }
  }

  Future<void> _loadDescriptionInlineImages() async {
    final id = widget.subprojectId?.trim();
    if (id == null || id.isEmpty) {
      if (mounted) setState(() => _descriptionInlineImages = []);
      return;
    }
    final list = await DatabaseService.fetchInlineAttachments(
      entityType: 'subproject_description',
      entityId: id,
    );
    if (mounted) setState(() => _descriptionInlineImages = list);
  }

  Future<void> _loadCommentInlineImages(
    List<ProjectCommentRowDisplay> comments,
  ) async {
    if (comments.isEmpty) {
      if (mounted) setState(() => _commentInlineImages.clear());
      return;
    }
    final next = <String, List<InlineAttachmentRow>>{};
    for (final comment in comments) {
      final list = await DatabaseService.fetchInlineAttachments(
        entityType: 'subproject_comment',
        entityId: comment.id,
      );
      if (list.isNotEmpty) next[comment.id] = list;
    }
    if (mounted) {
      setState(() {
        _commentInlineImages
          ..clear()
          ..addAll(next);
      });
    }
  }

  Future<void> _loadAttachments() async {
    final id = widget.subprojectId?.trim();
    if (id == null || id.isEmpty) return;
    try {
      final files = await DatabaseService.fetchFileAttachments(
        entityType: 'subproject',
        entityId: id,
      );
      final urls = await DatabaseService.fetchUrlAttachments(
        entityType: 'subproject',
        entityId: id,
      );
      if (!mounted) return;
      setState(() {
        for (final a in _attachments) {
          a.dispose();
        }
        _attachments.clear();
        for (final r in files) {
          _attachments.add(
            _SubprojectAttachmentDraft(
              id: r.id,
              url: r.url,
              desc: (r.description?.trim().isNotEmpty == true)
                  ? r.description
                  : r.filename,
              mimeType: r.mimeType,
            ),
          );
        }
        for (final r in urls) {
          _attachments.add(
            _SubprojectAttachmentDraft(
              id: r.id,
              url: r.url,
              desc: r.label,
              isWebsiteLink: true,
            ),
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _loadAssigneePicker() async {
    if (!PostgrestConfig.isConfigured) {
      _assigneePickerLoading = false;
      _assigneePickerError = 'Database not configured';
      _publishAssigneeSnapshots();
      return;
    }
    _assigneePickerLoading = true;
    _publishAssigneeSnapshots();
    try {
      final data = await DatabaseService.fetchStaffAssigneePickerData();
      if (!mounted) return;
      _assigneePickerLoading = false;
      _pickerOffices = data.offices;
      _pickerTeams = data.teams;
      _pickerStaff = data.staff;
      _assigneePickerError = null;
      _publishAssigneeSnapshots();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _assigneePickerLoading = false;
      _assigneePickerError = e.toString();
      _publishAssigneeSnapshots();
      setState(() {});
    }
  }

  void _publishAssigneeSnapshots() {
    _assigneeSnapshot.value = AsanaAssigneePickerSnapshot(
      loading: _assigneePickerLoading,
      offices: _pickerOffices,
      teams: _pickerTeams,
      staff: List<StaffForAssignment>.from(_pickerStaff),
      error: _assigneePickerError,
    );
    _picSnapshot.value = AsanaAssigneePickerSnapshot(
      loading: _assigneePickerLoading,
      offices: _pickerOffices,
      teams: _pickerTeams,
      staff: List<StaffForAssignment>.from(_pickerStaff),
      error: _assigneePickerError,
    );
  }

  String _labelForAssigneeId(String id, AppState state) {
    for (final s in _pickerStaff) {
      if (s.assigneeId == id) return s.name.trim();
    }
    final a = state.assigneeById(id);
    if (a != null && a.name.trim().isNotEmpty) return a.name.trim();
    return id;
  }

  List<({String id, String name})> _rowsForIds(
    Set<String> ids,
    AppState state,
  ) {
    return ids
        .map((id) => (id: id, name: _labelForAssigneeId(id, state)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Set<String> _visibleAssigneeIdsForPicker() {
    return _assigneeIds
        .where((id) => !_picAssigneeIds.contains(id.trim()))
        .toSet();
  }

  List<String> _effectiveAssigneeIdsForSave() {
    final ids = <String>{};
    for (final raw in _assigneeIds) {
      final id = raw.trim();
      if (id.isNotEmpty) ids.add(id);
    }
    for (final raw in _picAssigneeIds) {
      final id = raw.trim();
      if (id.isNotEmpty) ids.add(id);
    }
    return ids.toList();
  }

  Future<void> _pickAssignees(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker || _saving) return;
    if (_assigneePickerLoading || !_assigneeSnapshot.value.hasData) {
      await _loadAssigneePicker();
    }
    if (!mounted || !_assigneeSnapshot.value.hasData) {
      await _showInfo(
        'Could not load teammates',
        _assigneePickerError ?? 'Please try again in a moment.',
      );
      return;
    }
    await showAsanaAssigneePicker(
      anchorLink: _assigneeAnchorLink,
      anchorContext: anchorContext,
      snapshot: _assigneeSnapshot,
      selectedIds: _visibleAssigneeIdsForPicker(),
      whenClosed: _blockAnchoredPickerReopen,
      onSelectionChanged: (s) {
        if (!mounted) return;
        setState(() {
          _assigneeIds
            ..clear()
            ..addAll(s)
            ..addAll(_picAssigneeIds);
        });
      },
    );
  }

  Future<void> _pickPics(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker || _saving) return;
    if (_assigneePickerLoading || !_picSnapshot.value.hasData) {
      await _loadAssigneePicker();
    }
    if (!mounted || !_picSnapshot.value.hasData) {
      await _showInfo(
        'Could not load teammates',
        _assigneePickerError ?? 'Please try again in a moment.',
      );
      return;
    }
    await showAsanaAssigneePicker(
      anchorLink: _picAnchorLink,
      anchorContext: anchorContext,
      snapshot: _picSnapshot,
      selectedIds: _picAssigneeIds,
      whenClosed: _blockAnchoredPickerReopen,
      onSelectionChanged: (s) {
        if (!mounted) return;
        setState(() {
          for (final id in _picAssigneeIds) {
            _assigneeIds.remove(id);
          }
          _picAssigneeIds
            ..clear()
            ..addAll(s);
          _assigneeIds.addAll(_picAssigneeIds);
        });
      },
    );
  }

  Future<void> _pickStatus(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker || _saving) return;
    const options = [
      AsanaAnchoredOption(value: 'Not started', label: 'Not started'),
      AsanaAnchoredOption(value: 'In progress', label: 'In progress'),
      AsanaAnchoredOption(value: 'Completed', label: 'Completed'),
    ];
    final choice = await showAsanaAnchoredOptionMenu<String>(
      anchorLink: _statusAnchorLink,
      anchorContext: anchorContext,
      onClosed: _blockAnchoredPickerReopen,
      options: options,
    );
    if (choice != null && mounted) {
      setState(() => _draftStatus = choice);
    }
  }

  Future<void> _pickStartDate(BuildContext anchorContext) async {
    final picked = await showAsanaAnchoredSingleDatePicker(
      anchorContext: anchorContext,
      initialDate: _startDate ?? HkTime.todayDateOnlyHk(),
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = picked);
  }

  Future<void> _pickDueDate(BuildContext anchorContext) async {
    final picked = await showAsanaAnchoredSingleDatePicker(
      anchorContext: anchorContext,
      initialDate: _endDate ?? _startDate ?? HkTime.todayDateOnlyHk(),
    );
    if (picked == null || !mounted) return;
    setState(() => _endDate = picked);
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
  }

  Future<void> _showInfo(String title, String content) {
    AsanaBlockingLoadingOverlay.hideAll();
    if (mounted && _saving) setState(() => _saving = false);
    return showAsanaInfoDialog(
      context: context,
      title: title,
      content: content,
      palette: widget.palette,
    );
  }

  bool _isParentProjectMember(AppState state) {
    final project = state.projectById(widget.projectId);
    if (project == null) return false;
    return project.isInvolvedStaff(
      staffUuid: _myStaffUuid ?? state.effectiveStaffUuid,
      staffAppId: state.userStaffAppId,
    );
  }

  bool _isSubprojectMember(AppState state) {
    final row = _row;
    if (row == null) return false;
    return row.isInvolvedStaff(
      staffUuid: _myStaffUuid ?? state.effectiveStaffUuid,
      staffAppId: state.userStaffAppId,
    );
  }

  Future<void> _loadSubprojectTasks() async {
    final sid = widget.subprojectId?.trim();
    if (sid == null || sid.isEmpty || !PostgrestConfig.isConfigured) return;
    try {
      final list = await DatabaseService.fetchSingularTasksForProject(
        widget.projectId,
      );
      if (!mounted) return;
      final visible = list.where((t) {
        if (_childTaskStatusRank(t) >= 2) return false;
        return t.subprojectId?.trim() == sid;
      }).toList();
      _sortChildTasksForDetail(visible);
      setState(() => _tasks = visible);
    } catch (_) {}
  }

  bool _taskDeleted(Task t) {
    final s = (t.dbStatus ?? '').trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  bool _taskCompleted(Task t) {
    final s = (t.dbStatus ?? '').trim().toLowerCase();
    return s == 'completed' || s == 'complete' || t.status == TaskStatus.done;
  }

  String _taskStatusLabel(Task t) {
    if (_taskDeleted(t)) return 'Deleted';
    final project = context.read<AppState>().projectById(widget.projectId);
    if ((_row?.isPaused ?? false) ||
        (project?.isPaused ?? false) ||
        t.isPaused) {
      return 'Paused';
    }
    final raw = t.dbStatus?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return taskStatusDisplayNames[t.status] ?? 'Incomplete';
  }

  void _sortChildTasksForDetail(List<Task> list) {
    list.sort((a, b) {
      final status = _childTaskStatusRank(a).compareTo(_childTaskStatusRank(b));
      if (status != 0) return status;
      final due = _compareNullableDueDates(a.endDate, b.endDate);
      if (due != 0) return due;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  int _childTaskStatusRank(Task task) {
    if (_taskDeleted(task)) return 3;
    final status = _taskStatusLabel(task).trim().toLowerCase();
    if (status == 'completed' || status == 'complete') return 1;
    if (status == 'paused') return 2;
    return 0;
  }

  int _compareNullableDueDates(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return DateUtils.dateOnly(a).compareTo(DateUtils.dateOnly(b));
  }

  String _formatShortDate(DateTime? d) {
    if (d == null) return '—';
    final today = HkTime.todayDateOnlyHk();
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today';
    return HkTime.formatInstantAsHk(d, 'MMM d');
  }

  bool _draftShowsAsWebsiteLink(_SubprojectAttachmentDraft draft) {
    if (draft.isPendingFile) return false;
    if (draft.isWebsiteLink) return true;
    final url = draft.urlController.text.trim();
    return url.isNotEmpty && !isUploadedFileAttachmentUrl(url);
  }

  String? _attachmentMimeTypeFromName(String? name) {
    final n = name?.toLowerCase().trim() ?? '';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    return null;
  }

  bool _attachmentDraftIsImage(_SubprojectAttachmentDraft draft) {
    final mime = draft.mimeType?.toLowerCase().trim() ?? '';
    if (mime.startsWith('image/')) return true;
    final name = draft.pendingFilename?.trim().isNotEmpty == true
        ? draft.pendingFilename!.trim()
        : draft.descController.text.trim();
    return _attachmentMimeTypeFromName(name) != null;
  }

  List<String?> _attachmentAclKeys(AppState state) {
    return [state.userStaffAppId, ..._picAssigneeIds, ..._assigneeIds];
  }

  String get _descriptionInlineEntityId =>
      _createMode ? 'draft_description' : (widget.subprojectId?.trim() ?? '');

  Future<void> _stageInlineImage({
    required String entityType,
    required String entityId,
    List<PickedFileBytes>? files,
    int rejectedNonImages = 0,
  }) async {
    if (stateAdminBlocked()) return;
    final resolved = await resolveInlineImageFiles(
      dropped: files,
      rejectedNonImages: rejectedNonImages,
    );
    if (!mounted) return;
    if (resolved.error != null) {
      await _showInfo('Inline image upload failed', resolved.error!);
      return;
    }
    if (resolved.files.isEmpty) return;
    setState(() {
      var order = _pendingInlineImageAdds
          .where(
            (draft) =>
                draft.entityType == entityType && draft.entityId == entityId,
          )
          .length;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      for (final file in resolved.files) {
        final label = file.name.trim().isNotEmpty ? file.name.trim() : 'image';
        _pendingInlineImageAdds.add(
          _SubprojectInlineImageDraft(
            id: 'draft_${stamp}_$order',
            entityType: entityType,
            entityId: entityId,
            bytes: file.bytes,
            label: label,
            sortOrder: order,
          ),
        );
        order++;
      }
    });
    if (resolved.warning != null && mounted) {
      await _showInfo('Inline image', resolved.warning!);
    }
  }

  bool stateAdminBlocked() => context.read<AppState>().adminViewMode;

  void _removeInlineImagePreview(InlineImagePreviewItem image) {
    if (context.read<AppState>().adminViewMode) return;
    setState(() {
      final saved = image.inlineAttachment;
      if (saved != null) {
        if (!_pendingInlineImageDeletes.any((row) => row.id == saved.id)) {
          _pendingInlineImageDeletes.add(saved);
        }
      } else {
        _pendingInlineImageAdds.removeWhere((draft) => draft.id == image.id);
      }
    });
  }

  List<InlineImagePreviewItem> _inlinePreviewItems({
    required String entityType,
    required String entityId,
    required List<InlineAttachmentRow> saved,
  }) {
    final deletedIds = _pendingInlineImageDeletes.map((row) => row.id).toSet();
    final savedItems = saved
        .where((row) => !deletedIds.contains(row.id))
        .map(
          (row) => InlineImagePreviewItem(
            id: row.id,
            inlineAttachment: row,
            url: row.url,
            description: row.description,
            mimeType: row.mimeType,
            canRemove: true,
          ),
        );
    final draftItems = _pendingInlineImageAdds
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
        );
    return [...savedItems, ...draftItems];
  }

  Future<String?> _commitPendingInlineImages({
    required String subprojectId,
    required AppState state,
    Map<String, String> entityIdOverrides = const {},
  }) async {
    for (final draft in List<_SubprojectInlineImageDraft>.from(
      _pendingInlineImageAdds,
    )) {
      final resolvedEntityId =
          entityIdOverrides[draft.entityId] ?? draft.entityId;
      if (resolvedEntityId.trim().isEmpty ||
          resolvedEntityId == 'draft' ||
          resolvedEntityId == 'draft_description') {
        continue;
      }
      final upload = await AttachmentUploadService.uploadBytesForSubproject(
        subprojectId,
        bytes: draft.bytes,
        originalFilename: draft.label,
        aclStaffKeys: _attachmentAclKeys(state),
      );
      if (upload.error != null) return upload.error;
      final url = upload.url?.trim();
      if (url == null || url.isEmpty) {
        return 'Inline image upload did not return a download link.';
      }
      final ins = await DatabaseService.insertInlineAttachment(
        entityType: draft.entityType,
        entityId: resolvedEntityId,
        url: url,
        description: upload.label ?? draft.label,
        mimeType: draft.mimeType,
        creatorStaffLookupKey: state.userStaffAppId,
        sortOrder: draft.sortOrder,
      );
      if (ins.error != null) return ins.error;
    }
    for (final row in List<InlineAttachmentRow>.from(
      _pendingInlineImageDeletes,
    )) {
      final deleteErr = await AttachmentUploadService.deleteUploadedObjectByUrl(
        row.url,
      );
      if (deleteErr != null) return deleteErr;
      final markErr = await DatabaseService.markInlineAttachmentDeleted(row.id);
      if (markErr != null) return markErr;
    }
    _pendingInlineImageAdds.clear();
    _pendingInlineImageDeletes.clear();
    return null;
  }

  Future<String?> _insertDraftComment(String subprojectId, AppState state) async {
    final text = stripInlineImageMarkers(_commentController.text);
    final hasImages = _pendingInlineImageAdds.any(
      (draft) =>
          draft.entityType == 'subproject_comment' && draft.entityId == 'draft',
    );
    if (text.isEmpty && !hasImages) return null;
    final c = await DatabaseService.insertSubprojectCommentRow(
      subprojectId: subprojectId,
      description: text.isNotEmpty ? text : inlineImageOnlyCommentPlaceholder,
      creatorStaffLookupKey: state.userStaffAppId,
    );
    if (c.error != null) {
      await _showInfo('Could not add comment', c.error!);
      return null;
    }
    final commentId = c.commentId;
    if (commentId == null || commentId.isEmpty) {
      await _showInfo(
        'Could not add comment',
        'The comment was not saved because the database did not return a comment id.',
      );
      return null;
    }
    _commentController.clear();
    return commentId;
  }

  Future<void> _addFileAttachment({List<PickedFileBytes>? dropped}) async {
    late final List<({Uint8List bytes, String label})> files;
    if (dropped != null) {
      if (dropped.isEmpty) return;
      files = [];
      for (final file in dropped) {
        final label = file.name.trim().isEmpty ? 'attachment' : file.name.trim();
        final sizeError = AttachmentUploadService.uploadSizeError(
          file.bytes.length,
          label,
        );
        if (sizeError != null) {
          await _showInfo('Attachment upload failed', sizeError);
          return;
        }
        files.add((bytes: file.bytes, label: label));
      }
    } else {
      final picked = await AttachmentUploadService.pickFilesForUpload(
        allowMultiple: true,
      );
      if (!mounted) return;
      if (picked.error != null) {
        await _showInfo('Attachment upload failed', picked.error!);
        return;
      }
      files = picked.files;
    }
    if (files.isEmpty) return;
    setState(() {
      for (final file in files) {
        final draft = _SubprojectAttachmentDraft(
          desc: file.label,
          mimeType: _attachmentMimeTypeFromName(file.label),
        );
        draft.pendingBytes = file.bytes;
        draft.pendingFilename = file.label;
        _attachments.add(draft);
      }
    });
  }

  Future<void> _addUrlAttachment(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker || _saving) return;
    final result = await showAsanaAnchoredLinkEditor(
      anchorLink: _attachmentAddAnchorLink,
      anchorContext: anchorContext,
      widthAlignContext:
          _detailPopupWidthAlignKey.currentContext ?? anchorContext,
      initialUrl: '',
      initialDescription: '',
      onClosed: _blockAnchoredPickerReopen,
    );
    if (!mounted || result == null) return;
    setState(() {
      _attachments.add(
        _SubprojectAttachmentDraft(
          url: result.url,
          desc: result.description,
          isWebsiteLink: true,
        ),
      );
    });
  }

  Future<void> _editAttachmentLink(
    BuildContext anchorContext,
    _SubprojectAttachmentDraft draft,
  ) async {
    if (!_canOpenAnchoredPicker || _saving) return;
    final updated = await showAsanaAnchoredLinkEditor(
      anchorLink: _attachmentAddAnchorLink,
      anchorContext: anchorContext,
      widthAlignContext:
          _detailPopupWidthAlignKey.currentContext ?? anchorContext,
      initialUrl: draft.urlController.text,
      initialDescription: draft.descController.text,
      onClosed: _blockAnchoredPickerReopen,
    );
    if (!mounted || updated == null) return;
    setState(() {
      draft.urlController.text = updated.url;
      draft.descController.text = updated.description;
      draft.isWebsiteLink = true;
    });
  }

  void _removeAttachmentDraft(_SubprojectAttachmentDraft draft) {
    setState(() {
      draft.dispose();
      _attachments.remove(draft);
    });
  }

  List<_SubprojectAttachmentDraft> get _fileAttachments => _attachments
      .where((a) => a.isPendingFile || !_draftShowsAsWebsiteLink(a))
      .toList();

  List<_SubprojectAttachmentDraft> get _urlAttachments => _attachments
      .where((a) => !a.isPendingFile && _draftShowsAsWebsiteLink(a))
      .toList();

  Future<String?> _uploadPendingFiles(
    String subprojectId,
    AppState state,
  ) async {
    for (final draft in _attachments) {
      if (!draft.isPendingFile) continue;
      final upload = await AttachmentUploadService.uploadBytesForSubproject(
        subprojectId,
        bytes: draft.pendingBytes!,
        originalFilename: draft.pendingFilename ?? 'attachment',
        aclStaffKeys: _attachmentAclKeys(state),
      );
      if (upload.error != null) return upload.error;
      final url = upload.url?.trim();
      if (url == null || url.isEmpty) {
        return 'File upload did not return a download link.';
      }
      draft.urlController.text = url;
      draft.pendingBytes = null;
      draft.pendingFilename = null;
    }
    return null;
  }

  Future<String?> _replaceAttachments(String subprojectId) async {
    final files = _attachments
        .where((a) => !a.isPendingFile && !_draftShowsAsWebsiteLink(a))
        .map((a) {
          final url = a.urlController.text.trim();
          final desc = a.descController.text.trim();
          return (
            id: a.id,
            url: url.isEmpty ? null : url,
            filename: desc.isEmpty ? null : desc,
            description: desc.isEmpty ? null : desc,
          );
        })
        .where((r) => (r.url ?? '').isNotEmpty)
        .toList();
    final urls = _attachments
        .where((a) => !a.isPendingFile && _draftShowsAsWebsiteLink(a))
        .map((a) {
          final url = a.urlController.text.trim();
          final desc = a.descController.text.trim();
          return (
            id: a.id,
            url: url.isEmpty ? null : url,
            label: desc.isEmpty ? url : desc,
          );
        })
        .where((r) => (r.url ?? '').isNotEmpty)
        .toList();
    final fileErr = await DatabaseService.replaceFileAttachments(
      entityType: 'subproject',
      entityId: subprojectId,
      rows: files,
    );
    if (fileErr != null) return fileErr;
    return DatabaseService.replaceUrlAttachments(
      entityType: 'subproject',
      entityId: subprojectId,
      rows: urls,
    );
  }

  Future<bool> _validate(AppState state) async {
    if (state.adminViewMode) {
      await _showInfo('Admin View', 'Admin View is read-only.');
      return false;
    }
    if (!PostgrestConfig.isConfigured) {
      await _showInfo(
        'Database not configured',
        'Please configure the database API before continuing.',
      );
      return false;
    }
    if (_nameController.text.trim().isEmpty) {
      await _showInfo(
        'Sub-project name required',
        'Please fill in the sub-project name before continuing.',
      );
      return false;
    }
    if (_effectiveAssigneeIdsForSave().isEmpty) {
      await _showInfo('Assignee required', 'Select at least one assignee.');
      return false;
    }
    if (_effectiveAssigneeIdsForSave().length >
        DatabaseService.projectAssigneeSlotCount) {
      await _showInfo(
        'Too many assignees',
        'Select no more than ${DatabaseService.projectAssigneeSlotCount} assignees.',
      );
      return false;
    }
    if (_picAssigneeIds.isEmpty) {
      await _showInfo('PIC required', 'Select at least one PIC.');
      return false;
    }
    if (_picAssigneeIds.length > DatabaseService.projectPicSlotCount) {
      await _showInfo(
        'Too many PICs',
        'Select no more than ${DatabaseService.projectPicSlotCount} PICs.',
      );
      return false;
    }
    if (_createMode && !_isParentProjectMember(state)) {
      await _showInfo(
        'Not allowed',
        'Only the project creator, assignees, or PIC can create a sub-project.',
      );
      return false;
    }
    return true;
  }

  Future<void> _create(AppState state) async {
    if (!await _validate(state)) return;
    setState(() => _saving = true);
    await AsanaBlockingLoadingOverlay.showAfterFrame(context);
    try {
      final slots = await DatabaseService.assigneeSlotsForProject(
        _effectiveAssigneeIdsForSave(),
      );
      final picUuids = <String>[];
      for (final key in _picAssigneeIds) {
        final u = await DatabaseService.resolveStaffRowIdForAssigneeKey(key);
        if (u != null && u.trim().isNotEmpty) picUuids.add(u.trim());
      }
      final ins = await DatabaseService.insertSubprojectRow(
        projectId: widget.projectId,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        status: _draftStatus,
        startDate: _startDate,
        endDate: _endDate,
        assignees: slots,
        picStaffUuids: picUuids,
        creatorStaffLookupKey: state.userStaffAppId,
      );
      if (ins.error != null) {
        await _showInfo('Could not create sub-project', ins.error!);
        return;
      }
      final newId = ins.subprojectId;
      _subprojectAi?.attachCreatedEntityId(newId ?? '');
      if (newId == null || newId.isEmpty) {
        await _showInfo(
          'Could not create sub-project',
          'The database did not return a sub-project id.',
        );
        return;
      }
      final uploadErr = await _uploadPendingFiles(newId, state);
      if (uploadErr != null) {
        await _showInfo('Sub-project saved, attachments failed', uploadErr);
      } else {
        final attachErr = await _replaceAttachments(newId);
        if (attachErr != null) {
          await _showInfo('Sub-project saved, attachments failed', attachErr);
        }
      }
      final commentId = await _insertDraftComment(newId, state);
      final hasDraftComment = _pendingInlineImageAdds.any(
        (draft) =>
            draft.entityType == 'subproject_comment' &&
            draft.entityId == 'draft',
      );
      if (hasDraftComment && commentId == null) return;
      final inlineErr = await _commitPendingInlineImages(
        subprojectId: newId,
        state: state,
        entityIdOverrides: {
          'draft_description': newId,
          if (commentId != null) 'draft': commentId,
        },
      );
      if (inlineErr != null) {
        await _showInfo('Could not save inline image', inlineErr);
      }
      state.applySubprojects(await DatabaseService.fetchAllSubprojects());
      _subprojectAi?.clearAllSuggestions();
      widget.onCreated?.call(newId);
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save(AppState state) async {
    final id = widget.subprojectId?.trim();
    if (id == null || id.isEmpty) return;
    if (!await _validate(state)) return;
    final becomingCompleted =
        _draftStatus == 'Completed' && _row?.isCompleted != true;
    if (becomingCompleted &&
        !await _confirmSubprojectCascade(id, HierarchyCascadeAction.complete)) {
      return;
    }
    setState(() => _saving = true);
    await AsanaBlockingLoadingOverlay.showAfterFrame(context);
    try {
      final slots = await DatabaseService.assigneeSlotsForProject(
        _effectiveAssigneeIdsForSave(),
      );
      final picUuids = <String>[];
      for (final key in _picAssigneeIds) {
        final u = await DatabaseService.resolveStaffRowIdForAssigneeKey(key);
        if (u != null && u.trim().isNotEmpty) picUuids.add(u.trim());
      }
      final err = await DatabaseService.updateSubprojectRow(
        subprojectId: id,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        status: _draftStatus == 'Paused' ? _row?.status : _draftStatus,
        startDate: _startDate,
        endDate: _endDate,
        clearStartDate: _startDate == null,
        clearEndDate: _endDate == null,
        assigneeSlots: slots,
        picStaffUuids: picUuids,
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (err != null) {
        await _showInfo('Could not update sub-project', err);
        return;
      }
      final uploadErr = await _uploadPendingFiles(id, state);
      if (uploadErr != null) {
        await _showInfo('Sub-project saved, attachments failed', uploadErr);
      } else {
        final attachErr = await _replaceAttachments(id);
        if (attachErr != null) {
          await _showInfo('Sub-project saved, attachments failed', attachErr);
        }
      }
      final commentId = await _insertDraftComment(id, state);
      final hasDraftComment = _pendingInlineImageAdds.any(
        (draft) =>
            draft.entityType == 'subproject_comment' &&
            draft.entityId == 'draft',
      );
      if (hasDraftComment && commentId == null) return;
      final inlineErr = await _commitPendingInlineImages(
        subprojectId: id,
        state: state,
        entityIdOverrides: commentId == null
            ? const {}
            : {'draft': commentId},
      );
      if (inlineErr != null) {
        await _showInfo('Could not save inline image', inlineErr);
        return;
      }
      state.applySubprojects(await DatabaseService.fetchAllSubprojects());
      await _loadDescriptionInlineImages();
      await _loadComments();
      _subprojectAi?.clearAllSuggestions();
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmSubprojectCascade(
    String id,
    HierarchyCascadeAction action,
  ) async {
    final counts = await DatabaseService.countCascadeForSubproject(
      subprojectId: id,
      action: action,
    );
    if (!mounted) return false;
    return confirmHierarchyCascadeIfNeeded(
      context: context,
      palette: widget.palette,
      action: action,
      parentKind: 'sub-project',
      counts: counts,
    );
  }

  Future<void> _setPause(AppState state, {required bool paused}) async {
    final id = widget.subprojectId?.trim();
    if (id == null || id.isEmpty) return;
    if (!await _confirmSubprojectCascade(
      id,
      paused ? HierarchyCascadeAction.pause : HierarchyCascadeAction.resume,
    )) {
      return;
    }
    setState(() => _saving = true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await DatabaseService.updateSubprojectRow(
        subprojectId: id,
        updatePauseStatus: true,
        pauseStatus: paused ? 'Paused' : 'Not Paused',
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (err != null) {
        await _showInfo(
          paused ? 'Could not pause sub-project' : 'Could not resume',
          err,
        );
        return;
      }
      state.applySubprojects(await DatabaseService.fetchAllSubprojects());
      await _loadExisting();
      _subprojectAi?.clearAllSuggestions();
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(AppState state) async {
    final id = widget.subprojectId?.trim();
    if (id == null || id.isEmpty) return;
    final counts = await DatabaseService.countCascadeForSubproject(
      subprojectId: id,
      action: HierarchyCascadeAction.delete,
    );
    if (!mounted) return;
    final ok = counts.hasChanges
        ? await confirmHierarchyCascadeIfNeeded(
            context: context,
            palette: widget.palette,
            action: HierarchyCascadeAction.delete,
            parentKind: 'sub-project',
            counts: counts,
          )
        : await showAsanaConfirmDialog(
            context: context,
            title: 'Remove sub-project',
            content: 'Remove "${_nameController.text.trim()}"?',
            confirmText: 'Remove',
            isDestructive: true,
            palette: widget.palette,
          );
    if (ok != true) return;
    setState(() => _saving = true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await DatabaseService.deleteSubprojectRow(
        subprojectId: id,
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (err != null) {
        await _showInfo('Could not remove sub-project', err);
        return;
      }
      state.applySubprojects(await DatabaseService.fetchAllSubprojects());
      widget.onChanged?.call();
      widget.onClose();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restore(AppState state) async {
    final id = widget.subprojectId?.trim();
    if (id == null || id.isEmpty) return;
    if (state.adminViewMode) {
      await _showInfo('Admin View', 'Admin View is read-only.');
      return;
    }
    if (!await _confirmSubprojectCascade(id, HierarchyCascadeAction.restore)) {
      return;
    }
    setState(() => _saving = true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await DatabaseService.updateSubprojectRow(
        subprojectId: id,
        status: 'Not started',
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (err != null) {
        await _showInfo('Could not restore sub-project', err);
        return;
      }
      final cascadeErr =
          await DatabaseService.markTasksAndSubtasksRestoredForSubproject(
            subprojectId: id,
            updateByStaffLookupKey: state.userStaffAppId,
          );
      if (cascadeErr != null) {
        await _showInfo(
          'Sub-project restored, but child items were not fully restored',
          cascadeErr,
        );
        return;
      }
      state.applySubprojects(await DatabaseService.fetchAllSubprojects());
      await _loadExisting();
      await _loadSubprojectTasks();
      _subprojectAi?.clearAllSuggestions();
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  String _buildParentProjectContext(AppState state) {
    final project = state.projectById(widget.projectId);
    if (project == null) return '';
    String ymd(DateTime? d) {
      if (d == null) return '(empty)';
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    final assignees = project.assigneeStaffDisplayNames
        .where((n) => n.trim().isNotEmpty)
        .join(', ');
    final pics = project.picStaffDisplayNames
        .where((n) => n.trim().isNotEmpty)
        .join(', ');
    final description = project.description.trim();
    return '''
Name: ${project.name.trim().isEmpty ? '(empty)' : project.name.trim()}
Description: ${description.isEmpty ? '(empty)' : description}
Status: ${project.isPaused ? 'Paused' : project.status}
Start date: ${ymd(project.startDate)}
Due date: ${ymd(project.endDate)}
Assignees: ${assignees.isEmpty ? '(none)' : assignees}
PIC: ${pics.isEmpty ? '(none)' : pics}
''';
  }

  List<({String url, String description})> _websiteAttachmentsForAi() {
    return _attachments
        .where((a) => !a.isPendingFile && _draftShowsAsWebsiteLink(a))
        .map(
          (a) => (
            url: a.urlController.text.trim(),
            description: a.descController.text.trim(),
          ),
        )
        .where((a) => a.url.isNotEmpty)
        .toList();
  }

  AsanaSubprojectAiFormSnapshot _aiFormSnapshot(AppState state) {
    final assigneesLabel = _visibleAssigneeIdsForPicker()
        .map((id) => _labelForAssigneeId(id, state))
        .join(', ');
    final picLabel = _picAssigneeIds
        .map((id) => _labelForAssigneeId(id, state))
        .join(', ');
    final staff = _pickerStaff
        .map((s) => (id: s.assigneeId, name: s.name.trim()))
        .where((s) => s.name.isNotEmpty)
        .toList();
    final paused = _row?.isPaused == true;
    return AsanaSubprojectAiFormSnapshot(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      commentDraft: _commentController.text.trim(),
      status: paused ? 'Paused' : _draftStatus,
      startDate: _startDate,
      dueDate: _endDate,
      assigneesLabel: assigneesLabel,
      picLabel: picLabel,
      staff: staff,
      selectedAssigneeIds: _visibleAssigneeIdsForPicker(),
      selectedPicAssigneeIds: Set<String>.from(_picAssigneeIds),
      websiteAttachments: _websiteAttachmentsForAi(),
      parentProjectContext: _buildParentProjectContext(state),
      statusLocked: paused,
    );
  }

  AsanaSubprojectAiApply _aiApplyHandlers() {
    return AsanaSubprojectAiApply(
      applyName: (v) => setState(() => _nameController.text = v),
      applyDescription: (v) => setState(() => _descController.text = v),
      applyAssignees: (ids) => setState(() {
        _assigneeIds
          ..clear()
          ..addAll(ids)
          ..addAll(_picAssigneeIds);
      }),
      applyPic: (ids) => setState(() {
        for (final id in _picAssigneeIds) {
          _assigneeIds.remove(id);
        }
        _picAssigneeIds
          ..clear()
          ..addAll(ids);
        _assigneeIds.addAll(_picAssigneeIds);
      }),
      applyStatus: (s) => setState(() => _draftStatus = s),
      applyStartDate: (d) => setState(() => _startDate = d),
      applyDueDate: (d) => setState(() => _endDate = d),
      applyComment: (v) => setState(() => _commentController.text = v),
      applyWebsiteLink: (url, desc) => setState(() {
        _attachments.add(
          _SubprojectAttachmentDraft(url: url, desc: desc, isWebsiteLink: true),
        );
      }),
    );
  }

  void _ensureSubprojectAi(AppState state) {
    _subprojectAi ??= AsanaTaskAiController(
      mode: AsanaTaskAiAssistantMode.subprojectFields,
      readOnly: () => _saving,
      auditContext: () {
        final current = context.read<AppState>();
        return AsanaAiAuditContext(
          entityType: 'subproject',
          entityId: _createMode ? null : widget.subprojectId,
          staffId: current.userStaffId,
          staffDisplayName: _labelForAssigneeId(
            current.userStaffAppId ?? '',
            current,
          ),
          actionType: _createMode ? 'create' : 'update',
        );
      },
      subprojectSnapshot: () => _aiFormSnapshot(context.read<AppState>()),
      subprojectApply: _aiApplyHandlers(),
    );
  }

  Widget _aiSuggestions(AsanaTaskAiFieldKey key) {
    final c = _subprojectAi;
    if (c == null) return const SizedBox.shrink();
    return AsanaTaskAiInlineSuggestions(
      controller: c,
      fieldKey: key,
      palette: widget.palette,
    );
  }

  Widget _footer(AppState state, bool canEdit) {
    final chrome = AsanaSlideChrome(widget.palette);
    if (!canEdit) return const SizedBox.shrink();
    final Widget actions;
    if (_createMode) {
      actions = AsanaDetailSlideFooter(
        backgroundColor: chrome.footer,
        borderColor: chrome.footerBorder,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: _saving ? null : () => _create(state),
              style: FilledButton.styleFrom(
                backgroundColor: widget.palette.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text(_saving ? 'Creating…' : 'Create'),
            ),
          ],
        ),
      );
    } else {
      final row = _row;
      final deleted = row?.isDeleted == true;
      final buttons = <Widget>[
        if (!deleted)
          FilledButton(
            onPressed: _saving ? null : () => _save(state),
            style: AsanaTaskDetailActionStyles.updateFilled(
              widget.palette,
              context: context,
            ),
            child: Text(_saving ? 'Saving' : 'Update'),
          ),
      ];
      if (row != null && !row.isDeleted && !row.isPaused && !row.isCompleted) {
        buttons.add(
          OutlinedButton(
            onPressed: _saving ? null : () => _setPause(state, paused: true),
            style: AsanaTaskDetailActionStyles.pauseOutlined(context: context),
            child: const Text('Pause'),
          ),
        );
      }
      if (row != null && !row.isDeleted && row.isPaused) {
        buttons.add(
          OutlinedButton(
            onPressed: _saving ? null : () => _setPause(state, paused: false),
            style: AsanaTaskDetailActionStyles.resumeOutlined(context: context),
            child: const Text('Resume'),
          ),
        );
      }
      if (row != null && !row.isDeleted) {
        buttons.add(
          FilledButton(
            onPressed: _saving ? null : () => _delete(state),
            style: AsanaTaskDetailActionStyles.deleteFilled(context: context),
            child: const Text('Delete'),
          ),
        );
      }
      if (row != null && row.isDeleted) {
        buttons.add(
          OutlinedButton(
            onPressed: _saving ? null : () => _restore(state),
            style: AsanaTaskDetailActionStyles.undoOutlined(
              widget.palette,
              context: context,
            ),
            child: const Text('Restore to Not started'),
          ),
        );
      }
      actions = AsanaDetailSlideFooter(
        backgroundColor: chrome.footer,
        borderColor: chrome.footerBorder,
        child: Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: buttons,
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_subprojectAi != null)
          AsanaTaskAiDock(
            controller: _subprojectAi!,
            palette: widget.palette,
            footerBorder: chrome.footerBorder,
          ),
        actions,
      ],
    );
  }

  Widget _attachmentTwoColumnRow({
    required String label,
    required List<_SubprojectAttachmentDraft> attachments,
    required String addTooltip,
    required void Function(BuildContext buttonContext)? onAdd,
    void Function(List<PickedFileBytes> files)? onDropFiles,
    LayerLink? addAnchorLink,
    BuildContext? editAnchorContext,
    required bool canEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 600
                ? kAsanaDetailLabelColumnWidth / 2
                : kAsanaDetailLabelColumnWidth,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(label, style: asanaDetailLabelStyle(context)),
                ),
                if (canEdit) ...[
                  const SizedBox(width: 8),
                  AsanaDetailCircleAddButton(
                    onTap: onAdd,
                    enabled: onAdd != null && !_saving,
                    tooltip: addTooltip,
                    size: 22,
                    anchorLink: addAnchorLink,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: asanaAttachmentValuesWithFileDrop(
              enabled: canEdit && !_saving,
              onDropFiles: onDropFiles,
              child: attachments.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        for (final draft in attachments)
                          _attachmentTile(
                            draft,
                            editAnchorContext: editAnchorContext,
                            canEdit: canEdit,
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentTile(
    _SubprojectAttachmentDraft draft, {
    BuildContext? editAnchorContext,
    required bool canEdit,
  }) {
    if (draft.isPendingFile) {
      final name = draft.pendingFilename?.trim().isNotEmpty == true
          ? draft.pendingFilename!.trim()
          : 'File';
      return AsanaAttachmentDraftTile(
        isWebsiteLink: false,
        title: name,
        subtitle: 'Uploads when you save',
        enabled: !_saving,
        onRemove: canEdit ? () => _removeAttachmentDraft(draft) : null,
        imageBytes: draft.pendingBytes,
        mimeType: draft.mimeType,
        showImagePreview: _attachmentDraftIsImage(draft),
      );
    }
    final url = draft.urlController.text.trim();
    if (url.isEmpty) return const SizedBox.shrink();
    final desc = draft.descController.text.trim();
    final isLink = _draftShowsAsWebsiteLink(draft);
    return AsanaAttachmentDraftTile(
      isWebsiteLink: isLink,
      title: desc.isNotEmpty ? desc : url,
      url: url,
      enabled: !_saving,
      onRemove: canEdit ? () => _removeAttachmentDraft(draft) : null,
      onEditLink: canEdit && isLink && editAnchorContext != null
          ? () => _editAttachmentLink(editAnchorContext, draft)
          : null,
      mimeType: draft.mimeType,
      showImagePreview: !isLink && _attachmentDraftIsImage(draft),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chrome = AsanaSlideChrome(widget.palette);
    final adminReadOnly = state.adminViewMode;
    final creator = _row?.createByStaffUuid?.trim();
    final me = _myStaffUuid?.trim();
    final isCreator =
        me != null &&
        me.isNotEmpty &&
        creator != null &&
        creator.isNotEmpty &&
        me == creator;
    final canCreate = _createMode && _isParentProjectMember(state);
    final canEdit = !adminReadOnly && (_createMode ? canCreate : isCreator);
    final canCreateChildren =
        !_createMode &&
        !adminReadOnly &&
        (_isParentProjectMember(state) || _isSubprojectMember(state));
    final displayStatus = _row?.isPaused == true ? 'Paused' : _draftStatus;
    final parentProject = state.projectById(widget.projectId);
    if (canEdit && !_loading) _ensureSubprojectAi(state);

    return AsanaDetailSlideScaffold(
      backgroundColor: chrome.body,
      footer: _footer(state, canEdit),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsanaHoverTextField(
                  controller: _nameController,
                  canEdit: canEdit,
                  readOnly: _saving,
                  showOutline: false,
                  maxLines: 3,
                  minLines: 1,
                  style: asanaDetailTitleStyle(context),
                  hintText: 'Please fill in sub-project name',
                ),
                if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.taskName),
                const SizedBox(height: 12),
                AsanaDetailLabelValue(
                  label: 'Description',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AsanaFileDropRegion(
                        enabled: canEdit && !_saving,
                        imagesOnly: true,
                        onFiles: (files, rejected) => _stageInlineImage(
                          entityType: 'subproject_description',
                          entityId: _descriptionInlineEntityId,
                          files: files,
                          rejectedNonImages: rejected,
                        ),
                        child: AsanaHoverTextField(
                          controller: _descController,
                          canEdit: canEdit,
                          readOnly: _saving,
                          showOutline: false,
                          maxLines: 8,
                          minLines: 1,
                          style: asanaDetailMultilineValueStyle(context),
                          hintText: 'Please fill in sub-project description',
                        ),
                      ),
                      if (canEdit)
                        InlineImageToolbar(
                          enabled: !_saving,
                          onAdd: () => _stageInlineImage(
                            entityType: 'subproject_description',
                            entityId: _descriptionInlineEntityId,
                          ),
                        ),
                      InlineImagePreviewList(
                        images: _inlinePreviewItems(
                          entityType: 'subproject_description',
                          entityId: _descriptionInlineEntityId,
                          saved: _descriptionInlineImages,
                        ),
                        onRemove: canEdit ? _removeInlineImagePreview : null,
                      ),
                    ],
                  ),
                ),
                if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.description),
                if (parentProject != null)
                  AsanaDetailTwoColumnRow(
                    label: 'Parent Project',
                    child: AsanaDetailPlainValue(
                      text: parentProject.name.trim(),
                    ),
                  ),
                AsanaDetailTwoColumnRow(
                  label: 'Assignees',
                  child: KeyedSubtree(
                    key: _detailPopupWidthAlignKey,
                    child: canEdit
                        ? AsanaAssigneeFieldValue(
                            anchorLink: _assigneeAnchorLink,
                            assignees: _rowsForIds(
                              _visibleAssigneeIdsForPicker(),
                              state,
                            ),
                            canEdit: !_saving,
                            onOpenPicker: _pickAssignees,
                            onRemove: (id) => setState(() {
                              _assigneeIds.remove(id);
                            }),
                          )
                        : AsanaDetailPlainValue(
                            text:
                                _row?.assigneeStaffDisplayNames
                                    .where((n) => n.trim().isNotEmpty)
                                    .join(', ') ??
                                '',
                          ),
                  ),
                ),
                if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.assignees),
                AsanaDetailTwoColumnRow(
                  label: 'PIC',
                  child: canEdit
                      ? AsanaAssigneeFieldValue(
                          anchorLink: _picAnchorLink,
                          assignees: _rowsForIds(_picAssigneeIds, state),
                          canEdit: !_saving,
                          emptyPlaceholder: 'Select PIC',
                          onOpenPicker: _pickPics,
                          onRemove: (id) => setState(() {
                            _picAssigneeIds.remove(id);
                            _assigneeIds.remove(id);
                          }),
                        )
                      : AsanaDetailPlainValue(
                          text:
                              _row?.picStaffDisplayNames
                                  .where((n) => n.trim().isNotEmpty)
                                  .join(', ') ??
                              '',
                        ),
                ),
                if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.pic),
                if (!_createMode) ...[
                  AsanaDetailSectionHeader(
                    title: 'Tasks',
                    showAddButton: canCreateChildren,
                    addTooltip: 'Create task',
                    onAdd: !canCreateChildren || widget.onPushCreateTask == null
                        ? null
                        : (_) => widget.onPushCreateTask!(),
                    addEnabled:
                        canCreateChildren &&
                        !_saving &&
                        widget.onPushCreateTask != null,
                  ),
                  if (_tasks.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return AsanaSlideChildTaskList(
                          tasks: _tasks,
                          viewportWidth: constraints.maxWidth,
                          tableColors: widget.palette.tableColors,
                          formatDue: _formatShortDate,
                          statusLabel: _taskStatusLabel,
                          isCompleted: _taskCompleted,
                          isDeleted: _taskDeleted,
                          onOpenTask: widget.onPushTask,
                        );
                      },
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'No tasks yet',
                        style: asanaDetailValueStyle(
                          context,
                        ).copyWith(color: kAsanaTextSecondary),
                      ),
                    ),
                ],
                AsanaDetailTwoColumnRow(
                  label: 'Status',
                  child: canEdit && !(_row?.isPaused ?? false)
                      ? Builder(
                          builder: (anchorContext) => CompositedTransformTarget(
                            link: _statusAnchorLink,
                            child: MouseRegion(
                              cursor: _saving
                                  ? SystemMouseCursors.basic
                                  : SystemMouseCursors.click,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _saving
                                    ? null
                                    : () => _pickStatus(anchorContext),
                                child: AsanaDetailStatusPill(
                                  status: displayStatus,
                                ),
                              ),
                            ),
                          ),
                        )
                      : AsanaDetailStatusPill(status: displayStatus),
                ),
                if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.projectStatus),
                AsanaDetailTwoColumnRow(
                  label: 'Start date',
                  child: AsanaHoverTapValue(
                    value: _formatDate(_startDate),
                    canEdit: canEdit && !_saving,
                    emptyPlaceholder: '-',
                    onTap: canEdit && !_saving ? _pickStartDate : null,
                    onClear: canEdit && !_saving
                        ? () => setState(() => _startDate = null)
                        : null,
                  ),
                ),
                if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.startDate),
                AsanaDetailTwoColumnRow(
                  label: 'Due date',
                  child: AsanaHoverTapValue(
                    value: _formatDate(_endDate),
                    canEdit: canEdit && !_saving,
                    emptyPlaceholder: '-',
                    onTap: canEdit && !_saving ? _pickDueDate : null,
                    onClear: canEdit && !_saving
                        ? () => setState(() => _endDate = null)
                        : null,
                  ),
                ),
                if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.dueDate),
                Builder(
                  builder: (anchorContext) => _attachmentTwoColumnRow(
                    label: 'Files',
                    attachments: _fileAttachments,
                    addTooltip: 'Add file',
                    onAdd: canEdit ? (_) => _addFileAttachment() : null,
                    onDropFiles: canEdit
                        ? (files) => _addFileAttachment(dropped: files)
                        : null,
                    canEdit: canEdit,
                  ),
                ),
                Builder(
                  builder: (anchorContext) => _attachmentTwoColumnRow(
                    label: 'Links',
                    attachments: _urlAttachments,
                    addTooltip: 'Add website link',
                    onAdd: canEdit ? _addUrlAttachment : null,
                    addAnchorLink: _attachmentAddAnchorLink,
                    editAnchorContext: anchorContext,
                    canEdit: canEdit,
                  ),
                ),
                if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.websiteLink),
                AsanaDetailLabelValue(
                  label: 'Comments',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final comment in _comments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                comment.displayStaffName,
                                style: asanaDetailLabelStyle(context),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                stripInlineImageMarkers(comment.description),
                                style: asanaDetailMultilineValueStyle(context),
                              ),
                              InlineImagePreviewList(
                                images: _inlinePreviewItems(
                                  entityType: 'subproject_comment',
                                  entityId: comment.id,
                                  saved:
                                      _commentInlineImages[comment.id] ??
                                      const [],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (canEdit) ...[
                        AsanaFileDropRegion(
                          enabled: !_saving,
                          imagesOnly: true,
                          onFiles: (files, rejected) => _stageInlineImage(
                            entityType: 'subproject_comment',
                            entityId: 'draft',
                            files: files,
                            rejectedNonImages: rejected,
                          ),
                          child: AsanaHoverTextField(
                            controller: _commentController,
                            canEdit: true,
                            readOnly: _saving,
                            maxLines: 5,
                            minLines: 2,
                            style: asanaDetailMultilineValueStyle(context),
                            hintText: 'Add a comment',
                          ),
                        ),
                        InlineImageToolbar(
                          enabled: !_saving,
                          onAdd: () => _stageInlineImage(
                            entityType: 'subproject_comment',
                            entityId: 'draft',
                          ),
                        ),
                        InlineImagePreviewList(
                          images: _inlinePreviewItems(
                            entityType: 'subproject_comment',
                            entityId: 'draft',
                            saved: const [],
                          ),
                          onRemove: _removeInlineImagePreview,
                        ),
                      ],
                    ],
                  ),
                ),
                if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.comment),
              ],
            ),
    );
  }
}
