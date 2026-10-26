import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../commencement_status.dart';
import '../../models/project_record.dart';
import '../../models/singular_subtask.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/subproject_record.dart';
import '../../models/task.dart';
import '../../services/database_service.dart';
import '../../services/llm_service.dart';
import '../../utils/attachment_open_bytes.dart';
import '../../utils/hk_time.dart';
import '../../utils/staff_report_export.dart';
import 'asana_assignee_field.dart';
import 'asana_assignee_picker.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';
import 'asana_theme.dart';
import '../asana_landing_screen.dart';

enum AsanaPerformanceViewMode { group, individual }

class AsanaPerformancePanel extends StatefulWidget {
  const AsanaPerformancePanel({
    super.key,
    required this.palette,
    required this.viewMode,
  });

  final AsanaLandingPalette palette;
  final AsanaPerformanceViewMode viewMode;

  @override
  State<AsanaPerformancePanel> createState() => _AsanaPerformancePanelState();
}

class _AsanaPerformancePanelState extends State<AsanaPerformancePanel> {
  bool _loading = true;
  String? _error;
  String _loadedTaskSignature = '';
  List<Task>? _fullTasks;
  List<ProjectRecord>? _fullProjects;
  Map<String, String> _officeIdByStaffKey = {};
  Map<String, String> _officeNameById = {};
  Map<String, String> _canonicalStaffKeyByLookup = {};
  Map<String, List<SingularSubtask>> _subtasksByTaskId = {};
  String? _individualStaffUuid;
  String? _individualAppId;
  String? _individualName;
  List<StaffForAssignment> _scopedStaff = [];
  List<OfficeOptionRow> _pickerOffices = const [];
  List<TeamOptionRow> _pickerTeams = const [];
  String? _selectedIndividualId;
  bool _individualPickedManually = false;
  String? _appliedSelfKey;
  DateTime? _outputRangeStart;
  DateTime? _outputRangeEnd;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final taskIds =
        context
            .read<AppState>()
            .tasks
            .map((t) => t.id.trim())
            .where((id) => id.isNotEmpty)
            .toList()
          ..sort();
    final signature = taskIds.join('|');
    _syncDefaultIndividual(context.read<AppState>());
    if (signature != _loadedTaskSignature) {
      _loadedTaskSignature = signature;
      _load(taskIds);
    }
  }

  Future<void> _load(List<String> taskIds) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<AppState>();
      final ids = taskIds;
      _fullTasks = null;
      _fullProjects = null;
      final picker = await DatabaseService.fetchStaffAssigneePickerData();
      final subtasks =
          await DatabaseService.fetchSubtasksGroupedIncludingDeleted(ids);
      if (!mounted) return;
      final scoped = _withCurrentUser(
        _staffInOffices(picker.staff, state),
        picker.staff,
        state,
      );
      final selected = _chooseIndividual(scoped, state);
      setState(() {
        _officeIdByStaffKey = _officeMapByStaffKey(picker.staff);
        _canonicalStaffKeyByLookup = _canonicalMapByStaffKey(picker.staff);
        _officeNameById = {
          for (final office in picker.offices)
            office.officeId.trim().toLowerCase(): office.officeName.trim(),
        };
        _subtasksByTaskId = subtasks;
        _pickerOffices = picker.offices;
        _pickerTeams = picker.teams;
        _scopedStaff = scoped;
        _appliedSelfKey = _selfKey(state);
        _applyIndividual(selected);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<StaffForAssignment> _staffInOffices(
    List<StaffForAssignment> staff,
    AppState state,
  ) {
    final allowed = state.staffAdminOfficeIds
        .map((id) => id.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toSet();
    final scoped = staff.where((person) {
      final office = person.officeId?.trim().toLowerCase();
      if (office == null || office.isEmpty) return false;
      if (allowed.isEmpty) return state.isSuperAdmin;
      return allowed.contains(office);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return scoped;
  }

  StaffForAssignment? _chooseIndividual(
    List<StaffForAssignment> scoped,
    AppState state,
  ) {
    if (_individualPickedManually) {
      for (final person in scoped) {
        if (person.assigneeId == _selectedIndividualId) return person;
      }
    }
    return _personMatchingSelf(scoped, state) ??
        (scoped.isEmpty ? null : scoped.first);
  }

  List<StaffForAssignment> _withCurrentUser(
    List<StaffForAssignment> scoped,
    List<StaffForAssignment> all,
    AppState state,
  ) {
    final self = _personMatchingSelf(all, state);
    if (self == null) return scoped;
    if (scoped.any((person) => person.assigneeId == self.assigneeId)) {
      return scoped;
    }
    return [...scoped, self]..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  StaffForAssignment? _personMatchingSelf(
    List<StaffForAssignment> staff,
    AppState state,
  ) {
    final appId = state.effectiveStaffAppId?.trim().toLowerCase();
    final uuid = state.effectiveStaffUuid?.trim().toLowerCase();
    for (final person in staff) {
      final assignee = person.assigneeId.trim().toLowerCase();
      final personUuid = person.staffUuid?.trim().toLowerCase();
      final appHit = appId != null &&
          appId.isNotEmpty &&
          (assignee == appId || personUuid == appId);
      final uuidHit = uuid != null &&
          uuid.isNotEmpty &&
          (assignee == uuid || personUuid == uuid);
      if (appHit || uuidHit) return person;
    }
    final name = state.currentStaffDisplayName?.trim().toLowerCase();
    if (name == null || name.isEmpty) return null;
    final named = staff
        .where((person) => person.name.trim().toLowerCase() == name)
        .toList();
    return named.length == 1 ? named.first : null;
  }

  String _selfKey(AppState state) {
    final appId = state.effectiveStaffAppId?.trim() ?? '';
    final uuid = state.effectiveStaffUuid?.trim() ?? '';
    if (appId.isNotEmpty || uuid.isNotEmpty) return '$appId|$uuid';
    return 'name:${state.currentStaffDisplayName ?? ''}';
  }

  void _syncDefaultIndividual(AppState state) {
    final key = _selfKey(state);
    if (key == _appliedSelfKey) return;
    _appliedSelfKey = key;
    _individualPickedManually = false;
    if (_loading || _scopedStaff.isEmpty) return;
    final selected = _chooseIndividual(_scopedStaff, state);
    if (selected?.assigneeId == _selectedIndividualId) return;
    setState(() {
      _outputRangeStart = null;
      _outputRangeEnd = null;
      _applyIndividual(selected);
    });
  }

  void _applyIndividual(StaffForAssignment? person) {
    _selectedIndividualId = person?.assigneeId;
    _individualAppId = person?.assigneeId;
    _individualStaffUuid = person?.staffUuid;
    _individualName = person?.name;
  }

  List<({String id, String name})> _officesInScope(AppState state) {
    final fromGrant = state.staffAdminOfficeIds
        .map((id) => id.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toList();
    final source = fromGrant.isNotEmpty
        ? fromGrant
        : (state.isSuperAdmin ? _officeNameById.keys.toList() : <String>[]);
    source.sort((a, b) {
      final an = (_officeNameById[a] ?? a).toLowerCase();
      final bn = (_officeNameById[b] ?? b).toLowerCase();
      return an.compareTo(bn);
    });
    return [
      for (final id in source)
        (
          id: id,
          name: (_officeNameById[id]?.trim().isNotEmpty == true)
              ? _officeNameById[id]!.trim()
              : id.toUpperCase(),
        ),
    ];
  }

  Map<String, String> _officeMapByStaffKey(List<StaffForAssignment> staff) {
    final map = <String, String>{};
    for (final s in staff) {
      final officeId = s.officeId?.trim();
      if (officeId == null || officeId.isEmpty) continue;
      final appId = s.assigneeId.trim();
      if (appId.isNotEmpty) map[appId.toLowerCase()] = officeId;
      final uuid = s.staffUuid?.trim();
      if (uuid != null && uuid.isNotEmpty) map[uuid.toLowerCase()] = officeId;
    }
    return map;
  }

  Map<String, String> _canonicalMapByStaffKey(List<StaffForAssignment> staff) {
    final map = <String, String>{};
    for (final s in staff) {
      final canonical =
          (s.staffUuid?.trim().isNotEmpty == true
                  ? s.staffUuid!.trim()
                  : s.assigneeId.trim())
              .toLowerCase();
      if (canonical.isEmpty) continue;
      final appId = s.assigneeId.trim().toLowerCase();
      if (appId.isNotEmpty) map[appId] = canonical;
      final uuid = s.staffUuid?.trim().toLowerCase();
      if (uuid != null && uuid.isNotEmpty) map[uuid] = canonical;
    }
    return map;
  }

  bool _projectDeleted(ProjectRecord p) =>
      p.status.trim().toLowerCase() == 'deleted';

  bool _taskDeleted(Task t) =>
      (t.dbStatus ?? '').trim().toLowerCase() == 'deleted';

  bool _subtaskDeleted(SingularSubtask s) =>
      s.status.trim().toLowerCase() == 'deleted';

  bool _taskCompleted(Task t) {
    final status = (t.dbStatus ?? '').trim().toLowerCase();
    return status == 'completed' ||
        status == 'complete' ||
        t.status == TaskStatus.done;
  }

  bool _subtaskCompleted(SingularSubtask s) {
    final status = s.status.trim().toLowerCase();
    return status == 'completed' || status == 'complete';
  }

  bool _belongsToOffice(Iterable<String?> staffKeys, String officeLabel) {
    final target = officeLabel.trim().toLowerCase();
    if (target.isEmpty) return false;
    for (final rawKey in staffKeys) {
      final key = rawKey?.trim().toLowerCase();
      if (key == null || key.isEmpty) continue;
      final officeId = _officeIdByStaffKey[key]?.trim();
      if (officeId == null || officeId.isEmpty) continue;
      final id = officeId.toLowerCase();
      final name = (_officeNameById[id] ?? '').trim().toLowerCase();
      if (id == target || name == target) return true;
      if (id.contains(target) || name.contains(target)) return true;
    }
    return false;
  }

  Iterable<String?> _projectOwnerKeys(ProjectRecord p) {
    if (p.picStaffUuids.isNotEmpty) return p.picStaffUuids;
    return p.assigneeStaffUuids;
  }

  List<Task> _tasksOf(AppState state) => _fullTasks ?? state.tasks;

  List<ProjectRecord> _projectsOf(AppState state) =>
      _fullProjects ?? state.projects;

  Iterable<String?> _taskOwnerKeys(Task t) {
    final pic = t.pic?.trim();
    if (pic != null && pic.isNotEmpty) return [pic];
    return t.assigneeIds;
  }

  Iterable<String?> _subtaskOwnerKeys(SingularSubtask s) {
    final pic = s.pic?.trim();
    if (pic != null && pic.isNotEmpty) return [pic];
    return s.assigneeIds;
  }

  Iterable<String?> _officeKeysForCreatedItem({
    required String? creatorKey,
    required Iterable<String?> ownerKeys,
  }) {
    final creator = creatorKey?.trim();
    if (creator != null && creator.isNotEmpty) return [creator];
    return ownerKeys;
  }

  List<DateTime?> _createdDatesForOffice(String officeLabel, AppState state) {
    final out = <DateTime?>[];
    for (final t in _tasksOf(state).where((t) => !_taskDeleted(t))) {
      if (_belongsToOffice(
        _officeKeysForCreatedItem(
          creatorKey: t.createByAssigneeKey,
          ownerKeys: _taskOwnerKeys(t),
        ),
        officeLabel,
      )) {
        out.add(t.createdAt);
      }
    }
    for (final s
        in _subtasksByTaskId.values
            .expand((list) => list)
            .where((s) => !_subtaskDeleted(s))) {
      if (_belongsToOffice(
        _officeKeysForCreatedItem(
          creatorKey: s.createByStaffId,
          ownerKeys: _subtaskOwnerKeys(s),
        ),
        officeLabel,
      )) {
        out.add(s.createDate);
      }
    }
    return out;
  }

  _PerformanceMetrics _metricsFor(String officeLabel, AppState state) {
    final projects = _projectsOf(state)
        .where((p) => !_projectDeleted(p))
        .where((p) => _belongsToOffice(_projectOwnerKeys(p), officeLabel))
        .toList();
    final tasks = _tasksOf(state)
        .where((t) => !_taskDeleted(t))
        .where((t) => _belongsToOffice(_taskOwnerKeys(t), officeLabel))
        .toList();
    final subtasks = _subtasksByTaskId.values
        .expand((list) => list)
        .where((s) => !_subtaskDeleted(s))
        .where((s) => _belongsToOffice(_subtaskOwnerKeys(s), officeLabel))
        .toList();
    final activeStaff = <String>{};
    void addActive(String? key) {
      final k = key?.trim();
      if (k == null || k.isEmpty) return;
      if (_belongsToOffice([k], officeLabel)) {
        final lower = k.toLowerCase();
        activeStaff.add(_canonicalStaffKeyByLookup[lower] ?? lower);
      }
    }

    for (final t in tasks) {
      addActive(t.pic);
      for (final id in t.assigneeIds) {
        addActive(id);
      }
    }
    for (final s in subtasks) {
      addActive(s.pic);
      for (final id in s.assigneeIds) {
        addActive(id);
      }
    }

    final subprojects = state.subprojects
        .where((s) => !s.isDeleted)
        .where(
          (s) => _belongsToOffice(_subprojectOwnerKeys(s), officeLabel),
        )
        .toList();
    final activeTasks = tasks.where((t) => !_taskCompleted(t)).toList();
    final activeSubtasks = subtasks.where((s) => !_subtaskCompleted(s)).toList();
    final toBeCommenced =
        activeTasks.where((t) => isToBeCommenced(t.commencementStatus)).length +
        activeSubtasks
            .where((s) => isToBeCommenced(s.commencementStatus))
            .length;
    final ongoing = activeTasks.length + activeSubtasks.length - toBeCommenced;

    return _PerformanceMetrics(
      activeProjects: projects.where((p) => !_recordCompleted(p.status)).length,
      activeSubprojects: subprojects.where((s) => !s.isCompleted).length,
      activeTasks: activeTasks.length,
      activeSubtasks: activeSubtasks.length,
      completedWorkItems:
          tasks.where(_taskCompleted).length +
          subtasks.where(_subtaskCompleted).length,
      ongoingWorkItems: ongoing,
      toBeCommencedWorkItems: toBeCommenced,
      activeStaff: activeStaff.length,
    );
  }

  bool _ownedByIndividual(Iterable<String?> keys) {
    for (final key in keys) {
      if (_keyMatchesIndividual(key)) return true;
    }
    return false;
  }

  /// Same eight counts as an office, limited to items this staff member owns.
  _PerformanceMetrics _metricsForIndividual(AppState state) {
    final projects = _projectsOf(state)
        .where((p) => !_projectDeleted(p))
        .where((p) => _ownedByIndividual(_projectOwnerKeys(p)))
        .toList();
    final tasks = _tasksOf(state)
        .where((t) => !_taskDeleted(t))
        .where((t) => _ownedByIndividual(_taskOwnerKeys(t)))
        .toList();
    final subtasks = _subtasksByTaskId.values
        .expand((list) => list)
        .where((s) => !_subtaskDeleted(s))
        .where((s) => _ownedByIndividual(_subtaskOwnerKeys(s)))
        .toList();
    final subprojects = state.subprojects
        .where((s) => !s.isDeleted)
        .where((s) => _ownedByIndividual(_subprojectOwnerKeys(s)))
        .toList();
    final activeStaff = <String>{};
    void addPerson(String? key) {
      final k = key?.trim();
      if (k == null || k.isEmpty) return;
      final lower = k.toLowerCase();
      activeStaff.add(_canonicalStaffKeyByLookup[lower] ?? lower);
    }

    for (final t in tasks) {
      addPerson(t.pic);
      for (final id in t.assigneeIds) {
        addPerson(id);
      }
    }
    for (final s in subtasks) {
      addPerson(s.pic);
      for (final id in s.assigneeIds) {
        addPerson(id);
      }
    }

    final activeTasks = tasks.where((t) => !_taskCompleted(t)).toList();
    final activeSubtasks = subtasks
        .where((s) => !_subtaskCompleted(s))
        .toList();
    final toBeCommenced =
        activeTasks.where((t) => isToBeCommenced(t.commencementStatus)).length +
        activeSubtasks
            .where((s) => isToBeCommenced(s.commencementStatus))
            .length;
    final ongoing = activeTasks.length + activeSubtasks.length - toBeCommenced;
    return _PerformanceMetrics(
      activeProjects: projects.where((p) => !_recordCompleted(p.status)).length,
      activeSubprojects: subprojects.where((s) => !s.isCompleted).length,
      activeTasks: activeTasks.length,
      activeSubtasks: activeSubtasks.length,
      completedWorkItems:
          tasks.where(_taskCompleted).length +
          subtasks.where(_subtaskCompleted).length,
      ongoingWorkItems: ongoing,
      toBeCommencedWorkItems: toBeCommenced,
      activeStaff: activeStaff.length,
    );
  }

  bool _recordCompleted(String status) {
    final value = status.trim().toLowerCase();
    return value == 'completed' || value == 'complete';
  }

  Iterable<String?> _subprojectOwnerKeys(SubprojectRecord subproject) {
    if (subproject.picStaffUuids.isNotEmpty) return subproject.picStaffUuids;
    return subproject.assigneeStaffUuids;
  }

  bool _keyMatchesIndividual(String? value) {
    final v = value?.trim().toLowerCase();
    if (v == null || v.isEmpty) return false;
    final appId = _individualAppId?.trim().toLowerCase();
    final uuid = _individualStaffUuid?.trim().toLowerCase();
    return (appId != null && appId.isNotEmpty && v == appId) ||
        (uuid != null && uuid.isNotEmpty && v == uuid);
  }

  String _monthKey(DateTime? value) {
    if (value == null) return 'No date';
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  String _complexityKey(String? value) {
    final s = value?.trim().toLowerCase();
    return switch (s) {
      'low' => 'Low',
      'medium' => 'Medium',
      'high' => 'High',
      _ => 'Medium',
    };
  }

  _IndividualPerformance _individualPerformance(AppState state) {
    final byMonth = <String, _MonthlyIndividualPerformance>{};

    _MonthlyIndividualPerformance month(String key) {
      return byMonth.putIfAbsent(key, () => _MonthlyIndividualPerformance(key));
    }

    final scored = <_ScoredCompletion>[];
    void countCompleted({
      required DateTime? completedAt,
      required String? complexity,
      required bool completed,
      required bool isPic,
    }) {
      if (!completed || !isPic) return;
      final key = _complexityKey(complexity);
      month(_monthKey(completedAt)).completedOutput.increment(key);
      scored.add(_ScoredCompletion(date: completedAt, complexity: key));
    }

    for (final t in _tasksOf(state).where((t) => !_taskDeleted(t))) {
      countCompleted(
        completedAt: t.completionDate ?? t.updateDate ?? t.lastUpdated,
        complexity: t.complexity,
        completed: _taskCompleted(t),
        isPic: _keyMatchesIndividual(t.pic),
      );
    }

    final subtasks = _subtasksByTaskId.values
        .expand((list) => list)
        .where((s) => !_subtaskDeleted(s));
    for (final s in subtasks) {
      countCompleted(
        completedAt: s.completionDate ?? s.updateDate,
        complexity: s.complexity,
        completed: _subtaskCompleted(s),
        isPic: _keyMatchesIndividual(s.pic),
      );
    }

    final months = byMonth.values.toList()
      ..sort((a, b) => b.month.compareTo(a.month));
    return _IndividualPerformance(
      displayName: _individualName?.trim().isNotEmpty == true
          ? _individualName!.trim()
          : 'Staff',
      months: months,
      scored: scored,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.showPerformanceNav) {
      return ColoredBox(color: widget.palette.content);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load performance data.\n$_error',
          textAlign: TextAlign.center,
          style: asanaTextStyle(
            Theme.of(context).textTheme.bodyMedium,
            color: Colors.red.shade700,
          ),
        ),
      );
    }

    final offices = _officesInScope(state);
    final individual = _individualPerformance(state);
    const seriesColors = <Color>[
      Color(0xFFF06A6A),
      Color(0xFF1565C0),
      Color(0xFF2E7D32),
      Color(0xFF6A1B9A),
      Color(0xFFEF6C00),
      Color(0xFF00838F),
    ];

    final titleNarrow = MediaQuery.sizeOf(context).width < 600;
    final pageTitle = widget.viewMode == AsanaPerformanceViewMode.group
        ? 'Group Performance'
        : 'Individual Performance';
    return ColoredBox(
      color: widget.palette.content,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        children: [
          Text(
            pageTitle,
            style: asanaTextStyle(
              Theme.of(context).textTheme.headlineMedium,
              fontSize: titleNarrow ? 22 : 32,
              fontWeight: FontWeight.w700,
              color: kAsanaTextPrimary,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 28),
          if (widget.viewMode == AsanaPerformanceViewMode.group) ...[
            _OfficePerformanceSection(
              offices: [
                for (final office in offices)
                  (
                    title: office.name,
                    metrics: _metricsFor(office.id, state),
                  ),
              ],
              palette: widget.palette,
            ),
            const SizedBox(height: 18),
            _CreatedVolumeSection(
              series: [
                for (var i = 0; i < offices.length; i++)
                  _OfficeCreatedSeries(
                    label: offices[i].name,
                    color: seriesColors[i % seriesColors.length],
                    dates: _createdDatesForOffice(offices[i].id, state),
                  ),
              ],
              palette: widget.palette,
            ),
          ],
          if (widget.viewMode == AsanaPerformanceViewMode.individual)
            _IndividualPerformanceBlock(
              performance: individual,
              metrics: _metricsForIndividual(state),
              staffChoices: _scopedStaff,
              offices: _pickerOffices,
              teams: _pickerTeams,
              selectedStaffId: _selectedIndividualId,
              onStaffSelected: (id) {
                StaffForAssignment? person;
                for (final row in _scopedStaff) {
                  if (row.assigneeId == id) person = row;
                }
                setState(() {
                  _individualPickedManually = true;
                  _outputRangeStart = null;
                  _outputRangeEnd = null;
                  _applyIndividual(person);
                });
              },
              outputRangeStart: _outputRangeStart,
              outputRangeEnd: _outputRangeEnd,
              onOutputRangeChanged: (start, end) {
                setState(() {
                  _outputRangeStart = start;
                  _outputRangeEnd = end;
                });
              },
              onWriteReport: _writeStaffReport,
              palette: widget.palette,
            ),
        ],
      ),
    );
  }

  bool _staffInvolved(String? pic, List<String> assigneeIds) {
    if (_keyMatchesIndividual(pic)) return true;
    for (final id in assigneeIds) {
      if (_keyMatchesIndividual(id)) return true;
    }
    return false;
  }

  String _staffRole(String? pic, List<String> assigneeIds) {
    final isPic = _keyMatchesIndividual(pic);
    final isAssignee = assigneeIds.any(_keyMatchesIndividual);
    if (isPic && isAssignee) return 'PIC and assignee';
    if (isPic) return 'PIC';
    return 'assignee';
  }

  bool _dueInReportRange(
    DateTime? due, {
    required bool all,
    required _CreatedChartGrain grain,
    required DateTime start,
    required DateTime end,
  }) {
    if (all) return true;
    final day = _hkDateOnly(due);
    if (day == null) return false;
    final bucket = _alignCreatedGrainStart(day, grain);
    return !bucket.isBefore(start) && !bucket.isAfter(end);
  }

  String _clipReportText(String raw) {
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 160) return text;
    return '${text.substring(0, 157)}...';
  }

  Future<String> _writeStaffReport({
    required bool all,
    required _CreatedChartGrain grain,
    required DateTime start,
    required DateTime end,
  }) async {
    final evidence = _staffReportEvidence(
      context.read<AppState>(),
      all: all,
      grain: grain,
      start: start,
      end: end,
    );
    if (evidence == null) {
      return 'No tasks or sub-tasks are due in this period for this staff member.';
    }
    return LlmService.writeStaffPerformanceReport(
      staffName: _individualName?.trim().isNotEmpty == true
          ? _individualName!.trim()
          : 'Staff',
      evidence: evidence,
    );
  }

  String? _staffReportEvidence(
    AppState state, {
    required bool all,
    required _CreatedChartGrain grain,
    required DateTime start,
    required DateTime end,
  }) {
    bool inRange(DateTime? due) => _dueInReportRange(
      due,
      all: all,
      grain: grain,
      start: start,
      end: end,
    );
    final tasks = _tasksOf(state)
        .where((t) => !_taskDeleted(t))
        .where((t) => _staffInvolved(t.pic, t.assigneeIds))
        .where((t) => inRange(t.dueDate))
        .toList();
    final subtasks = _subtasksByTaskId.values
        .expand((list) => list)
        .where((s) => !_subtaskDeleted(s))
        .where((s) => _staffInvolved(s.pic, s.assigneeIds))
        .where((s) => inRange(s.dueDate))
        .toList();
    if (tasks.isEmpty && subtasks.isEmpty) return null;

    final taskById = {for (final t in _tasksOf(state)) t.id: t};
    final projectById = {for (final p in _projectsOf(state)) p.id: p};
    final subprojectById = {for (final s in state.subprojects) s.id: s};
    final projectIds = <String>{};
    final subprojectIds = <String>{};
    void takeParents(Task? task) {
      final projectId = task?.projectId?.trim();
      if (projectId != null && projectId.isNotEmpty) projectIds.add(projectId);
      final subprojectId = task?.subprojectId?.trim();
      if (subprojectId != null && subprojectId.isNotEmpty) {
        subprojectIds.add(subprojectId);
      }
    }

    for (final task in tasks) {
      takeParents(task);
    }
    for (final subtask in subtasks) {
      takeParents(taskById[subtask.taskId]);
    }

    var score = 0;
    var scoreLow = 0;
    var scoreMedium = 0;
    var scoreHigh = 0;
    void addScore(String? complexity, bool completed, bool isPic) {
      if (!completed || !isPic) return;
      switch (_complexityKey(complexity)) {
        case 'Low':
          scoreLow++;
          score += 1;
        case 'Medium':
          scoreMedium++;
          score += 2;
        case 'High':
          scoreHigh++;
          score += 3;
      }
    }

    final taskMix = _ComplexityCounts();
    final subtaskMix = _ComplexityCounts();
    for (final task in tasks) {
      taskMix.increment(_complexityKey(task.complexity));
      addScore(task.complexity, _taskCompleted(task), _keyMatchesIndividual(task.pic));
    }
    for (final subtask in subtasks) {
      subtaskMix.increment(_complexityKey(subtask.complexity));
      addScore(
        subtask.complexity,
        _subtaskCompleted(subtask),
        _keyMatchesIndividual(subtask.pic),
      );
    }

    String dueLabel(DateTime? due) {
      final day = _hkDateOnly(due);
      if (day == null) return 'no due date';
      return DateFormat('d MMM yyyy').format(day);
    }

    String statusOfTask(Task task) {
      final db = (task.dbStatus ?? '').trim();
      if (db.isNotEmpty) return db;
      return taskStatusDisplayNames[task.status] ?? '';
    }

    const cap = 40;
    final shownTasks = tasks.take(cap).toList();
    final shownSubtasks = subtasks.take(cap).toList();
    final period = all
        ? 'All due dates'
        : 'Due from ${_createdGrainLabel(start, grain)} to ${_createdGrainLabel(end, grain)}';
    final buffer = StringBuffer()
      ..writeln('Period: $period')
      ..writeln(
        all
            ? 'Included items are every task and sub-task where this person is assignee or PIC. Projects and sub-projects are only those linked to these items.'
            : 'Included items are tasks and sub-tasks where this person is assignee or PIC, and whose due date is in the period. Projects and sub-projects are only those linked to these items.',
      )
      ..writeln()
      ..writeln(
        'Capability score (completed items where this person is PIC; Low 1, Medium 2, High 3; a task weighs the same as a sub-task):',
      )
      ..writeln('Score: $score')
      ..writeln('Low: $scoreLow')
      ..writeln('Medium: $scoreMedium')
      ..writeln('High: $scoreHigh')
      ..writeln()
      ..writeln(
        'Kind of work in this period, counting every included item: tasks ${taskMix.total} (Low ${taskMix.low}, Medium ${taskMix.medium}, High ${taskMix.high}); sub-tasks ${subtaskMix.total} (Low ${subtaskMix.low}, Medium ${subtaskMix.medium}, High ${subtaskMix.high}).',
      )
      ..writeln()
      ..writeln('Projects:');
    if (projectIds.isEmpty) {
      buffer.writeln('- None');
    }
    String projectNameFor(String id) {
      final stored = projectById[id]?.name.trim() ?? '';
      if (stored.isNotEmpty) return stored;
      for (final task in tasks) {
        if (task.projectId == id &&
            (task.projectName?.trim().isNotEmpty ?? false)) {
          return task.projectName!.trim();
        }
      }
      return id;
    }

    for (final id in projectIds) {
      final project = projectById[id];
      final name = projectNameFor(id);
      final description = _clipReportText(project?.description ?? '');
      buffer.writeln('- $name');
      if (description.isNotEmpty) buffer.writeln('  $description');
    }
    buffer.writeln();
    buffer.writeln('Sub-projects:');
    if (subprojectIds.isEmpty) buffer.writeln('- None');
    for (final id in subprojectIds) {
      final subproject = subprojectById[id];
      final name = subproject?.name.trim().isNotEmpty == true
          ? subproject!.name.trim()
          : id;
      final parent = subproject == null
          ? ''
          : (projectById[subproject.projectId]?.name.trim() ?? '');
      final description = _clipReportText(subproject?.description ?? '');
      buffer.writeln(parent.isEmpty ? '- $name' : '- $name (project: $parent)');
      if (description.isNotEmpty) buffer.writeln('  $description');
    }
    buffer.writeln();
    buffer.writeln('Tasks:');
    for (final task in shownTasks) {
      buffer.writeln(
        '- ${task.name.trim().isEmpty ? '(Unnamed task)' : task.name.trim()} | ${_staffRole(task.pic, task.assigneeIds)} | ${_complexityKey(task.complexity)} | ${statusOfTask(task)} | due ${dueLabel(task.dueDate)} | project ${task.projectName?.trim().isNotEmpty == true ? task.projectName!.trim() : '—'} | sub-project ${task.subprojectName?.trim().isNotEmpty == true ? task.subprojectName!.trim() : '—'}',
      );
      final description = _clipReportText(task.description);
      if (description.isNotEmpty) buffer.writeln('  $description');
    }
    if (tasks.length > shownTasks.length) {
      buffer.writeln('- ${tasks.length - shownTasks.length} more tasks not listed');
    }
    buffer.writeln();
    buffer.writeln('Sub-tasks:');
    for (final subtask in shownSubtasks) {
      final parent = taskById[subtask.taskId];
      buffer.writeln(
        '- ${subtask.subtaskName.trim().isEmpty ? '(Unnamed sub-task)' : subtask.subtaskName.trim()} | ${_staffRole(subtask.pic, subtask.assigneeIds)} | ${_complexityKey(subtask.complexity)} | ${subtask.status.trim()} | due ${dueLabel(subtask.dueDate)} | task ${parent?.name.trim().isNotEmpty == true ? parent!.name.trim() : '—'}',
      );
      final description = _clipReportText(subtask.description);
      if (description.isNotEmpty) buffer.writeln('  $description');
    }
    if (subtasks.length > shownSubtasks.length) {
      buffer.writeln(
        '- ${subtasks.length - shownSubtasks.length} more sub-tasks not listed',
      );
    }
    return buffer.toString();
  }
}

class _ComplexityCounts {
  int low = 0;
  int medium = 0;
  int high = 0;

  int get total => low + medium + high;
  int get weightedScore => low + medium * 2 + high * 3;
  int get maxComplexityCount =>
      [low, medium, high, 1].reduce((a, b) => a > b ? a : b);

  void increment(String complexity) {
    switch (complexity) {
      case 'Low':
        low++;
      case 'Medium':
        medium++;
      case 'High':
        high++;
      default:
        medium++;
    }
  }
}

class _MonthlyIndividualPerformance {
  _MonthlyIndividualPerformance(this.month);

  final String month;
  final completedOutput = _ComplexityCounts();

  int get outputScore => completedOutput.weightedScore;
}

class _ScoredCompletion {
  const _ScoredCompletion({required this.date, required this.complexity});

  final DateTime? date;
  final String complexity;

  int get weight => switch (complexity) {
    'Low' => 1,
    'High' => 3,
    _ => 2,
  };
}

class _IndividualPerformance {
  const _IndividualPerformance({
    required this.displayName,
    required this.months,
    required this.scored,
  });
  final String displayName;
  final List<_MonthlyIndividualPerformance> months;
  final List<_ScoredCompletion> scored;
}


class _WorkOutputScoreInfoButton extends StatelessWidget {
  const _WorkOutputScoreInfoButton({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return _PerformanceInfoButton(
      palette: palette,
      title: 'Output Score',
      content:
          'Each completed task and each completed sub-task where this staff member is PIC adds the same score. The score uses complexity only.',
      tableRows: const [
        ['Complexity', 'Weight'],
        ['Low', '1'],
        ['Medium', '2'],
        ['High', '3'],
      ],
    );
  }
}

class _IndividualStaffField extends StatefulWidget {
  const _IndividualStaffField({
    required this.offices,
    required this.teams,
    required this.staff,
    required this.selectedId,
    required this.onSelected,
    required this.nameStyle,
  });

  final List<OfficeOptionRow> offices;
  final List<TeamOptionRow> teams;
  final List<StaffForAssignment> staff;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final TextStyle nameStyle;

  @override
  State<_IndividualStaffField> createState() => _IndividualStaffFieldState();
}

class _IndividualStaffFieldState extends State<_IndividualStaffField> {
  final LayerLink _anchor = LayerLink();
  late final ValueNotifier<AsanaAssigneePickerSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = ValueNotifier(_snapshotOf());
  }

  @override
  void didUpdateWidget(covariant _IndividualStaffField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _snapshot.value = _snapshotOf();
  }

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

  AsanaAssigneePickerSnapshot _snapshotOf() {
    final officeIds = {
      for (final person in widget.staff)
        if ((person.officeId ?? '').trim().isNotEmpty)
          person.officeId!.trim().toLowerCase(),
    };
    final teamIds = {
      for (final person in widget.staff)
        if ((person.teamId ?? '').trim().isNotEmpty)
          person.teamId!.trim().toLowerCase(),
    };
    return AsanaAssigneePickerSnapshot(
      offices: widget.offices
          .where((office) => officeIds.contains(office.officeId.trim().toLowerCase()))
          .toList(),
      teams: widget.teams
          .where((team) => teamIds.contains(team.teamId.trim().toLowerCase()))
          .toList(),
      staff: widget.staff,
    );
  }

  Future<void> _open(BuildContext anchorContext) {
    final id = widget.selectedId?.trim();
    return showAsanaAssigneePicker(
      anchorLink: _anchor,
      anchorContext: anchorContext,
      snapshot: _snapshot,
      selectedIds: {if (id != null && id.isNotEmpty) id},
      singleSelect: true,
      minPanelWidth: 420,
      onSelectionChanged: (ids) {
        if (ids.isEmpty) return;
        widget.onSelected(ids.first);
      },
    );
  }

  double _fieldWidth(BuildContext context) {
    var width = _textWidth('Select staff', asanaDetailValueStyle(context));
    for (final person in widget.staff) {
      final name = person.name.trim();
      if (name.isEmpty) continue;
      final measured = _textWidth(name, widget.nameStyle);
      if (measured > width) width = measured;
    }
    return width + 36;
  }

  double _textWidth(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    StaffForAssignment? person;
    for (final row in widget.staff) {
      if (row.assigneeId == widget.selectedId) person = row;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _fieldWidth(context)),
      child: AsanaAssigneeFieldValue(
        anchorLink: _anchor,
        assignees: [
          if (person != null) (id: person.assigneeId, name: person.name),
        ],
        canEdit: widget.staff.isNotEmpty,
        emptyPlaceholder: 'Select staff',
        showAddButtonWhenNotEmpty: false,
        nameStyle: widget.nameStyle,
        onOpenPicker: _open,
      ),
    );
  }
}

class _IndividualPerformanceBlock extends StatelessWidget {
  const _IndividualPerformanceBlock({
    required this.performance,
    required this.metrics,
    required this.staffChoices,
    required this.offices,
    required this.teams,
    required this.selectedStaffId,
    required this.onStaffSelected,
    required this.outputRangeStart,
    required this.outputRangeEnd,
    required this.onOutputRangeChanged,
    required this.onWriteReport,
    required this.palette,
  });

  final _IndividualPerformance performance;
  final _PerformanceMetrics metrics;
  final List<StaffForAssignment> staffChoices;
  final List<OfficeOptionRow> offices;
  final List<TeamOptionRow> teams;
  final String? selectedStaffId;
  final ValueChanged<String> onStaffSelected;
  final DateTime? outputRangeStart;
  final DateTime? outputRangeEnd;
  final void Function(DateTime? start, DateTime? end) onOutputRangeChanged;
  final Future<String> Function({
    required bool all,
    required _CreatedChartGrain grain,
    required DateTime start,
    required DateTime end,
  }) onWriteReport;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final titleStyle = asanaTextStyle(
      Theme.of(context).textTheme.titleLarge,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
      height: 1.2,
    );
    final totals = _outputTotals(
      performance.scored,
      outputRangeStart,
      outputRangeEnd,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _IndividualSectionCard(
          palette: palette,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Staff - ', style: titleStyle),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _IndividualStaffField(
                        offices: offices,
                        teams: teams,
                        staff: staffChoices,
                        selectedId: selectedStaffId,
                        onSelected: onStaffSelected,
                        nameStyle: titleStyle!,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _PerformanceCardsLayout(metrics: metrics, palette: palette),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _IndividualSectionCard(
          palette: palette,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Work Output', style: titleStyle),
                  const SizedBox(width: 4),
                  _WorkOutputScoreInfoButton(palette: palette),
                ],
              ),
              const SizedBox(height: 18),
              _PerformanceCardsLayout(
                palette: palette,
                cards: [
                  ('Score', totals.score),
                  ('# of low', totals.low),
                  ('# of medium', totals.medium),
                  ('# of high', totals.high),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ScoreTrendSection(
          items: performance.scored,
          palette: palette,
          onRangeChanged: onOutputRangeChanged,
        ),
        const SizedBox(height: 18),
        _StaffReportSection(
          key: ValueKey<String>(selectedStaffId ?? ''),
          palette: palette,
          staffName: performance.displayName,
          onWriteReport: onWriteReport,
        ),
      ],
    );
  }
}

class _IndividualSectionCard extends StatelessWidget {
  const _IndividualSectionCard({required this.palette, required this.child});

  final AsanaLandingPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.listSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: child,
      ),
    );
  }
}

