import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/singular_subtask.dart';
import '../../models/task.dart';
import '../../priority.dart';
import '../../services/supabase_service.dart';
import '../../utils/copyable_snackbar.dart';

class _SubtaskAttachmentEntry {
  _SubtaskAttachmentEntry({this.id, String? url, String? desc})
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

/// Detail view for a row in `public.subtask`.
class SubtaskDetailScreen extends StatefulWidget {
  const SubtaskDetailScreen({super.key, required this.subtaskId});

  final String subtaskId;

  @override
  State<SubtaskDetailScreen> createState() => _SubtaskDetailScreenState();
}

class _SubtaskDetailScreenState extends State<SubtaskDetailScreen> {
  static const Color _selGreen = Color(0xFF1B5E20);

  SingularSubtask? _sub;
  Task? _parentTask;
  String? _myStaffUuid;
  bool _director = false;
  bool _loading = true;
  bool _saving = false;

  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final List<_SubtaskAttachmentEntry> _subtaskAttachments = [];
  final _commentController = TextEditingController();

  List<SubtaskCommentRowDisplay> _comments = [];
  String? _resolvedPicStaffUuid;

  /// Last loaded [SingularSubtask.pic] as an assignee key (for dirty check).
  String? _picAssigneeKeyResolved;

  /// Edited PIC assignee key; saved with **Update** (not on dropdown change).
  String? _picEditKey;
  int _editPriority = priorityStandard;
  DateTime? _editStart;
  DateTime? _editDue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _clearSubtaskAttachments();
    _commentController.dispose();
    super.dispose();
  }

  void _clearSubtaskAttachments() {
    for (final e in _subtaskAttachments) {
      e.dispose();
    }
    _subtaskAttachments.clear();
  }

  void _addSubtaskAttachmentRow() {
    setState(() => _subtaskAttachments.add(_SubtaskAttachmentEntry()));
  }

  void _removeSubtaskAttachmentRow(int index) {
    setState(() {
      _subtaskAttachments[index].dispose();
      _subtaskAttachments.removeAt(index);
    });
  }

  List<({String? content, String? description})> _subtaskAttachmentPayload() {
    return _subtaskAttachments
        .map(
          (e) => (
            content: e.urlController.text,
            description: e.descController.text,
          ),
        )
        .toList();
  }

  String? _firstSubtaskAttachmentUrl() {
    for (final e in _subtaskAttachments) {
      final u = e.urlController.text.trim();
      if (u.isNotEmpty) return u;
    }
    return null;
  }

  bool _canEditSubtaskAttachments(AppState state, SingularSubtask st) =>
      _isCreator(state, st) || _isPic(state, st);

  Future<void> _load() async {
    if (!SupabaseConfig.isConfigured) {
      setState(() => _loading = false);
      return;
    }
    final st = await SupabaseService.fetchSubtaskById(widget.subtaskId);
    final state = context.read<AppState>();
    Task? parent;
    if (st != null) {
      parent = await SupabaseService.fetchSingularTaskModelById(st.taskId) ??
          state.taskById(st.taskId);
    }
    String? myU;
    final lk = state.userStaffAppId?.trim();
    if (lk != null && lk.isNotEmpty) {
      myU = await SupabaseService.staffRowIdForAssigneeKey(lk);
      if (myU != null && myU.isNotEmpty) {
        final dir = await SupabaseService.fetchStaffDirectorByStaffUuid(myU);
        if (mounted) setState(() => _director = dir);
      }
    }
    List<SubtaskAttachmentRow> attRows = [];
    if (st != null) {
      attRows = await SupabaseService.fetchSubtaskAttachments(st.id);
      final cm = await SupabaseService.fetchSubtaskComments(st.id);
      if (mounted) {
        setState(() {
          _comments = cm;
        });
      }
    }
    if (!mounted) return;
    String? picUuid;
    if (st?.pic != null && st!.pic!.trim().isNotEmpty) {
      picUuid = await SupabaseService.staffRowIdForAssigneeKey(st.pic!.trim());
    }
    if (!mounted) return;
    String? picKeyResolved;
    if (st != null && parent != null) {
      final p = st.pic?.trim();
      if (p != null && p.isNotEmpty) {
        for (final id in parent.assigneeIds) {
          if (id == p) {
            picKeyResolved = id;
            break;
          }
        }
        if (picKeyResolved == null && picUuid != null && picUuid.isNotEmpty) {
          for (final id in parent.assigneeIds) {
            final u = await SupabaseService.staffRowIdForAssigneeKey(id);
            if (_uuidEq(u, picUuid)) {
              picKeyResolved = id;
              break;
            }
          }
        }
      }
    }
    if (!mounted) return;
    _clearSubtaskAttachments();
    setState(() {
      _sub = st;
      _parentTask = parent;
      _myStaffUuid = myU;
      _resolvedPicStaffUuid = picUuid;
      _picAssigneeKeyResolved = picKeyResolved;
      _picEditKey = picKeyResolved;
      _loading = false;
      if (st != null) {
        _nameController.text = st.subtaskName;
        _descController.text = st.description;
        for (final r in attRows) {
          _subtaskAttachments.add(
            _SubtaskAttachmentEntry(
              id: r.id,
              url: r.content,
              desc: r.description,
            ),
          );
        }
        _editPriority = st.priority;
        _editStart = st.startDate;
        _editDue = st.dueDate;
      }
    });
  }

