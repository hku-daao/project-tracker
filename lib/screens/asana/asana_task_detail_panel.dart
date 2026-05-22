import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/project_record.dart';
import '../../models/singular_comment.dart';
import '../../models/singular_subtask.dart';
import '../../models/task.dart';
import '../../priority.dart';
import '../../services/firebase_attachment_upload_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/copyable_snackbar.dart';
import '../../utils/due_span_policy.dart';
import '../../utils/hk_time.dart';
import '../../utils/holiday_date_picker.dart';
import '../../utils/singular_workflow_guards.dart';
import '../../widgets/attachment_add_link_dialog.dart';
import '../../widgets/attachment_source_bottom_sheet.dart';
import '../../widgets/outlook_attachment_chip.dart';
import '../../widgets/task_list_card.dart';
import '../asana_landing_screen.dart';
import 'asana_detail_subtask_list.dart';
import 'asana_detail_widgets.dart';
import 'asana_value_chips.dart';
import 'asana_theme.dart';

class AsanaTaskDetailPanel extends StatefulWidget {
  const AsanaTaskDetailPanel({
    super.key,
    this.taskId,
    this.createMode = false,
    required this.palette,
    required this.onClose,
    this.refreshToken = 0,
    this.onPushCreateSubtask,
    this.onPushSubtask,
  }) : assert(createMode || taskId != null);

  final String? taskId;
  final bool createMode;
  final AsanaLandingPalette palette;
  final int refreshToken;
  final VoidCallback onClose;
  final VoidCallback? onPushCreateSubtask;
  final void Function(String subtaskId)? onPushSubtask;

  @override
  State<AsanaTaskDetailPanel> createState() => _AsanaTaskDetailPanelState();
}

class _AttachmentDraft {
  _AttachmentDraft({this.id, String? url, String? desc})
      : urlController = TextEditingController(text: url ?? ''),
        descController = TextEditingController(text: desc ?? '');

  final String? id;
  final TextEditingController urlController;
  final TextEditingController descController;

  void dispose() {
    urlController.dispose();
    descController.dispose();
  }
}