({int score, int low, int medium, int high}) _outputTotals(
  List<_ScoredCompletion> items,
  DateTime? start,
  DateTime? end,
) {
  var low = 0;
  var medium = 0;
  var high = 0;
  final from = start == null ? null : DateTime(start.year, start.month, start.day);
  final to = end == null ? null : DateTime(end.year, end.month, end.day);
  for (final item in items) {
    if (from != null || to != null) {
      final day = _hkDateOnly(item.date);
      if (day == null) continue;
      if (from != null && day.isBefore(from)) continue;
      if (to != null && day.isAfter(to)) continue;
    }
    switch (item.complexity) {
      case 'Low':
        low++;
      case 'High':
        high++;
      default:
        medium++;
    }
  }
  return (
    score: low + medium * 2 + high * 3,
    low: low,
    medium: medium,
    high: high,
  );
}

class _PerformanceInfoButton extends StatelessWidget {
  const _PerformanceInfoButton({
    required this.palette,
    required this.title,
    required this.content,
    this.tableRows = const [],
  });

  final AsanaLandingPalette palette;
  final String title;
  final String content;
  final List<List<String>> tableRows;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'What does this mean?',
      child: IconButton(
        onPressed: () => _showInfo(context),
        icon: Icon(Icons.info_outline, size: 17, color: palette.accent),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        splashRadius: 16,
      ),
    );
  }

  Future<void> _showInfo(BuildContext context) async {
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: palette.panelBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFEDEAE9), width: 1),
        ),
        elevation: 12,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                title,
                style: asanaTextStyle(
                  theme.textTheme.titleMedium,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kAsanaTextPrimary,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                content,
                style: asanaTextStyle(
                  theme.textTheme.bodyMedium,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: kAsanaTextSecondary,
                  height: 1.4,
                ),
              ),
              if (tableRows.isNotEmpty) ...[
                const SizedBox(height: 14),
                Table(
                  border: TableBorder.all(color: const Color(0xFFE5E7EB)),
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                    1: FlexColumnWidth(1),
                  },
                  children: [
                    for (var i = 0; i < tableRows.length; i++)
                      TableRow(
                        decoration: BoxDecoration(
                          color: i == 0
                              ? palette.accent.withValues(alpha: 0.08)
                              : Colors.transparent,
                        ),
                        children: [
                          for (final cell in tableRows[i])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Text(
                                cell,
                                style: asanaTextStyle(
                                  theme.textTheme.bodySmall,
                                  fontWeight: i == 0
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: i == 0
                                      ? kAsanaTextPrimary
                                      : kAsanaTextSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CreatedChartGrain { month, week, day }

class _OfficeCreatedSeries {
  const _OfficeCreatedSeries({
    required this.label,
    required this.color,
    required this.dates,
  });

  final String label;
  final Color color;
  final List<DateTime?> dates;
}

class _CreatedVolumePoint {
  const _CreatedVolumePoint({required this.label, required this.values});

  final String label;
  final List<int> values;
}

DateTime? _hkDateOnly(DateTime? stored) {
  if (stored == null) return null;
  final hk = stored.toUtc().add(const Duration(hours: 8));
  return DateTime(hk.year, hk.month, hk.day);
}

DateTime _weekStartMonday(DateTime d) {
  return DateTime(
    d.year,
    d.month,
    d.day,
  ).subtract(Duration(days: d.weekday - DateTime.monday));
}

DateTime _alignCreatedGrainStart(DateTime d, _CreatedChartGrain grain) {
  switch (grain) {
    case _CreatedChartGrain.month:
      return DateTime(d.year, d.month, 1);
    case _CreatedChartGrain.week:
      return _weekStartMonday(d);
    case _CreatedChartGrain.day:
      return DateTime(d.year, d.month, d.day);
  }
}

DateTime _createdGrainNext(DateTime d, _CreatedChartGrain grain) {
  switch (grain) {
    case _CreatedChartGrain.month:
      return DateTime(d.year, d.month + 1, 1);
    case _CreatedChartGrain.week:
      return d.add(const Duration(days: 7));
    case _CreatedChartGrain.day:
      return d.add(const Duration(days: 1));
  }
}

String _createdGrainKey(DateTime d, _CreatedChartGrain grain) {
  final a = _alignCreatedGrainStart(d, grain);
  switch (grain) {
    case _CreatedChartGrain.month:
      return '${a.year}-${a.month.toString().padLeft(2, '0')}';
    case _CreatedChartGrain.week:
    case _CreatedChartGrain.day:
      return '${a.year}-${a.month.toString().padLeft(2, '0')}-${a.day.toString().padLeft(2, '0')}';
  }
}

const _reportMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _reportMonthText(DateTime d) => '${d.year} ${_reportMonthNames[d.month - 1]}';

String _reportDayText(DateTime d) =>
    '${_reportMonthNames[d.month - 1]} ${d.day}, ${d.year}';

String _reportStampMonth(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}';

String _reportStampDay(DateTime d) =>
    '${_reportStampMonth(d)}${d.day.toString().padLeft(2, '0')}';

String _createdGrainLabel(DateTime d, _CreatedChartGrain grain) {
  final a = _alignCreatedGrainStart(d, grain);
  switch (grain) {
    case _CreatedChartGrain.month:
      return DateFormat('MMM yyyy').format(a);
    case _CreatedChartGrain.week:
      return 'Week of ${DateFormat('MMM d, yyyy').format(a)}';
    case _CreatedChartGrain.day:
      return DateFormat('MMM d, yyyy').format(a);
  }
}

List<DateTime> _createdGrainSteps(
  DateTime start,
  DateTime end,
  _CreatedChartGrain grain,
) {
  var cursor = _alignCreatedGrainStart(start, grain);
  final last = _alignCreatedGrainStart(end, grain);
  final out = <DateTime>[];
  while (!cursor.isAfter(last)) {
    out.add(cursor);
    cursor = _createdGrainNext(cursor, grain);
  }
  return out;
}

List<_CreatedVolumePoint> _createdVolumePoints({
  required List<List<DateTime?>> seriesDates,
  required _CreatedChartGrain grain,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final start = _alignCreatedGrainStart(rangeStart, grain);
  final last = _alignCreatedGrainStart(rangeEnd, grain);
  final counts = [
    for (final _ in seriesDates) <String, int>{},
  ];
  final keys = <String>[];
  final labels = <String, String>{};
  for (final cursor in _createdGrainSteps(start, last, grain)) {
    final key = _createdGrainKey(cursor, grain);
    keys.add(key);
    labels[key] = switch (grain) {
      _CreatedChartGrain.month => DateFormat('MMM yyyy').format(cursor),
      _CreatedChartGrain.week ||
      _CreatedChartGrain.day => DateFormat('MMM d').format(cursor),
    };
    for (final into in counts) {
      into[key] = 0;
    }
  }

  void tally(List<DateTime?> dates, Map<String, int> into) {
    for (final raw in dates) {
      final d = _hkDateOnly(raw);
      if (d == null) continue;
      final key = _createdGrainKey(d, grain);
      if (!into.containsKey(key)) continue;
      into[key] = (into[key] ?? 0) + 1;
    }
  }

  for (var i = 0; i < seriesDates.length; i++) {
    tally(seriesDates[i], counts[i]);
  }
  return [
    for (final key in keys)
      _CreatedVolumePoint(
        label: labels[key] ?? key,
        values: [for (final into in counts) into[key] ?? 0],
      ),
  ];
}

class _StaffReportSection extends StatefulWidget {
  const _StaffReportSection({
    super.key,
    required this.palette,
    required this.staffName,
    required this.onWriteReport,
  });

  final AsanaLandingPalette palette;
  final String staffName;
  final Future<String> Function({
    required bool all,
    required _CreatedChartGrain grain,
    required DateTime start,
    required DateTime end,
  }) onWriteReport;

  @override
  State<_StaffReportSection> createState() => _StaffReportSectionState();
}

class _StaffReportSectionState extends State<_StaffReportSection> {
  _CreatedChartGrain _grain = _CreatedChartGrain.month;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  bool _writing = false;
  final _report = TextEditingController();

  @override
  void dispose() {
    _report.dispose();
    super.dispose();
  }

  DateTime get _today => HkTime.todayDateOnlyHk();

  DateTime get _boundStart => DateTime(_today.year - 3, _today.month, 1);
  DateTime get _boundEnd => DateTime(_today.year + 2, _today.month, 1);

  DateTime get _effectiveStart {
    final raw = _rangeStart ?? _boundStart;
    final aligned = _alignCreatedGrainStart(raw, _grain);
    if (aligned.isAfter(_boundEnd)) return _boundEnd;
    return aligned;
  }

  DateTime get _effectiveEnd {
    final raw = _rangeEnd ?? _boundEnd;
    final aligned = _alignCreatedGrainStart(raw, _grain);
    if (aligned.isBefore(_effectiveStart)) return _effectiveStart;
    return aligned;
  }

  bool get _all => _rangeStart == null && _rangeEnd == null;

  String? get _reportRangeLabel {
    if (_all) return null;
    if (_grain == _CreatedChartGrain.day) {
      return 'from ${_reportDayText(_effectiveStart)} to ${_reportDayText(_effectiveEnd)}';
    }
    return 'from ${_reportMonthText(_effectiveStart)} to ${_reportMonthText(_effectiveEnd)}';
  }

  String _reportFileName({required bool asPdf}) {
    final name = widget.staffName.trim().isEmpty
        ? 'Staff'
        : widget.staffName.trim().replaceAll(' ', '_');
    final extension = asPdf ? 'pdf' : 'docx';
    if (_all) return 'project_tracker_report_$name.$extension';
    final from = _grain == _CreatedChartGrain.day
        ? _reportStampDay(_effectiveStart)
        : _reportStampMonth(_effectiveStart);
    final to = _grain == _CreatedChartGrain.day
        ? _reportStampDay(_effectiveEnd)
        : _reportStampMonth(_effectiveEnd);
    return 'project_tracker_report_${name}_${from}_to_$to.$extension';
  }

  ButtonStyle _accentButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: widget.palette.accent,
      foregroundColor: Colors.white,
      disabledBackgroundColor: widget.palette.accent.withValues(alpha: 0.6),
      disabledForegroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  StaffReportDocument get _reportDocument {
    final name = widget.staffName.trim().isEmpty ? 'Staff' : widget.staffName.trim();
    return StaffReportDocument(
      staffName: name,
      rangeLabel: _reportRangeLabel,
      body: _report.text,
    );
  }

  Future<void> _downloadReport({required bool asPdf}) async {
    if (_report.text.trim().isEmpty || _writing) return;
    try {
      final document = _reportDocument;
      final bytes = asPdf
          ? await staffReportPdf(document)
          : staffReportDocx(document);
      final contentType = asPdf
          ? 'application/pdf'
          : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      final saved = await openAttachmentBytesInSystemViewer(
        bytes,
        contentType,
        _reportFileName(asPdf: asPdf),
      );
      if (!saved && mounted) {
        _showDownloadError();
      }
    } catch (_) {
      if (!mounted) return;
      _showDownloadError();
    }
  }

  void _showDownloadError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not download the report.')),
    );
  }

  Future<void> _pickRange(BuildContext anchorContext) async {
    if (_grain == _CreatedChartGrain.month) {
      final picked = await showAsanaAnchoredMonthRangePicker(
        anchorContext: anchorContext,
        startMonth: _rangeStart == null ? _today : _effectiveStart,
        endMonth: _rangeEnd == null ? _today : _effectiveEnd,
        helpText: 'From and to',
        firstDate: _boundStart,
        lastDate: _boundEnd,
        allowClear: false,
        requireBothEnds: true,
        emptyHint: 'Select the from month, then the to month.',
        pendingEndHint: 'Select the to month',
        selectedPrefix: '',
      );
      if (picked == null || picked.cleared || picked.range == null || !mounted) {
        return;
      }
      _applyRange(picked.range!.start, picked.range!.end);
      return;
    }
    final picked = await showAsanaAnchoredDateRangePicker(
      anchorContext: anchorContext,
      start: _rangeStart ?? _today,
      end: _rangeEnd ?? _today,
      helpText: 'From and to',
      firstDate: _boundStart,
      lastDate: _boundEnd,
      requireBothEnds: true,
    );
    if (picked == null || !mounted) return;
    _applyRange(picked.start, picked.end);
  }

  void _applyRange(DateTime startRaw, DateTime endRaw) {
    setState(() {
      var start = _alignCreatedGrainStart(startRaw, _grain);
      var end = _alignCreatedGrainStart(endRaw, _grain);
      if (start.isAfter(end)) {
        final tmp = start;
        start = end;
        end = tmp;
      }
      _rangeStart = start;
      _rangeEnd = end;
    });
  }

  Future<void> _write() async {
    setState(() => _writing = true);
    try {
      final text = await widget.onWriteReport(
        all: _all,
        grain: _grain,
        start: _effectiveStart,
        end: _effectiveEnd,
      );
      if (!mounted) return;
      setState(() => _report.text = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _report.text = e.toString());
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = asanaTextStyle(
      Theme.of(context).textTheme.titleLarge,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
      height: 1.2,
    );
    final fromLabel = _all ? 'All' : _createdGrainLabel(_effectiveStart, _grain);
    final toLabel = _all ? 'All' : _createdGrainLabel(_effectiveEnd, _grain);
    return Material(
      color: widget.palette.listSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Staff report', style: titleStyle),
            const SizedBox(height: 6),
            Text(
              'A written report for this staff member, using tasks and sub-tasks due in the selected period and the projects and sub-projects those items belong to.',
              style: asanaTextStyle(
                Theme.of(context).textTheme.bodySmall,
                color: kAsanaTextSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _CreatedGrainToggle(
                  grain: _grain,
                  showWeek: false,
                  onChanged: (value) => setState(() {
                    _grain = value;
                    _rangeStart = null;
                    _rangeEnd = null;
                  }),
                  palette: widget.palette,
                ),
                Text(
                  'From',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodySmall,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextSecondary,
                  ),
                ),
                _CreatedRangeButton(label: fromLabel, onPressed: _pickRange),
                Text(
                  'To',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodySmall,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextSecondary,
                  ),
                ),
                _CreatedRangeButton(label: toLabel, onPressed: _pickRange),
                TextButton(
                  onPressed: () => setState(() {
                    _rangeStart = null;
                    _rangeEnd = null;
                  }),
                  child: const Text('All'),
                ),
                FilledButton(
                  onPressed: _writing ? null : _write,
                  style: _accentButtonStyle(),
                  child: _writing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Write report'),
                ),
              ],
            ),
            if (_report.text.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _report,
                readOnly: true,
                minLines: 8,
                maxLines: 18,
                style: asanaTextStyle(
                  Theme.of(context).textTheme.bodyMedium,
                  color: kAsanaTextPrimary,
                  height: 1.4,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: _writing
                          ? null
                          : () => _downloadReport(asPdf: false),
                      style: _accentButtonStyle(),
                      child: const Text('Download as Word'),
                    ),
                    FilledButton(
                      onPressed: _writing
                          ? null
                          : () => _downloadReport(asPdf: true),
                      style: _accentButtonStyle(),
                      child: const Text('Download as PDF'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreTrendSection extends StatefulWidget {
  const _ScoreTrendSection({
    required this.items,
    required this.palette,
    required this.onRangeChanged,
  });

  final List<_ScoredCompletion> items;
  final AsanaLandingPalette palette;
  final void Function(DateTime? start, DateTime? end) onRangeChanged;

  @override
  State<_ScoreTrendSection> createState() => _ScoreTrendSectionState();
}

class _ScoreTrendSectionState extends State<_ScoreTrendSection> {
  _CreatedChartGrain _grain = _CreatedChartGrain.month;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  DateTime get _today => HkTime.todayDateOnlyHk();

  DateTime get _dataStart {
    DateTime? min;
    for (final item in widget.items) {
      final d = _hkDateOnly(item.date);
      if (d == null) continue;
      if (min == null || d.isBefore(min)) min = d;
    }
    return min ?? DateTime(_today.year, _today.month, 1);
  }

  DateTime get _dataEnd {
    var maxDate = _today;
    for (final item in widget.items) {
      final d = _hkDateOnly(item.date);
      if (d != null && d.isAfter(maxDate)) maxDate = d;
    }
    return maxDate;
  }

  DateTime get _boundStart => _alignCreatedGrainStart(_dataStart, _grain);
  DateTime get _boundEnd => _alignCreatedGrainStart(_dataEnd, _grain);

  DateTime get _effectiveStart {
    final raw = _rangeStart ?? _boundStart;
    final aligned = _alignCreatedGrainStart(raw, _grain);
    if (aligned.isBefore(_boundStart)) return _boundStart;
    if (aligned.isAfter(_boundEnd)) return _boundEnd;
    return aligned;
  }

  DateTime get _effectiveEnd {
    final raw = _rangeEnd ?? _boundEnd;
    final aligned = _alignCreatedGrainStart(raw, _grain);
    if (aligned.isAfter(_boundEnd)) return _boundEnd;
    if (aligned.isBefore(_effectiveStart)) return _effectiveStart;
    return aligned;
  }

  void _publishRange({required bool all}) {
    if (all) {
      widget.onRangeChanged(null, null);
      return;
    }
    widget.onRangeChanged(_effectiveStart, _effectiveEnd);
  }

  Future<void> _pickRange(BuildContext anchorContext) async {
    final steps = _createdGrainSteps(_boundStart, _boundEnd, _grain);
    if (steps.isEmpty) return;
    if (_grain == _CreatedChartGrain.month) {
      final picked = await showAsanaAnchoredMonthRangePicker(
        anchorContext: anchorContext,
        startMonth: _effectiveStart,
        endMonth: _effectiveEnd,
        helpText: 'From and to',
        firstDate: _boundStart,
        lastDate: _boundEnd,
        allowClear: false,
        requireBothEnds: true,
        emptyHint: 'Select the from month, then the to month.',
        pendingEndHint: 'Select the to month',
        selectedPrefix: '',
      );
      if (picked == null || picked.cleared || picked.range == null || !mounted) {
        return;
      }
      _applyRange(picked.range!.start, picked.range!.end);
      return;
    }
    var lastDate = _grain == _CreatedChartGrain.day ? _boundEnd : _today;
    if (lastDate.isBefore(_boundStart)) lastDate = _boundStart;
    final picked = await showAsanaAnchoredDateRangePicker(
      anchorContext: anchorContext,
      start: _effectiveStart,
      end: _effectiveEnd,
      helpText: 'From and to',
      firstDate: _boundStart,
      lastDate: lastDate,
      requireBothEnds: true,
    );
    if (picked == null || !mounted) return;
    _applyRange(picked.start, picked.end);
  }

  void _applyRange(DateTime startRaw, DateTime endRaw) {
    setState(() {
      var start = _alignCreatedGrainStart(startRaw, _grain);
      var end = _alignCreatedGrainStart(endRaw, _grain);
      if (start.isBefore(_boundStart)) start = _boundStart;
      if (end.isAfter(_boundEnd)) end = _boundEnd;
      if (start.isAfter(_boundEnd)) start = _boundEnd;
      if (end.isBefore(_boundStart)) end = _boundStart;
      if (start.isAfter(end)) {
        final tmp = start;
        start = end;
        end = tmp;
      }
      _rangeStart = start;
      _rangeEnd = end;
    });
    _publishRange(all: false);
  }

  @override
  Widget build(BuildContext context) {
    final points = _scoreTrendPoints(
      items: widget.items,
      grain: _grain,
      rangeStart: _effectiveStart,
      rangeEnd: _effectiveEnd,
    );
    final titleStyle = asanaTextStyle(
      Theme.of(context).textTheme.titleLarge,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
      height: 1.2,
    );
    return Material(
      color: widget.palette.listSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final wrap = constraints.maxWidth < 720;
                final title = Text('Score trend', style: titleStyle);
                final toggle = _CreatedGrainToggle(
                  grain: _grain,
                  onChanged: (value) {
                    setState(() {
                      _grain = value;
                      _rangeStart = null;
                      _rangeEnd = null;
                    });
                    _publishRange(all: true);
                  },
                  palette: widget.palette,
                );
                if (wrap) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 12), toggle],
                  );
                }
                return Row(children: [Expanded(child: title), toggle]);
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'From',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodySmall,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextSecondary,
                  ),
                ),
                _CreatedRangeButton(
                  label: _createdGrainLabel(_effectiveStart, _grain),
                  onPressed: _pickRange,
                ),
                Text(
                  'To',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodySmall,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextSecondary,
                  ),
                ),
                _CreatedRangeButton(
                  label: _createdGrainLabel(_effectiveEnd, _grain),
                  onPressed: _pickRange,
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _rangeStart = null;
                      _rangeEnd = null;
                    });
                    _publishRange(all: true);
                  },
                  child: const Text('All'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ChartLegendDot(color: widget.palette.accent, label: 'Score'),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            _ScrollablePerformanceChart(
              points: points,
              colors: [widget.palette.accent],
            ),
          ],
        ),
      ),
    );
  }
}