  bool _uuidEq(String? a, String? b) {
    final x = a?.trim().toLowerCase() ?? '';
    final y = b?.trim().toLowerCase() ?? '';
    if (x.isEmpty || y.isEmpty) return false;
    return x == y;
  }

  bool _isCreator(AppState state, SingularSubtask st) {
    final cb = st.createByStaffId?.trim();
    return _uuidEq(_myStaffUuid, cb);
  }

  bool _isParentTaskCreator(AppState state, Task parent) {
    final mine = state.userStaffAppId?.trim();
    final cb = parent.createByAssigneeKey?.trim();
    return mine != null &&
        mine.isNotEmpty &&
        cb != null &&
        cb.isNotEmpty &&
        mine == cb;
  }

  /// Sub-task creator or parent task creator may set [SingularSubtask.pic] from task assignees.
  bool _canEditSubtaskPic(AppState state, SingularSubtask st, Task parent) =>
      _isCreator(state, st) || _isParentTaskCreator(state, parent);

  String _subtaskAssigneeLine(AppState state, SingularSubtask st) {
    if (st.assigneeIds.isEmpty) return '—';
    return st.assigneeIds
        .map((id) => state.assigneeById(id)?.name ?? id)
        .join(', ');
  }

  String _picDisplayName(AppState state, SingularSubtask st) {
    final p = st.pic?.trim();
    if (p == null || p.isEmpty) return '—';
    return state.assigneeById(p)?.name ?? p;
  }

  bool _picEditIsDirty(Task parent) {
    if (parent.assigneeIds.length <= 1) return false;
    final a = _picAssigneeKeyResolved?.trim() ?? '';
    final b = _picEditKey?.trim() ?? '';
    return a != b;
  }

  /// [stored] is `subtask.update_date`; display uses +8h (Hong Kong), format Mmm DD, YYYY HH:mm.
  String _subtaskLastUpdatedLine(DateTime? stored) {
    if (stored == null) return 'Last updated: —';
    final shown = stored.add(const Duration(hours: 8));
    return 'Last updated: ${DateFormat('MMM dd, yyyy HH:mm').format(shown)}';
  }

