import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/postgrest_config.dart';
import '../../models/singular_comment.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/subproject_record.dart';
import '../../services/attachment_upload_service.dart';
import '../../services/database_service.dart';
import '../../utils/attachment_url_launch.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_assignee_field.dart';
import 'asana_assignee_picker.dart';
import 'asana_attachment_draft_tile.dart';
import 'asana_attachment_menu.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';

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
    required this.onClose,
    this.onCreated,
    this.onChanged,
  });

  final AsanaLandingPalette palette;
  final String projectId;
  final String? subprojectId;
  final bool createMode;
  final VoidCallback onClose;
  final void Function(String subprojectId)? onCreated;
  final VoidCallback? onChanged;

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
  DateTime? _startDate;
  DateTime? _endDate;
  String _draftStatus = 'Not started';
  bool _saving = false;
  bool _loading = false;
  String? _myStaffUuid;
  SubprojectRecord? _row;
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
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _commentController.dispose();
    for (final attachment in _attachments) {
      attachment.dispose();
    }
    _assigneeSnapshot.dispose();
    _picSnapshot.dispose();
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
      await _loadComments();
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

  Future<void> _addFileAttachment() async {
    final picked = await AttachmentUploadService.pickFilesForUpload();
    if (!mounted) return;
    if (picked.error != null) {
      await _showInfo('Attachment upload failed', picked.error!);
      return;
    }
    setState(() {
      for (final file in picked.files) {
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

  Future<String?> _uploadPendingFiles(String subprojectId, AppState state) async {
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
    if (_picAssigneeIds.isEmpty) {
      await _showInfo('PIC required', 'Select at least one PIC.');
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
      final comment = _commentController.text.trim();
      if (comment.isNotEmpty) {
        final c = await DatabaseService.insertSubprojectCommentRow(
          subprojectId: newId,
          description: comment,
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (c.error != null) {
          await _showInfo('Sub-project saved, comment failed', c.error!);
        }
      }
      state.applySubprojects(await DatabaseService.fetchAllSubprojects());
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
      final comment = _commentController.text.trim();
      if (comment.isNotEmpty) {
        final c = await DatabaseService.insertSubprojectCommentRow(
          subprojectId: id,
          description: comment,
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (c.error != null) {
          await _showInfo('Sub-project saved, comment failed', c.error!);
        } else {
          _commentController.clear();
        }
      }
      state.applySubprojects(await DatabaseService.fetchAllSubprojects());
      await _loadComments();
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setPause(AppState state, {required bool paused}) async {
    final id = widget.subprojectId?.trim();
    if (id == null || id.isEmpty) return;
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
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(AppState state) async {
    final id = widget.subprojectId?.trim();
    if (id == null || id.isEmpty) return;
    final ok = await showAsanaConfirmDialog(
      context: context,
      title: 'Remove sub-project',
      content:
          'Remove "${_nameController.text.trim()}"? Tasks under it stay on the project.',
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

  Widget _footer(AppState state, bool canEdit) {
    final chrome = AsanaSlideChrome(widget.palette);
    if (!canEdit) return const SizedBox.shrink();
    if (_createMode) {
      return AsanaDetailSlideFooter(
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
    }
    final row = _row;
    final buttons = <Widget>[
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
    return AsanaDetailSlideFooter(
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

  Widget _attachmentTwoColumnRow({
    required String label,
    required List<_SubprojectAttachmentDraft> attachments,
    required String addTooltip,
    required void Function(BuildContext buttonContext)? onAdd,
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
    final canEdit = !adminReadOnly &&
        (_createMode ||
            (me != null &&
                me.isNotEmpty &&
                creator != null &&
                creator.isNotEmpty &&
                me == creator));
    final displayStatus = _row?.isPaused == true ? 'Paused' : _draftStatus;

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
                const SizedBox(height: 12),
                AsanaDetailLabelValue(
                  label: 'Description',
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
                            text: _row?.assigneeStaffDisplayNames
                                    .where((n) => n.trim().isNotEmpty)
                                    .join(', ') ??
                                '',
                          ),
                  ),
                ),
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
                          text: _row?.picStaffDisplayNames
                                  .where((n) => n.trim().isNotEmpty)
                                  .join(', ') ??
                              '',
                        ),
                ),
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
                Builder(
                  builder: (anchorContext) => _attachmentTwoColumnRow(
                    label: 'Files',
                    attachments: _fileAttachments,
                    addTooltip: 'Add file',
                    onAdd: canEdit ? (_) => _addFileAttachment() : null,
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
                                comment.description,
                                style: asanaDetailMultilineValueStyle(context),
                              ),
                            ],
                          ),
                        ),
                      if (canEdit)
                        AsanaHoverTextField(
                          controller: _commentController,
                          canEdit: true,
                          readOnly: _saving,
                          maxLines: 5,
                          minLines: 2,
                          style: asanaDetailMultilineValueStyle(context),
                          hintText: 'Add a comment',
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