List<_CreatedVolumePoint> _scoreTrendPoints({
  required List<_ScoredCompletion> items,
  required _CreatedChartGrain grain,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  final start = _alignCreatedGrainStart(rangeStart, grain);
  final last = _alignCreatedGrainStart(rangeEnd, grain);
  final totals = <String, int>{};
  final labels = <String, String>{};
  final keys = <String>[];
  for (final cursor in _createdGrainSteps(start, last, grain)) {
    final key = _createdGrainKey(cursor, grain);
    keys.add(key);
    totals[key] = 0;
    labels[key] = switch (grain) {
      _CreatedChartGrain.month => DateFormat('MMM yyyy').format(cursor),
      _CreatedChartGrain.week ||
      _CreatedChartGrain.day => DateFormat('MMM d').format(cursor),
    };
  }
  for (final item in items) {
    final day = _hkDateOnly(item.date);
    if (day == null) continue;
    final key = _createdGrainKey(day, grain);
    if (!totals.containsKey(key)) continue;
    totals[key] = (totals[key] ?? 0) + item.weight;
  }
  return [
    for (final key in keys)
      _CreatedVolumePoint(label: labels[key] ?? key, values: [totals[key] ?? 0]),
  ];
}

class _CreatedVolumeSection extends StatefulWidget {
  const _CreatedVolumeSection({
    required this.series,
    required this.palette,
  });

  final List<_OfficeCreatedSeries> series;
  final AsanaLandingPalette palette;

  @override
  State<_CreatedVolumeSection> createState() => _CreatedVolumeSectionState();
}

class _CreatedVolumeSectionState extends State<_CreatedVolumeSection> {
  _CreatedChartGrain _grain = _CreatedChartGrain.month;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  DateTime get _today => HkTime.todayDateOnlyHk();

  DateTime get _dataStart {
    DateTime? min;
    for (final series in widget.series) {
      for (final raw in series.dates) {
        final d = _hkDateOnly(raw);
        if (d == null) continue;
        if (min == null || d.isBefore(min)) min = d;
      }
    }
    return min ?? DateTime(_today.year, _today.month, 1);
  }

  DateTime get _boundStart => _alignCreatedGrainStart(_dataStart, _grain);
  DateTime get _boundEnd => _alignCreatedGrainStart(_today, _grain);

  DateTime get _effectiveStart {
    final raw = _rangeStart ?? _boundStart;
    final aligned = _alignCreatedGrainStart(raw, _grain);
    if (aligned.isBefore(_boundStart)) return _boundStart;
    if (aligned.isAfter(_boundEnd)) return _boundEnd;
    return aligned;
  }

  DateTime get _effectiveEnd {
    final raw = _rangeEnd ?? _boundEnd;
    final aligned = _alignCreatedGrainStart(raw, _grain);
    if (aligned.isAfter(_boundEnd)) return _boundEnd;
    if (aligned.isBefore(_effectiveStart)) return _effectiveStart;
    return aligned;
  }

  Future<void> _pickRange(BuildContext anchorContext) async {
    final steps = _createdGrainSteps(_boundStart, _boundEnd, _grain);
    if (steps.isEmpty) return;
    if (_grain == _CreatedChartGrain.month) {
      final picked = await showAsanaAnchoredMonthRangePicker(
        anchorContext: anchorContext,
        startMonth: _effectiveStart,
        endMonth: _effectiveEnd,
        helpText: 'From and to',
        firstDate: _boundStart,
        lastDate: _boundEnd,
        allowClear: false,
        requireBothEnds: true,
        emptyHint: 'Select the from month, then the to month.',
        pendingEndHint: 'Select the to month',
        selectedPrefix: '',
      );
      if (picked == null || picked.cleared || picked.range == null || !mounted) {
        return;
      }
      _applyRange(picked.range!.start, picked.range!.end);
      return;
    }
    var lastDate = _grain == _CreatedChartGrain.day ? _boundEnd : _today;
    if (lastDate.isBefore(_boundStart)) lastDate = _boundStart;
    final picked = await showAsanaAnchoredDateRangePicker(
      anchorContext: anchorContext,
      start: _effectiveStart,
      end: _effectiveEnd,
      helpText: 'From and to',
      firstDate: _boundStart,
      lastDate: lastDate,
      requireBothEnds: true,
    );
    if (picked == null || !mounted) return;
    _applyRange(picked.start, picked.end);
  }

  void _applyRange(DateTime startRaw, DateTime endRaw) {
    setState(() {
      var start = _alignCreatedGrainStart(startRaw, _grain);
      var end = _alignCreatedGrainStart(endRaw, _grain);
      if (start.isBefore(_boundStart)) start = _boundStart;
      if (end.isAfter(_boundEnd)) end = _boundEnd;
      if (start.isAfter(_boundEnd)) start = _boundEnd;
      if (end.isBefore(_boundStart)) end = _boundStart;
      if (start.isAfter(end)) {
        final tmp = start;
        start = end;
        end = tmp;
      }
      _rangeStart = start;
      _rangeEnd = end;
    });
  }

  @override
  Widget build(BuildContext context) {
    final points = _createdVolumePoints(
      seriesDates: [for (final series in widget.series) series.dates],
      grain: _grain,
      rangeStart: _effectiveStart,
      rangeEnd: _effectiveEnd,
    );
    return Material(
      color: widget.palette.listSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final wrap = constraints.maxWidth < 720;
                final title = Text(
                  'Tasks & Sub-tasks Creation',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.titleLarge,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: kAsanaTextPrimary,
                  ),
                );
                final toggle = _CreatedGrainToggle(
                  grain: _grain,
                  onChanged: (value) => setState(() => _grain = value),
                  palette: widget.palette,
                );
                if (wrap) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 12), toggle],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    toggle,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'From',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodySmall,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextSecondary,
                  ),
                ),
                _CreatedRangeButton(
                  label: _createdGrainLabel(_effectiveStart, _grain),
                  onPressed: _pickRange,
                ),
                Text(
                  'To',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodySmall,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextSecondary,
                  ),
                ),
                _CreatedRangeButton(
                  label: _createdGrainLabel(_effectiveEnd, _grain),
                  onPressed: _pickRange,
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _rangeStart = null;
                    _rangeEnd = null;
                  }),
                  child: const Text('All'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final series in widget.series)
                  _ChartLegendDot(color: series.color, label: series.label),
              ],
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            _ScrollablePerformanceChart(
              points: points,
              colors: [for (final series in widget.series) series.color],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatedRangeButton extends StatelessWidget {
  const _CreatedRangeButton({required this.label, required this.onPressed});

  final String label;
  final void Function(BuildContext anchorContext) onPressed;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchorContext) {
        return OutlinedButton(
          onPressed: () => onPressed(anchorContext),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          child: Text(label),
        );
      },
    );
  }
}