  Widget _priorityToggleButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Material(
          color: selected ? _selGreen : Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: enabled
                ? onTap
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'You do not have permission for this action.',
                        ),
                      ),
                    );
                  },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _selGreen, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isPic(AppState state, SingularSubtask st) {
    final p = st.pic?.trim();
    final mine = state.userStaffAppId?.trim();
    if (mine != null && p != null && mine == p) return true;
    final uid = _myStaffUuid?.trim();
    final picU = _resolvedPicStaffUuid?.trim();
    if (uid != null && picU != null && _uuidEq(uid, picU)) return true;
    return false;
  }

  bool _isAssignee(AppState state, SingularSubtask st) {
    final mine = state.userStaffAppId?.trim();
    if (mine != null && st.assigneeIds.contains(mine)) return true;
    final uid = _myStaffUuid?.trim();
    if (uid == null) return false;
    for (final id in st.assigneeIds) {
      if (_uuidEq(id, uid)) return true;
    }
    return false;
  }

  bool _canPicSubmit(SingularSubtask st) {
    final s = st.submission?.trim() ?? '';
    if (s.isEmpty || s.toLowerCase() == 'pending') return true;
    if (s.toLowerCase() == 'returned') return true;
    if (s.toLowerCase() == 'submitted' || s.toLowerCase() == 'accepted') {
      return false;
    }
    return true;
  }

  Future<void> _postComment(AppState state, SingularSubtask st) async {
    if (!_isAssignee(state, st) && !_isCreator(state, st)) {
      return;
    }
    final t = _commentController.text.trim();
    if (t.isEmpty) return;
    setState(() => _saving = true);
    try {
      final ins = await SupabaseService.insertSubtaskCommentRow(
        subtaskId: st.id,
        description: t,
        creatorStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (ins.error != null) {
        showCopyableSnackBar(context, ins.error!, backgroundColor: Colors.orange);
        return;
      }
      _commentController.clear();
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment added'), backgroundColor: Colors.green),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveMetadata(AppState state, SingularSubtask st) async {
    final parent = _parentTask;
    if (parent == null) return;
    final creator = _isCreator(state, st);
    final canPic = _canEditSubtaskPic(state, st, parent);
    final multiTaskAssignees = parent.assigneeIds.length > 1;
    final picDirty =
        canPic && multiTaskAssignees && _picEditIsDirty(parent);
    if (!creator) {
      if (canPic && multiTaskAssignees && picDirty) {
        final key = _picEditKey?.trim();
        if (key == null ||
            key.isEmpty ||
            !parent.assigneeIds.contains(key)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Choose a valid Sub-task PIC'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        setState(() => _saving = true);
        try {
          final err = await SupabaseService.updateSubtaskRow(
            subtaskId: st.id,
            picStaffLookupKey: key,
            updaterStaffLookupKey: state.userStaffAppId,
          );
          if (!mounted) return;
          if (err != null) {
            showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
            return;
          }
          final errA = await SupabaseService.replaceSubtaskAttachments(
            subtaskId: st.id,
            rows: _subtaskAttachmentPayload(),
          );
          if (!mounted) return;
          if (errA != null) {
            showCopyableSnackBar(context, errA, backgroundColor: Colors.orange);
            return;
          }
          await _load();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved'),
              backgroundColor: Colors.green,
            ),
          );
        } finally {
          if (mounted) setState(() => _saving = false);
        }
        return;
      }
      if (_isPic(state, st)) {
        setState(() => _saving = true);
        try {
          final errA = await SupabaseService.replaceSubtaskAttachments(
            subtaskId: st.id,
            rows: _subtaskAttachmentPayload(),
          );
          if (!mounted) return;
          if (errA != null) {
            showCopyableSnackBar(context, errA, backgroundColor: Colors.orange);
            return;
          }
          await _load();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved'),
              backgroundColor: Colors.green,
            ),
          );
        } finally {
          if (mounted) setState(() => _saving = false);
        }
        return;
      }
      if (canPic && multiTaskAssignees && !picDirty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No changes to save'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    if (_editStart != null &&
        _editDue != null &&
        DateTime(_editDue!.year, _editDue!.month, _editDue!.day)
            .isBefore(DateTime(_editStart!.year, _editStart!.month, _editStart!.day))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Due date cannot be before start date'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final picKey =
        picDirty && _picEditKey != null && parent.assigneeIds.contains(_picEditKey!)
        ? _picEditKey
        : null;
    setState(() => _saving = true);
    try {
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: st.id,
        subtaskName: _nameController.text.trim(),
        description: _descController.text.trim(),
        priorityDisplay: priorityToDisplayName(_editPriority),
        startDate: _editStart,
        clearStartDate: _editStart == null,
        dueDate: _editDue,
        clearDueDate: _editDue == null,
        picStaffLookupKey: picKey,
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      final errA = await SupabaseService.replaceSubtaskAttachments(
        subtaskId: st.id,
        rows: _subtaskAttachmentPayload(),
      );
      if (!mounted) return;
      if (errA != null) {
        showCopyableSnackBar(context, errA, backgroundColor: Colors.orange);
        return;
      }
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved'), backgroundColor: Colors.green),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit(AppState state, SingularSubtask st) async {
    final link = _firstSubtaskAttachmentUrl()?.trim() ?? '';
    final c = _commentController.text.trim();
    if (link.isEmpty && c.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add attachment and/or comment before submitting.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final e = await SupabaseService.replaceSubtaskAttachments(
        subtaskId: st.id,
        rows: _subtaskAttachmentPayload(),
      );
      if (e != null && mounted) {
        showCopyableSnackBar(context, e, backgroundColor: Colors.orange);
        return;
      }
      if (c.isNotEmpty) {
        final ins = await SupabaseService.insertSubtaskCommentRow(
          subtaskId: st.id,
          description: c,
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (ins.error != null && mounted) {
          showCopyableSnackBar(context, ins.error!, backgroundColor: Colors.orange);
          return;
        }
      }
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: st.id,
        submission: 'Submitted',
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      _commentController.clear();
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Submitted'),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _accept(AppState state, SingularSubtask st) async {
    setState(() => _saving = true);
    try {
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: st.id,
        status: 'Completed',
        submission: 'Accepted',
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accepted'), backgroundColor: Colors.green),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _return(AppState state, SingularSubtask st) async {
    setState(() => _saving = true);
    try {
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: st.id,
        status: 'Incomplete',
        submission: 'Returned',
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Returned'), backgroundColor: Colors.green),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteComment(
    AppState state,
    SingularSubtask st,
    SubtaskCommentRowDisplay c,
  ) async {
    if (!_isCreator(state, st) && !_director) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final err = await SupabaseService.softDeleteSubtaskCommentRow(
      commentId: c.id,
      updaterStaffLookupKey: state.userStaffAppId,
    );
    if (!mounted) return;
    if (err != null) {
      showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
      return;
    }
    await _load();
  }

  Future<void> _deleteSubtask(AppState state, SingularSubtask st) async {
    if (!_isCreator(state, st) && !_director) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete sub-task?'),
        content: const Text('This sub-task will be marked as deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final err = await SupabaseService.markSubtaskDeleted(
        subtaskId: st.id,
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sub-task')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final st = _sub;
    final parent = _parentTask;
    if (st == null || parent == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sub-task')),
        body: const Center(child: Text('Sub-task not found')),
      );
    }

    final creator = _isCreator(state, st);
    final pic = _isPic(state, st);
    final assignee = _isAssignee(state, st);
    final canDel = creator || _director;
    final canSetPic = _canEditSubtaskPic(state, st, parent);
    final multiTaskAssignees = parent.assigneeIds.length > 1;
    final showPicDropdown = canSetPic && multiTaskAssignees;
    final ymd = DateFormat('yyyy-MM-dd');
    final picDropdownValue =
        _picEditKey != null && parent.assigneeIds.contains(_picEditKey)
        ? _picEditKey
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(st.subtaskName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Parent: ${parent.name}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sub-task assignee(s): ${_subtaskAssigneeLine(state, st)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (showPicDropdown) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: picDropdownValue,
                            decoration: const InputDecoration(
                              labelText: 'Sub-task PIC',
                              border: OutlineInputBorder(),
                            ),
                            items: parent.assigneeIds
                                .map(
                                  (id) => DropdownMenuItem(
                                    value: id,
                                    child: Text(
                                      state.assigneeById(id)?.name ?? id,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() => _picEditKey = v);
                                    }
                                  },
                          ),
                        ] else if (st.assigneeIds.length > 1) ...[
                          const SizedBox(height: 8),
                          Text(
                            'PIC: ${_picDisplayName(state, st)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (canSetPic && parent.assigneeIds.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Add assignees on the parent task to choose a PIC.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nameController,
                          readOnly: _saving || !creator,
                          decoration: const InputDecoration(
                            labelText: 'Sub-task name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _descController,
                          readOnly: _saving || !creator,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                          minLines: 4,
                          maxLines: 8,
                        ),
                        const SizedBox(height: 12),
                        if (creator) ...[
                          Text(
                            'Priority',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _priorityToggleButton(
                                label: 'Standard',
                                selected: _editPriority == priorityStandard,
                                enabled: !_saving,
                                onTap: () => setState(
                                  () => _editPriority = priorityStandard,
                                ),
                              ),
                              const SizedBox(width: 12),
                              _priorityToggleButton(
                                label: 'URGENT',
                                selected: _editPriority == priorityUrgent,
                                enabled: !_saving,
                                onTap: () =>
                                    setState(() => _editPriority = priorityUrgent),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ] else
                          Text(
                            'Priority: ${priorityToDisplayName(st.priority)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        if (creator) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Start: ${_editStart != null ? ymd.format(_editStart!) : "—"}',
                                ),
                              ),
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () async {
                                        final d = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              _editStart ?? DateTime.now(),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now().add(
                                            const Duration(days: 365 * 10),
                                          ),
                                        );
                                        if (d != null) {
                                          setState(() => _editStart = d);
                                        }
                                      },
                                child: const Text('Pick'),
                              ),
                              if (_editStart != null)
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() => _editStart = null),
                                  child: const Text('Clear'),
                                ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Due: ${_editDue != null ? ymd.format(_editDue!) : "—"}',
                                ),
                              ),
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () async {
                                        final start = _editStart;
                                        final d = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              _editDue ?? DateTime.now(),
                                          firstDate: start ?? DateTime(2020),
                                          lastDate: DateTime.now().add(
                                            const Duration(days: 365 * 10),
                                          ),
                                        );
                                        if (d != null) {
                                          setState(() => _editDue = d);
                                        }
                                      },
                                child: const Text('Pick'),
                              ),
                              if (_editDue != null)
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() => _editDue = null),
                                  child: const Text('Clear'),
                                ),
                            ],
                          ),
                        ] else ...[
                          if (st.startDate != null)
                            Text('Start: ${ymd.format(st.startDate!)}'),
                          if (st.dueDate != null)
                            Text('Due: ${ymd.format(st.dueDate!)}'),
                        ],
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Status',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sub-task status: ${st.status}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Submission: ${st.submission?.trim().isNotEmpty == true ? st.submission!.trim() : '—'}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Last update by: ${st.updateByStaffName ?? '—'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _subtaskLastUpdatedLine(st.updateDate),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Attachment',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (_canEditSubtaskAttachments(state, st))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _addSubtaskAttachmentRow,
                      icon: const Icon(Icons.add_link_outlined),
                      label: const Text('Add attachment'),
                    ),
                  ),
                const SizedBox(height: 8),
                ...List.generate(_subtaskAttachments.length, (i) {
                  final e = _subtaskAttachments[i];
                  final canEdit = _canEditSubtaskAttachments(state, st);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: e.urlController,
                                readOnly: _saving || !canEdit,
                                decoration: const InputDecoration(
                                  labelText: 'Attachment (hyperlink)',
                                  hintText: 'https://…',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: e.descController,
                                readOnly: _saving || !canEdit,
                                decoration: const InputDecoration(
                                  labelText: 'Attachment description',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (canEdit)
                          IconButton(
                            onPressed: _saving
                                ? null
                                : () => _removeSubtaskAttachmentRow(i),
                            icon: const Icon(Icons.remove_circle_outline),
                            tooltip: 'Remove',
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  'Comments',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentController,
                  readOnly: _saving || !(assignee || creator),
                  textAlignVertical: TextAlignVertical.top,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: (assignee || creator)
                        ? 'Comments'
                        : 'Only assignees can add comments',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(12),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                ..._comments.map(
                  (c) => ListTile(
                    title: Text(c.description),
                    subtitle: Text(
                      '${c.displayStaffName} · ${c.createTimestampUtc ?? ""}',
                    ),
                    trailing:
                        (creator || _director) && !c.isDeleted
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _saving
                                ? null
                                : () => _deleteComment(state, st, c),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ||
                          (!creator &&
                              !assignee &&
                              !(canSetPic && multiTaskAssignees))
                      ? null
                      : () async {
                          if (creator || (canSetPic && multiTaskAssignees)) {
                            await _saveMetadata(state, st);
                          }
                          if ((assignee || creator) &&
                              _commentController.text.trim().isNotEmpty) {
                            await _postComment(state, st);
                          }
                        },
                  child: Text(_saving ? 'Saving…' : 'Update'),
                ),
                if (canDel) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _deleteSubtask(state, st),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (pic && _canPicSubmit(st)) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving ? null : () => _submit(state, st),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSecondaryContainer,
                    ),
                    child: const Text('Submit'),
                  ),
                ],
                if (creator &&
                    (st.submission?.trim().toLowerCase() == 'submitted')) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : () => _accept(state, st),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF298A00),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Accept'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : () => _return(state, st),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0B0094),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Return'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to task'),
                ),
              ],
            ),
          ),
          if (_saving)
            Positioned.fill(
              child: IgnorePointer(
                child: Material(
                  color: Colors.black.withOpacity(0.1),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