class _AsanaTaskDetailPanelState extends State<AsanaTaskDetailPanel> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _reasonController = TextEditingController();
  final _commentController = TextEditingController();

  List<SingularSubtask> _subtasks = [];
  List<SingularCommentRowDisplay> _comments = [];
  final List<_AttachmentDraft> _attachments = [];

  bool _loadingExtras = true;
  bool _saving = false;
  OverlayEntry? _fullscreenLoading;
  String? _myStaffUuid;
  bool _staffDirector = false;

  int _localPriority = priorityStandard;
  DateTime? _startDate;
  DateTime? _dueDate;
  String? _selectedProjectId;
  List<ProjectRecord> _myProjects = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant AsanaTaskDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId ||
        oldWidget.createMode != widget.createMode) {
      if (widget.createMode) {
        _resetCreateDraft();
      } else {
        _syncFromTask();
      }
      _bootstrap();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _loadSubtasks();
    }
  }

  @override
  void dispose() {
    _hideFullscreenLoading();
    _nameController.dispose();
    _descController.dispose();
    _reasonController.dispose();
    _commentController.dispose();
    _clearAttachments();
    super.dispose();
  }

  void _setSaving(bool saving) {
    if (!mounted) return;
    if (_saving == saving) return;
    setState(() => _saving = saving);
    if (saving) {
      _showFullscreenLoading();
    } else {
      _hideFullscreenLoading();
    }
  }

  void _showFullscreenLoading() {
    if (_fullscreenLoading != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _fullscreenLoading = OverlayEntry(
      builder: (ctx) => Material(
        color: const Color(0x66000000),
        child: Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Theme.of(ctx).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
    overlay.insert(_fullscreenLoading!);
  }

  void _hideFullscreenLoading() {
    _fullscreenLoading?.remove();
    _fullscreenLoading?.dispose();
    _fullscreenLoading = null;
  }

  void _clearAttachments() {
    for (final a in _attachments) {
      a.dispose();
    }
    _attachments.clear();
  }

  void _resetCreateDraft() {
    _nameController.clear();
    _descController.clear();
    _reasonController.clear();
    _commentController.clear();
    _localPriority = priorityStandard;
    _startDate = null;
    _dueDate = null;
    _selectedProjectId = null;
    _subtasks = [];
    _comments = [];
    _clearAttachments();
  }

  Future<void> _bootstrap() async {
    setState(() => _loadingExtras = true);
    if (widget.createMode) {
      _resetCreateDraft();
    } else {
      _syncFromTask();
    }
    final lk = context.read<AppState>().userStaffAppId?.trim();
    if (lk != null && lk.isNotEmpty) {
      _myStaffUuid = await SupabaseService.staffRowIdForAssigneeKey(lk);
      if (_myStaffUuid != null && _myStaffUuid!.isNotEmpty) {
        _staffDirector = await SupabaseService.fetchStaffDirectorByStaffUuid(
          _myStaffUuid!,
        );
      }
    }
    final loads = <Future<void>>[
      _loadProjectsIfCreator(),
    ];
    if (!widget.createMode) {
      loads.addAll([
        _loadSubtasks(),
        _loadComments(),
        _loadAttachments(),
      ]);
    }
    await Future.wait(loads);
    if (mounted) setState(() => _loadingExtras = false);
  }

  void _syncFromTask() {
    final id = widget.taskId;
    if (id == null) return;
    final task = context.read<AppState>().taskById(id);
    if (task == null) return;
    _nameController.text = task.name;
    _descController.text = task.description;
    _reasonController.text = task.changeDueReason ?? '';
    _localPriority = task.priority;
    _startDate = task.startDate;
    _dueDate = task.endDate;
    _selectedProjectId = task.projectId;
  }

  Future<void> _loadSubtasks() async {
    final id = widget.taskId;
    if (id == null || !SupabaseConfig.isConfigured) return;
    try {
      final list = await SupabaseService.fetchSubtasksForTask(id);
      if (mounted) setState(() => _subtasks = list.where((s) => !s.isDeleted).toList());
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    final id = widget.taskId;
    if (id == null || !SupabaseConfig.isConfigured) return;
    try {
      final list = await SupabaseService.fetchSingularCommentsForTask(id);
      if (mounted) setState(() => _comments = list);
    } catch (_) {}
  }

  Future<void> _loadAttachments() async {
    final id = widget.taskId;
    if (id == null || !SupabaseConfig.isConfigured) return;
    try {
      final rows = await SupabaseService.fetchAttachmentsForTask(id);
      if (!mounted) return;
      setState(() {
        _clearAttachments();
        for (final r in rows) {
          _attachments.add(
            _AttachmentDraft(id: r.id, url: r.content, desc: r.description),
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _loadProjectsIfCreator() async {
    final state = context.read<AppState>();
    final task =
        widget.createMode ? null : state.taskById(widget.taskId ?? '');
    if (!widget.createMode && (task == null || !_isCreator(state, task))) {
      return;
    }
    final me = _myStaffUuid;
    if (me == null || me.isEmpty || !SupabaseConfig.isConfigured) return;
    try {
      final all = await SupabaseService.fetchAllProjectsFromSupabase();
      bool eligible(ProjectRecord p) {
        final s = p.status.trim();
        return s == 'Not started' || s == 'In progress';
      }

      final created = all
          .where((p) => p.createByStaffUuid?.trim() == me)
          .where(eligible)
          .toList();
      final pid = task?.projectId?.trim();
      if (pid != null &&
          pid.isNotEmpty &&
          !created.any((p) => p.id == pid)) {
        final extra = await SupabaseService.fetchProjectById(pid);
        if (extra != null) created.add(extra);
      }
      created.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() => _myProjects = created);
    } catch (_) {}
  }

  static bool _uuidEquals(String? a, String? b) {
    final x = a?.trim().toLowerCase() ?? '';
    final y = b?.trim().toLowerCase() ?? '';
    if (x.isEmpty || y.isEmpty) return false;
    return x == y;
  }

  bool _isCreator(AppState state, Task task) {
    final mine = state.userStaffAppId?.trim();
    final cb = task.createByAssigneeKey?.trim();
    if (mine != null && mine.isNotEmpty && cb != null && cb.isNotEmpty && mine == cb) {
      return true;
    }
    return _uuidEquals(_myStaffUuid, task.createByAssigneeKey);
  }

  bool _isTaskAssignee(AppState state, Task task) {
    final mine = state.userStaffAppId?.trim();
    if (mine != null && mine.isNotEmpty && task.assigneeIds.contains(mine)) {
      return true;
    }
    for (final id in task.assigneeIds) {
      if (_uuidEquals(id, _myStaffUuid)) return true;
    }
    return false;
  }

  bool _isPic(AppState state, Task task) {
    final p = task.pic?.trim();
    if (p == null || p.isEmpty) return false;
    final mine = state.userStaffAppId?.trim();
    if (mine != null && mine.isNotEmpty && mine == p) return true;
    return _uuidEquals(p, _myStaffUuid);
  }

  bool _taskDeleted(Task task) =>
      (task.dbStatus ?? '').trim().toLowerCase() == 'deleted';

  bool _canEditMetadata(AppState state, Task task) =>
      _isCreator(state, task) && !_taskDeleted(task);

  bool _canWriteComments(AppState state, Task task) =>
      (_isCreator(state, task) || _isTaskAssignee(state, task)) &&
      !_taskDeleted(task);

  bool _canEditAttachments(AppState state, Task task) =>
      !_taskDeleted(task) && (_isCreator(state, task) || _isPic(state, task));

  String _nameFor(AppState state, String? key) {
    final k = key?.trim();
    if (k == null || k.isEmpty) return '';
    return state.assigneeById(k)?.name ?? k;
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
  }

  String _formatDateTime(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy HH:mm');
  }

  bool _needsChangeDueReason() {
    if (_startDate == null || _dueDate == null) return false;
    if (allSubtasksComplyWithDueSpanPolicy(_subtasks)) return false;
    return dueDateExceedsPolicyForPriority(
      _startDate,
      _dueDate,
      _localPriority,
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final today = HkTime.todayDateOnlyHk();
    final picked = await showHolidayAwareDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _dueDate) ?? today,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _dueDate = picked;
      }
    });
  }

  Future<void> _pickPriority() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: priorityOptions
              .map(
                (p) => ListTile(
                  title: Text(priorityToDisplayName(p)),
                  onTap: () => Navigator.pop(ctx, p),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (choice != null && mounted) setState(() => _localPriority = choice);
  }

  Future<void> _pickProject(AppState state) async {
    if (_myProjects.isEmpty) return;
    final choice = await showModalBottomSheet<String?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('— No project —'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            ..._myProjects.map(
              (p) => ListTile(
                title: Text(p.name.trim().isEmpty ? p.id : p.name.trim()),
                onTap: () => Navigator.pop(ctx, p.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    setState(() => _selectedProjectId = choice.isEmpty ? null : choice);
  }

  Future<void> _createTask(AppState state) async {
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showCopyableSnackBar(
        context,
        'Task name is required',
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (_needsChangeDueReason() && _reasonController.text.trim().isEmpty) {
      showCopyableSnackBar(
        context,
        'Enter a reason when the start/due span exceeds policy for this priority',
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (_startDate != null &&
        _dueDate != null &&
        _startDate!.isAfter(_dueDate!)) {
      showCopyableSnackBar(
        context,
        'Start date cannot be after due date',
        backgroundColor: Colors.orange,
      );
      return;
    }
    _setSaving(true);
    try {
      final ins = await SupabaseService.insertTaskTableRow(
        taskName: name,
        description: _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        priority: priorityToDisplayName(_localPriority),
        startDate: _startDate,
        dueDate: _dueDate,
        creatorStaffLookupKey: state.userStaffAppId,
        picStaffLookupKey: state.userStaffAppId,
        changeDueReason:
            _needsChangeDueReason() ? _reasonController.text.trim() : null,
        projectId: _selectedProjectId,
      );
      if (ins.error != null && mounted) {
        showCopyableSnackBar(context, ins.error!, backgroundColor: Colors.orange);
        return;
      }
      final newId = ins.taskId;
      if (newId == null || newId.isEmpty) return;
      final comment = _commentController.text.trim();
      if (comment.isNotEmpty) {
        await SupabaseService.insertSingularCommentRow(
          taskId: newId,
          description: comment,
          creatorStaffLookupKey: state.userStaffAppId,
        );
      }
      final model = await SupabaseService.fetchSingularTaskModelById(newId);
      if (model != null) {
        state.upsertTask(model);
      }
      if (mounted) widget.onClose();
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _save(AppState state, Task task) async {
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    if (!_canEditMetadata(state, task)) {
      if (_isPic(state, task)) {
        await _saveAttachmentsOnly(state, task);
        return;
      }
      await _postCommentOnly(state, task);
      return;
    }
    if (_needsChangeDueReason() && _reasonController.text.trim().isEmpty) {
      showCopyableSnackBar(
        context,
        'Enter a reason when the start/due span exceeds policy for this priority',
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (_startDate != null &&
        _dueDate != null &&
        _startDate!.isAfter(_dueDate!)) {
      showCopyableSnackBar(
        context,
        'Start date cannot be after due date',
        backgroundColor: Colors.orange,
      );
      return;
    }
    _setSaving(true);
    try {
      final take = List<String>.from(task.assigneeIds);
      final slots = await SupabaseService.assigneeSlotsForTask(take);
      final selProj = _selectedProjectId?.trim();
      final curProj = task.projectId?.trim();
      final clearProject = (selProj == null || selProj.isEmpty) &&
          curProj != null &&
          curProj.isNotEmpty;

      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        taskName: _nameController.text.trim(),
        description: _descController.text.trim(),
        priority: priorityToDisplayName(_localPriority),
        assigneeSlots: slots,
        startDate: _startDate,
        dueDate: _dueDate,
        clearStartDate: _startDate == null,
        clearDueDate: _dueDate == null,
        updateByStaffLookupKey: state.userStaffAppId,
        picStaffLookupKey: task.pic,
        updateChangeDueReason: true,
        changeDueReason:
            _needsChangeDueReason() ? _reasonController.text.trim() : null,
        clearProjectId: clearProject,
        projectId: !clearProject && selProj != null && selProj.isNotEmpty
            ? selProj
            : null,
      );
      if (err != null && mounted) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      if (_canEditAttachments(state, task)) {
        final errA = await SupabaseService.replaceAttachmentsForTask(
          taskId: task.id,
          rows: _attachmentPayload(),
        );
        if (errA != null && mounted) {
          showCopyableSnackBar(
            context,
            'Task saved; attachments: $errA',
            backgroundColor: Colors.orange,
          );
        } else {
          await _loadAttachments();
        }
      }
      final comment = _commentController.text.trim();
      if (comment.isNotEmpty) {
        final c = await SupabaseService.insertSingularCommentRow(
          taskId: task.id,
          description: comment,
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (c.error == null) {
          _commentController.clear();
          await _loadComments();
        }
      }
      if (!mounted) return;
      final updated = _buildUpdatedTask(task, clearProject: clearProject);
      state.replaceTask(updated);
      SupabaseService.invalidateSubtasksCacheForTask(task.id);
      await _loadSubtasks();
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _saveAttachmentsOnly(AppState state, Task task) async {
    _setSaving(true);
    try {
      final err = await SupabaseService.replaceAttachmentsForTask(
        taskId: task.id,
        rows: _attachmentPayload(),
      );
      if (err != null && mounted) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
      } else {
        await _loadAttachments();
      }
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _postCommentOnly(AppState state, Task task) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    _setSaving(true);
    try {
      final c = await SupabaseService.insertSingularCommentRow(
        taskId: task.id,
        description: text,
        creatorStaffLookupKey: state.userStaffAppId,
      );
      if (c.error != null && mounted) {
        showCopyableSnackBar(context, c.error!, backgroundColor: Colors.orange);
        return;
      }
      _commentController.clear();
      await _loadComments();
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  bool _canMarkComplete(Task task) {
    final db = task.dbStatus?.trim() ?? '';
    if (db == 'Deleted') return false;
    if (task.status == TaskStatus.done || db == 'Completed') return false;
    if (task.submission?.trim() == 'Submitted') return false;
    return true;
  }

  Future<void> _markCompleted(AppState state, Task task) async {
    _setSaving(true);
    try {
      final completedAt = task.submitDate ?? DateTime.now().toUtc();
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Completed',
        submission: 'Accepted',
        updateByStaffLookupKey: state.userStaffAppId,
        completionDateAt: completedAt,
      );
      if (err != null && mounted) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      state.replaceTask(
        task.copyWith(
          dbStatus: 'Completed',
          status: TaskStatus.done,
          submission: 'Accepted',
          completionDate: completedAt,
        ),
      );
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _submitTask(AppState state, Task task) async {
    if (_subtasks.any(subtaskPreventsParentTaskSubmission)) {
      showCopyableSnackBar(
        context,
        'Complete all sub-tasks before submitting',
        backgroundColor: Colors.orange,
      );
      return;
    }
    _setSaving(true);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        submission: 'Submitted',
        updateByStaffLookupKey: state.userStaffAppId,
        stampSubmitDateNow: true,
      );
      if (err != null && mounted) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      state.replaceTask(
        task.copyWith(submission: 'Submitted', submitDate: DateTime.now().toUtc()),
      );
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _acceptTask(AppState state, Task task) async {
    await _markCompleted(state, task);
  }

  Future<void> _returnTask(AppState state, Task task) async {
    _setSaving(true);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        submission: 'Returned',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (err != null && mounted) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      state.replaceTask(task.copyWith(submission: 'Returned'));
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  bool _canUndoAcceptOrReturn(Task task) {
    if ((task.dbStatus ?? '').trim().toLowerCase() == 'deleted') return false;
    final s = task.submission?.trim().toLowerCase() ?? '';
    return s == 'accepted' || s == 'returned';
  }

  Future<void> _undoAcceptOrReturn(AppState state, Task task) async {
    _setSaving(true);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Incomplete',
        submission: 'Pending',
        updateByStaffLookupKey: state.userStaffAppId,
        clearCompletionDate: true,
      );
      if (err != null && mounted) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      state.replaceTask(
        task.copyWith(
          dbStatus: 'Incomplete',
          status: TaskStatus.todo,
          submission: 'Pending',
          clearCompletionDate: true,
        ),
      );
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _undoDeleted(AppState state, Task task) async {
    _setSaving(true);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Incomplete',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (err != null && mounted) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      state.replaceTask(
        task.copyWith(dbStatus: 'Incomplete', status: TaskStatus.todo),
      );
      await _loadSubtasks();
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _deleteTask(AppState state, Task task) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: const Text('This marks the task as deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    _setSaving(true);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Deleted',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (err != null && mounted) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      await SupabaseService.markSubtasksDeletedForParentTask(
        taskId: task.id,
        updateByStaffLookupKey: state.userStaffAppId,
      );
      state.replaceTask(task.copyWith(dbStatus: 'Deleted'));
      await _loadSubtasks();
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _addAttachment(Task task) async {
    showAttachmentSourceBottomSheet(
      context: context,
      onPickFromDevice: () async {
        final r = await FirebaseAttachmentUploadService.pickUploadForTask(
          task.id,
          aclStaffKeys: [
            task.createByAssigneeKey,
            task.pic,
            ...task.assigneeIds,
          ],
        );
        if (!mounted || r.url == null) return;
        setState(() {
          _attachments.add(_AttachmentDraft(url: r.url, desc: r.label));
        });
      },
      onPickFromLink: () async {
        final pair = await showAttachmentAddLinkDialog(context);
        if (pair == null || !mounted) return;
        setState(() {
          _attachments.add(
            _AttachmentDraft(url: pair.url, desc: pair.description),
          );
        });
      },
    );
  }

  Task _buildUpdatedTask(Task task, {required bool clearProject}) {
    String? projectName = task.projectName;
    final selProj = _selectedProjectId?.trim();
    if (clearProject) {
      projectName = null;
    } else if (selProj != null && selProj.isNotEmpty) {
      for (final p in _myProjects) {
        if (p.id == selProj) {
          projectName = p.name.trim();
          break;
        }
      }
    }
    return task.copyWith(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      priority: _localPriority,
      startDate: _startDate,
      endDate: _dueDate,
      projectId: clearProject ? null : _selectedProjectId,
      projectName: projectName,
      clearProject: clearProject,
      changeDueReason:
          _needsChangeDueReason() ? _reasonController.text.trim() : null,
      updateDate: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
  }

  List<({String? content, String? description})> _attachmentPayload() {
    return _attachments
        .map(
          (e) => (
            content: e.urlController.text.trim().isEmpty
                ? null
                : e.urlController.text.trim(),
            description: e.descController.text.trim().isEmpty
                ? null
                : e.descController.text.trim(),
          ),
        )
        .where((r) => (r.content ?? '').isNotEmpty)
        .toList();
  }

  String _creatorDisplayName(AppState state) {
    final id = state.userStaffAppId?.trim();
    if (id == null || id.isEmpty) return '';
    return _nameFor(state, id);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chrome = AsanaSlideChrome(widget.palette);
    if (!widget.createMode) {
      final task = state.taskById(widget.taskId ?? '');
      if (task == null) {
        return ColoredBox(
          color: chrome.body,
          child: const Center(child: Text('Task not found')),
        );
      }
      return _buildTaskBody(context, state, task, chrome);
    }
    return _buildCreateBody(context, state, chrome);
  }

  Widget _buildCreateBody(
    BuildContext context,
    AppState state,
    AsanaSlideChrome chrome,
  ) {
    const canEdit = true;
    return Stack(
      children: [
        ColoredBox(
          color: chrome.body,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsanaHoverTextField(
                  controller: _nameController,
                  canEdit: canEdit,
                  readOnly: _saving,
                  maxLines: 6,
                  minLines: 1,
                  style: asanaDetailTitleStyle(context),
                ),
                const SizedBox(height: 12),
                AsanaDetailLabelValue(
                  label: 'Description',
                  child: AsanaHoverTextField(
                    controller: _descController,
                    canEdit: canEdit,
                    readOnly: _saving,
                    maxLines: 8,
                    minLines: 2,
                    style: asanaDetailMultilineValueStyle(context),
                  ),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Project',
                  child: _myProjects.isNotEmpty
                      ? AsanaHoverTapValue(
                          value: _projectLabelForDraft(),
                          canEdit: true,
                          onTap: () => _pickProject(state),
                        )
                      : const AsanaDetailPlainValue(text: ''),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Creator',
                  child: AsanaDetailPlainValue(text: _creatorDisplayName(state)),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'PIC',
                  child: AsanaDetailPlainValue(text: _creatorDisplayName(state)),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Assignees',
                  child: const AsanaDetailPlainValue(text: ''),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Priority',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _saving ? null : _pickPriority,
                        child: AsanaPriorityChip(priority: _localPriority),
                      ),
                    ),
                  ),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Status',
                  child: const AsanaDetailStatusPill(status: 'Incomplete'),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Start date',
                  child: AsanaHoverTapValue(
                    value: _formatDate(_startDate),
                    canEdit: true,
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Due date',
                  child: AsanaHoverTapValue(
                    value: _formatDate(_dueDate),
                    canEdit: true,
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
                if (_needsChangeDueReason())
                  AsanaDetailLabelValue(
                    label: 'Reason',
                    child: AsanaHoverTextField(
                      controller: _reasonController,
                      canEdit: true,
                      readOnly: _saving,
                      maxLines: 4,
                      minLines: 2,
                      style: asanaDetailMultilineValueStyle(context),
                    ),
                  ),
                AsanaDetailTwoColumnRow(
                  label: 'Submission',
                  child: const AsanaDetailSubmissionPill(submission: 'Pending'),
                ),
                AsanaDetailLabelValue(
                  label: 'Comments',
                  child: AsanaHoverTextField(
                    controller: _commentController,
                    canEdit: true,
                    readOnly: _saving,
                    maxLines: 4,
                    minLines: 2,
                    style: asanaDetailMultilineValueStyle(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: chrome.footer,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: chrome.footerBorder)),
              ),
              child: _ActionBar(
                createMode: true,
                saving: _saving,
                palette: widget.palette,
                onPrimary: () => _createTask(state),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskBody(
    BuildContext context,
    AppState state,
    Task task,
    AsanaSlideChrome chrome,
  ) {
    final canEdit = _canEditMetadata(state, task);
    final tc = widget.palette.tableColors;

    return Stack(
          children: [
            ColoredBox(
              color: chrome.body,
              child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AsanaHoverTextField(
                    controller: _nameController,
                    canEdit: canEdit,
                    readOnly: _saving,
                    maxLines: 6,
                    minLines: 1,
                    style: asanaDetailTitleStyle(context),
                  ),
                  const SizedBox(height: 12),
                  AsanaDetailLabelValue(
                    label: 'Description',
                    child: AsanaHoverTextField(
                      controller: _descController,
                      canEdit: canEdit,
                      readOnly: _saving,
                      maxLines: 8,
                      minLines: 2,
                      style: asanaDetailMultilineValueStyle(context),
                    ),
                  ),
                  AsanaDetailTwoColumnRow(
                    label: 'Project',
                    child: canEdit && _myProjects.isNotEmpty
                        ? AsanaHoverTapValue(
                            value: _projectLabel(task),
                            canEdit: true,
                            onTap: () => _pickProject(state),
                          )
                        : AsanaDetailPlainValue(
                            text: task.projectName?.trim() ?? '',
                          ),
                  ),
                  AsanaDetailTwoColumnRow(
                    label: 'Creator',
                    child: AsanaDetailPlainValue(
                      text: task.createByStaffName?.trim() ?? '',
                    ),
                  ),
                  AsanaDetailTwoColumnRow(
                    label: 'PIC',
                    child: AsanaDetailPlainValue(text: _nameFor(state, task.pic)),
                  ),
                  AsanaDetailTwoColumnRow(
                    label: 'Assignees',
                    child: AsanaDetailPlainValue(
                      text: task.assigneeIds
                          .map((id) => _nameFor(state, id))
                          .where((n) => n.isNotEmpty)
                          .join(', '),
                    ),
                  ),
                  AsanaDetailSectionHeader(
                    title: 'Sub-tasks',
                    showAddButton: true,
                    addTooltip: 'Create sub-task',
                    onAdd: widget.onPushCreateSubtask,
                    addEnabled: canEdit &&
                        !singularTaskStatusIsCompleted(task) &&
                        !_saving &&
                        widget.onPushCreateSubtask != null,
                  ),
                  if (_subtasks.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return AsanaDetailSubtaskList(
                          viewportWidth: constraints.maxWidth,
                          subtasks: _subtasks,
                          tableColors: tc,
                          appState: state,
                          projectName: task.projectName?.trim() ?? '—',
                          onOpenSubtask: widget.onPushSubtask,
                        );
                      },
                    ),
                  if (_subtasks.isNotEmpty) const SizedBox(height: 8),
                  AsanaDetailTwoColumnRow(
                    label: 'Priority',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: canEdit
                          ? MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _saving ? null : _pickPriority,
                                child: AsanaPriorityChip(priority: _localPriority),
                              ),
                            )
                          : AsanaPriorityChip(priority: task.priority),
                    ),
                  ),
                  AsanaDetailTwoColumnRow(
                    label: 'Status',
                    child: AsanaDetailStatusPill(
                      status: TaskListCard.statusLabel(task),
                    ),
                  ),
                  AsanaDetailTwoColumnRow(
                    label: 'Start date',
                    child: AsanaHoverTapValue(
                      value: _formatDate(_startDate),
                      canEdit: canEdit,
                      onTap: () => _pickDate(isStart: true),
                    ),
                  ),
                  AsanaDetailTwoColumnRow(
                    label: 'Due date',
                    child: AsanaHoverTapValue(
                      value: _formatDate(_dueDate),
                      canEdit: canEdit,
                      onTap: () => _pickDate(isStart: false),
                    ),
                  ),
                  if (_needsChangeDueReason() ||
                      (task.changeDueReason ?? '').trim().isNotEmpty)
                    AsanaDetailLabelValue(
                      label: 'Reason',
                      child: AsanaHoverTextField(
                        controller: _reasonController,
                        canEdit: canEdit,
                        readOnly: _saving,
                        maxLines: 4,
                        minLines: 2,
                        style: asanaDetailMultilineValueStyle(context),
                      ),
                    ),
                  AsanaDetailTwoColumnRow(
                    label: 'Submission',
                    child: AsanaDetailSubmissionPill(submission: task.submission),
                  ),
                  if ((task.updateByStaffName ?? '').trim().isNotEmpty)
                    AsanaDetailTwoColumnRow(
                      label: 'Last updated by',
                      child: AsanaDetailPlainValue(
                        text: task.updateByStaffName!.trim(),
                      ),
                    ),
                  if (task.lastUpdated != null)
                    AsanaDetailTwoColumnRow(
                      label: 'Last updated',
                      child: AsanaDetailPlainValue(
                        text: _formatDateTime(task.lastUpdated),
                      ),
                    ),
                  AsanaDetailSectionHeader(
                    title: 'Attachments',
                    showAddButton: true,
                    addTooltip: 'Add attachment',
                    onAdd: () => _addAttachment(task),
                    addEnabled: _canEditAttachments(state, task) && !_saving,
                  ),
                  if (_loadingExtras)
                    const LinearProgressIndicator()
                  else if (_attachments.isEmpty)
                    const SizedBox(height: 4)
                  else
                    ..._attachments.map((e) {
                      final url = e.urlController.text.trim();
                      if (url.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlookAttachmentChip(
                          label: e.descController.text.trim().isEmpty
                              ? url
                              : e.descController.text.trim(),
                          url: url,
                        ),
                      );
                    }),
                  AsanaDetailLabelValue(
                    label: 'Comments',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_canWriteComments(state, task))
                          AsanaHoverTextField(
                            controller: _commentController,
                            canEdit: true,
                            readOnly: _saving,
                            maxLines: 4,
                            minLines: 2,
                            style: asanaDetailMultilineValueStyle(context),
                          ),
                        if (_comments.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ..._comments.map(
                            (c) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.displayStaffName,
                                    style: asanaDetailLabelStyle(context),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c.description,
                                    style: asanaDetailValueStyle(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: chrome.footer,
                elevation: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: chrome.footerBorder)),
                  ),
                  child: _ActionBar(
                    createMode: false,
                    saving: _saving,
                    palette: widget.palette,
                    state: state,
                    task: task,
                    isCreator: _isCreator(state, task),
                    isPic: _isPic(state, task),
                    isAssigneeOnly: _isTaskAssignee(state, task) &&
                        !_isCreator(state, task) &&
                        !_isPic(state, task),
                    canDelete: _staffDirector || _isCreator(state, task),
                    onUpdate: () => _save(state, task),
                    onMarkComplete: () => _markCompleted(state, task),
                    onSubmit: () => _submitTask(state, task),
                    onAccept: () => _acceptTask(state, task),
                    onReturn: () => _returnTask(state, task),
                    onDelete: () => _deleteTask(state, task),
                    onUndoAcceptOrReturn: () => _undoAcceptOrReturn(state, task),
                    onUndoDeleted: () => _undoDeleted(state, task),
                    canMarkComplete: _canMarkComplete(task),
                    canUndoAcceptOrReturn: _canUndoAcceptOrReturn(task),
                  ),
                ),
              ),
            ),
          ],
        );
  }

  String _projectLabelForDraft() {
    final id = _selectedProjectId?.trim();
    if (id == null || id.isEmpty) return '';
    final hit = _myProjects.where((p) => p.id == id).toList();
    if (hit.isNotEmpty) return hit.first.name.trim();
    return id;
  }

  String _projectLabel(Task task) {
    final draft = _projectLabelForDraft();
    if (draft.isNotEmpty) return draft;
    return task.projectName?.trim() ?? '';
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.createMode,
    required this.saving,
    required this.palette,
    this.onPrimary,
    this.state,
    this.task,
    this.isCreator = false,
    this.isPic = false,
    this.isAssigneeOnly = false,
    this.canDelete = false,
    this.onUpdate,
    this.onMarkComplete,
    this.onSubmit,
    this.onAccept,
    this.onReturn,
    this.onDelete,
    this.onUndoAcceptOrReturn,
    this.onUndoDeleted,
    this.canMarkComplete = false,
    this.canUndoAcceptOrReturn = false,
  });

  final bool createMode;
  final bool saving;
  final AsanaLandingPalette palette;
  final VoidCallback? onPrimary;
  final AppState? state;
  final Task? task;
  final bool isCreator;
  final bool isPic;
  final bool isAssigneeOnly;
  final bool canDelete;
  final VoidCallback? onUpdate;
  final VoidCallback? onMarkComplete;
  final VoidCallback? onSubmit;
  final VoidCallback? onAccept;
  final VoidCallback? onReturn;
  final VoidCallback? onDelete;
  final VoidCallback? onUndoAcceptOrReturn;
  final VoidCallback? onUndoDeleted;
  final bool canMarkComplete;
  final bool canUndoAcceptOrReturn;

  @override
  Widget build(BuildContext context) {
    if (createMode) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton(
            onPressed: saving ? null : onPrimary,
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(saving ? 'Creating…' : 'Create'),
          ),
        ],
      );
    }

    final t = task!;
    final deleted = (t.dbStatus ?? '').trim().toLowerCase() == 'deleted';
    final showUpdate =
        !deleted && (isCreator || isPic || isAssigneeOnly);
    final buttons = <Widget>[];

    if (showUpdate) {
      buttons.add(
        FilledButton(
          onPressed: saving ? null : onUpdate,
          style: AsanaTaskDetailActionStyles.updateFilled(context),
          child: Text(saving ? 'Saving…' : 'Update'),
        ),
      );
    }
    if (!deleted && isCreator && canMarkComplete) {
      buttons.add(
        FilledButton(
          onPressed: saving ? null : onMarkComplete,
          style: AsanaTaskDetailActionStyles.successFilled(),
          child: const Text('Mark as Completed'),
        ),
      );
    }
    if (!deleted && isCreator && canUndoAcceptOrReturn) {
      buttons.add(
        OutlinedButton(
          onPressed: saving ? null : onUndoAcceptOrReturn,
          style: AsanaTaskDetailActionStyles.undoOutlined(context),
          child: const Text('Undo'),
        ),
      );
    }
    if (!deleted && isPic && _canPicSubmit(t)) {
      buttons.add(
        FilledButton(
          onPressed: saving ? null : onSubmit,
          style: AsanaTaskDetailActionStyles.submitFilled(context),
          child: const Text('Submit'),
        ),
      );
    }
    if (!deleted && isCreator && t.submission?.trim() == 'Submitted') {
      buttons.add(
        FilledButton(
          onPressed: saving ? null : onAccept,
          style: AsanaTaskDetailActionStyles.successFilled(),
          child: const Text('Accept'),
        ),
      );
      buttons.add(
        FilledButton(
          onPressed: saving ? null : onReturn,
          style: AsanaTaskDetailActionStyles.returnFilled(),
          child: const Text('Return'),
        ),
      );
    }
    if (canDelete) {
      if (deleted) {
        buttons.add(
          OutlinedButton(
            onPressed: saving ? null : onUndoDeleted,
            style: AsanaTaskDetailActionStyles.undoOutlined(context),
            child: const Text('Undo'),
          ),
        );
      } else {
        buttons.add(
          OutlinedButton(
            onPressed: saving ? null : onDelete,
            style: AsanaTaskDetailActionStyles.deleteOutlined(),
            child: const Text('Delete'),
          ),
        );
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          buttons[i],
        ],
      ],
    );
  }

  static bool _canPicSubmit(Task task) {
    final s = task.submission?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return true;
    if (s == 'returned') return true;
    return s != 'submitted' && s != 'accepted';
  }
}