class _CreatedGrainToggle extends StatelessWidget {
  const _CreatedGrainToggle({
    required this.grain,
    required this.onChanged,
    required this.palette,
    this.showWeek = true,
  });

  final _CreatedChartGrain grain;
  final ValueChanged<_CreatedChartGrain> onChanged;
  final AsanaLandingPalette palette;
  final bool showWeek;

  @override
  Widget build(BuildContext context) {
    Widget button(_CreatedChartGrain value, String label) {
      final selected = grain == value;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: selected ? palette.accent : palette.panelBackground,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onChanged(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                label,
                style: asanaTextStyle(
                  Theme.of(context).textTheme.labelLarge,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? palette.onBanner : kAsanaTextPrimary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(_CreatedChartGrain.month, 'Month'),
        if (showWeek) button(_CreatedChartGrain.week, 'Week'),
        button(_CreatedChartGrain.day, 'Day'),
      ],
    );
  }
}

class _ChartLegendDot extends StatelessWidget {
  const _ChartLegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: asanaTextStyle(
            Theme.of(context).textTheme.bodySmall,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kAsanaTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _ScrollablePerformanceChart extends StatelessWidget {
  const _ScrollablePerformanceChart({
    required this.points,
    required this.colors,
  });

  final List<_CreatedVolumePoint> points;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final width = mobile
            ? math.max(viewport, _mobileChartWidth(points.length))
            : viewport;
        final chart = SizedBox(
          width: width,
          height: 260,
          child: _OfficeLineChart(points: points, colors: colors),
        );
        if (!mobile || width <= viewport) return chart;
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.trackpad,
            },
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: chart,
          ),
        );
      },
    );
  }
}

double _mobileChartWidth(int pointCount) {
  if (pointCount <= 1) return 0;
  const slot = 72.0;
  const axisLeft = 36.0;
  const axisRight = 8.0;
  return axisLeft + axisRight + slot * (pointCount - 1);
}

class _OfficeLineChart extends StatelessWidget {
  const _OfficeLineChart({required this.points, required this.colors});

  final List<_CreatedVolumePoint> points;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OfficeLineChartPainter(
        points: points,
        colors: colors,
        labelStyle: asanaTextStyle(
          Theme.of(context).textTheme.bodySmall,
          fontSize: 10,
          color: kAsanaTextSecondary,
        )!,
      ),
    );
  }
}

class _OfficeLineChartPainter extends CustomPainter {
  _OfficeLineChartPainter({
    required this.points,
    required this.colors,
    required this.labelStyle,
  });

  final List<_CreatedVolumePoint> points;
  final List<Color> colors;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 36.0;
    const right = 8.0;
    const top = 12.0;
    const bottom = 32.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final maxY = math.max(
      1,
      points.fold<int>(0, (m, p) {
        final peak = p.values.fold<int>(0, math.max);
        return math.max(m, peak);
      }),
    );
    final axis = Paint()
      ..color = const Color(0xFFD5D8DC)
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, axis);

    final grid = Paint()
      ..color = const Color(0xFFECEFF1)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plot.bottom - plot.height * (i / 4);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final value = (maxY * i / 4).round();
      final tp = TextPainter(
        text: TextSpan(text: '$value', style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plot.left - tp.width - 6, y - tp.height / 2));
    }

    Offset pointFor(int index, int value) {
      final x = points.length == 1
          ? plot.left + plot.width / 2
          : plot.left + plot.width * (index / (points.length - 1));
      final y = plot.bottom - plot.height * (value / maxY);
      return Offset(x, y);
    }

    void drawSeries(Color color, int Function(_CreatedVolumePoint) pick) {
      final line = Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final p = pointFor(i, pick(points[i]));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, line);
      final dot = Paint()..color = color;
      if (points.length <= 16) {
        for (var i = 0; i < points.length; i++) {
          canvas.drawCircle(pointFor(i, pick(points[i])), 3.2, dot);
        }
      }
    }

    for (var series = 0; series < colors.length; series++) {
      drawSeries(colors[series], (p) {
        if (series >= p.values.length) return 0;
        return p.values[series];
      });
    }

    final slot = points.length <= 1
        ? plot.width
        : plot.width / (points.length - 1);
    final labelEvery = math.max(1, (64 / slot).ceil());
    for (var i = 0; i < points.length; i++) {
      if (i != 0 && i != points.length - 1 && i % labelEvery != 0) continue;
      final tp = TextPainter(
        text: TextSpan(text: points[i].label, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: 72);
      final x = pointFor(i, 0).dx - tp.width / 2;
      tp.paint(
        canvas,
        Offset(x.clamp(plot.left, plot.right - tp.width), plot.bottom + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OfficeLineChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.colors != colors;
  }
}

class _PerformanceMetrics {
  const _PerformanceMetrics({
    required this.activeProjects,
    required this.activeSubprojects,
    required this.activeTasks,
    required this.activeSubtasks,
    required this.completedWorkItems,
    required this.ongoingWorkItems,
    required this.toBeCommencedWorkItems,
    required this.activeStaff,
  });

  final int activeProjects;
  final int activeSubprojects;
  final int activeTasks;
  final int activeSubtasks;
  final int completedWorkItems;
  final int ongoingWorkItems;
  final int toBeCommencedWorkItems;
  final int activeStaff;
}

class _OfficePerformanceSection extends StatelessWidget {
  const _OfficePerformanceSection({
    required this.offices,
    required this.palette,
  });

  final List<({String title, _PerformanceMetrics metrics})> offices;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.listSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final blocks = [
                  for (final office in offices)
                    _PerformanceBlock(
                      title: office.title,
                      metrics: office.metrics,
                      palette: palette,
                    ),
                ];
                final perRow = constraints.maxWidth < 920
                    ? 1
                    : math.min(2, math.max(1, blocks.length));
                if (blocks.isEmpty) {
                  return Text(
                    'No offices in this grant.',
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.bodyMedium,
                      color: kAsanaTextSecondary,
                    ),
                  );
                }
                if (perRow == 1) {
                  return Column(
                    children: [
                      for (var i = 0; i < blocks.length; i++) ...[
                        if (i > 0) const SizedBox(height: 18),
                        blocks[i],
                      ],
                    ],
                  );
                }
                final rows = <Widget>[];
                for (var i = 0; i < blocks.length; i += perRow) {
                  if (rows.isNotEmpty) rows.add(const SizedBox(height: 18));
                  rows.add(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var col = 0; col < perRow; col++) ...[
                          if (col > 0) const SizedBox(width: 18),
                          Expanded(
                            child: i + col < blocks.length
                                ? blocks[i + col]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  );
                }
                return Column(children: rows);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceBlock extends StatelessWidget {
  const _PerformanceBlock({
    required this.title,
    required this.metrics,
    required this.palette,
  });

  final String title;
  final _PerformanceMetrics metrics;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.listSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: asanaTextStyle(
                Theme.of(context).textTheme.titleLarge,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: kAsanaTextPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 18),
            _PerformanceCardsLayout(metrics: metrics, palette: palette),
          ],
        ),
      ),
    );
  }
}

class _PerformanceCardsLayout extends StatelessWidget {
  const _PerformanceCardsLayout({
    required this.palette,
    this.metrics,
    this.cards,
  });

  final _PerformanceMetrics? metrics;
  final List<(String, int)>? cards;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;
    final source = metrics;
    final cards = this.cards ??
        <(String, int)>[
          ('Active projects', source!.activeProjects),
          ('Active sub-projects', source.activeSubprojects),
          ('Active tasks', source.activeTasks),
          ('Active sub-tasks', source.activeSubtasks),
          ('Completed Tasks/Sub-tasks', source.completedWorkItems),
          ('Ongoing Tasks/Sub-tasks', source.ongoingWorkItems),
          ('Tasks/Sub-tasks To be commenced', source.toBeCommencedWorkItems),
          ('Staff', source.activeStaff),
        ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = MediaQuery.sizeOf(context).width < 600 ? 2 : 4;
        final cardHeight = (columns == 2 ? 148.0 : 156.0) * 0.55;
        final rows = <Widget>[];
        for (var i = 0; i < cards.length; i += columns) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: gap),
                  Expanded(
                    child: i + col < cards.length
                        ? _PerformanceScoreCard(
                            label: cards[i + col].$1,
                            value: cards[i + col].$2,
                            palette: palette,
                            wide: true,
                            height: cardHeight,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

class _PerformanceScoreCard extends StatelessWidget {
  const _PerformanceScoreCard({
    required this.label,
    required this.value,
    required this.palette,
    this.wide = false,
    this.height,
  });

  final String label;
  final int value;
  final AsanaLandingPalette palette;
  final bool wide;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? double.infinity : 190,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 140;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                palette.accent.withValues(alpha: 0.08),
                palette.listSurface,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.accent.withValues(alpha: 0.16)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 10 : 14,
                8,
                narrow ? 8 : 12,
                4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.headlineMedium,
                      fontSize: narrow ? 26 : 30,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.bodyMedium,
                      fontSize: narrow ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: const Color(0xFF3B4552),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
