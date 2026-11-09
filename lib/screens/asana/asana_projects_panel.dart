import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../commencement_status.dart';
import '../../config/dev_auth_context.dart';
import '../../models/project_record.dart';
import '../../models/singular_subtask.dart';
import '../../models/subproject_record.dart';
import '../../models/task.dart';
import '../../services/backend_api.dart';
import '../../services/database_service.dart';
import '../../services/asana_filter_cookie_storage.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';
import 'asana_project_filter.dart';
import 'asana_task_filter.dart';
import 'asana_name_freshness.dart';
import 'asana_project_milestone_section.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

const double _kProjectSelectionWidth = 36;

enum _StructurePick {
  none,
  makeSubprojectParent,
  makeSubtaskParent,
  moveTaskParent,
  moveSubprojectParent,
  moveSubtaskParent,
}

class _InactiveSelection extends InheritedWidget {
  const _InactiveSelection({required this.ids, required super.child});

  final Set<String> ids;

  static bool contains(BuildContext context, String id) {
    if (id.isEmpty) return false;
    final scope = context.dependOnInheritedWidgetOfExactType<_InactiveSelection>();
    return scope?.ids.contains(id) ?? false;
  }

  static VoidCallback? toggle({
    required BuildContext context,
    required String itemId,
    required bool selected,
    required ValueChanged<bool>? onSelected,
  }) {
    if (onSelected == null) return null;
    return () {
      if (contains(context, itemId)) return;
      onSelected(!selected);
    };
  }

  @override
  bool updateShouldNotify(_InactiveSelection oldWidget) {
    if (oldWidget.ids.length != ids.length) return true;
    for (final id in ids) {
      if (!oldWidget.ids.contains(id)) return true;
    }
    return false;
  }
}

/// Projects nav content: filter toolbar + project table (mirrors [AsanaTasksPanel]).
class AsanaProjectsPanel extends StatefulWidget {
  const AsanaProjectsPanel({
    super.key,
    required this.palette,
    required this.searchQuery,
    this.refreshToken = 0,
    this.onOpenProject,
    this.onOpenTask,
    this.onOpenSubtask,
    this.onOpenSubproject,
    this.onCreateProject,
    this.onStructureChanged,
  });

  final AsanaLandingPalette palette;
  final String searchQuery;
  final int refreshToken;
  final void Function(String projectId)? onOpenProject;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;
  final void Function(String subprojectId, String projectId)? onOpenSubproject;
  final VoidCallback? onCreateProject;
  final VoidCallback? onStructureChanged;

  @override
  State<AsanaProjectsPanel> createState() => _AsanaProjectsPanelState();
}

class _AsanaProjectsPanelState extends State<AsanaProjectsPanel> {
  final _filters = AsanaProjectFilterState();
  List<ProjectRecord> _displayProjects = [];
  final Set<String> _expandedProjectIds = {};
  final Set<String> _expandedSubprojectIds = {};
  final Set<String> _expandedTaskIds = {};
  final Set<String> _loadingSubtaskTaskIds = {};
  final Map<String, List<SingularSubtask>> _subtasksByTask = {};
  final Map<String, int> _milestoneProgressByProject = {};
  final Set<String> _selectedProjectIds = {};
  final Set<String> _selectedSubprojectIds = {};
  final Set<String> _selectedTaskIds = {};
  final Set<String> _selectedSubtaskIds = {};
  _StructurePick _pick = _StructurePick.none;
  Set<String> _moveSourceProjectIds = {};
  Set<String> _moveSourceSubprojectIds = {};
  Set<String> _moveSourceTaskIds = {};
  Set<String> _moveSourceSubtaskIds = {};
  Set<String> _inactiveSelectionIds = {};
  int _progressLoadGen = 0;
  String? _progressIdsKey;

  String get _cookieStorageKey {
    final uid = activeUserStorageKey();
    return uid == null || uid.isEmpty
        ? 'asana_filters_projects'
        : 'asana_filters_projects_$uid';
  }

  @override
  void initState() {
    super.initState();
    final cookieData = AsanaFilterCookieStorage.load(_cookieStorageKey);
    if (cookieData != null) {
      _filters.applyCookieJson(cookieData);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rebuildList();
    });
  }

  @override
  void didUpdateWidget(covariant AsanaProjectsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _rebuildList();
    }
    if (oldWidget.refreshToken != widget.refreshToken) {
      _progressIdsKey = null;
      _rebuildList();
      _refreshExpandedSubtasks();
    }
  }

  void _rebuildList() {
    final state = context.read<AppState>();
    setState(() {
      _displayProjects = AsanaProjectFilter.apply(
        state,
        _filters,
        searchQuery: widget.searchQuery,
      );
    });
    _scheduleMilestoneProgressIfNeeded();
  }

  void _scheduleMilestoneProgressIfNeeded() {
    final key = [
      for (final project in _displayProjects)
        if (project.hasMilestone) project.id,
    ].join('|');
    if (key == _progressIdsKey) return;
    _progressIdsKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMilestoneProgress();
    });
  }

  int _progressFor(ProjectRecord project) {
    return asanaProjectListProgressPercent(
      hasMilestone: project.hasMilestone,
      status: project.status,
      milestoneAchievedPercent:
          _milestoneProgressByProject[project.id] ?? 0,
    );
  }

  Future<void> _loadMilestoneProgress() async {
    final gen = ++_progressLoadGen;
    final ids = [
      for (final project in _displayProjects)
        if (project.hasMilestone) project.id,
    ];
    if (ids.isEmpty) {
      if (!mounted || gen != _progressLoadGen) return;
      if (_milestoneProgressByProject.isEmpty) return;
      setState(_milestoneProgressByProject.clear);
      return;
    }
    final map = await DatabaseService.fetchAchievedMilestonePercentByProject(
      ids,
    );
    if (!mounted || gen != _progressLoadGen) return;
    setState(() {
      _milestoneProgressByProject
        ..clear()
        ..addAll(map);
    });
  }

  void _onFiltersChanged() {
    AsanaFilterCookieStorage.save(_cookieStorageKey, _filters.toCookieJson());
    AsanaBlockingLoadingOverlay.show(context);
    try {
      _rebuildList();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
    }
  }

  Map<String, List<Task>> _tasksByProject(AppState state) {
    final grouped = <String, List<Task>>{};
    for (final task in state.tasksForTeams({})) {
      if (!task.isSingularTableRow) continue;
      final projectId = task.projectId?.trim();
      if (projectId == null || projectId.isEmpty) continue;
      final status = task.dbStatus?.trim().toLowerCase() ?? '';
      if (status == 'delete' || status == 'deleted') continue;
      grouped.putIfAbsent(projectId, () => []).add(task);
    }
    for (final list in grouped.values) {
      _sortProjectChildTasks(state, list);
    }
    return grouped;
  }

  void _sortProjectChildTasks(AppState state, List<Task> list) {
    list.sort((a, b) {
      final status = _projectChildTaskStatusRank(
        state,
        a,
      ).compareTo(_projectChildTaskStatusRank(state, b));
      if (status != 0) return status;
      final due = _compareNullableDueDates(a.endDate, b.endDate);
      if (due != 0) return due;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  int _projectChildTaskStatusRank(AppState state, Task task) {
    final status = AsanaTaskFilter.taskDisplayStatus(
      state,
      task,
    ).trim().toLowerCase();
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

  Future<void> _ensureSubtasksLoadedForTasks(
    List<Task> tasks, {
    bool force = false,
  }) async {
    final ids = tasks
        .map((t) => t.id.trim())
        .where((id) => id.isNotEmpty)
        .where(
          (id) =>
              (force || !_subtasksByTask.containsKey(id)) &&
              !_loadingSubtaskTaskIds.contains(id),
        )
        .toList();
    if (ids.isEmpty) return;
    final state = context.read<AppState>();
    final taskById = {
      for (final task in tasks)
        if (task.id.trim().isNotEmpty) task.id.trim(): task,
    };
    setState(() => _loadingSubtaskTaskIds.addAll(ids));
    try {
      final grouped =
          await DatabaseService.fetchSubtasksGroupedForLandingPrefetch(ids);
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          final list = List<SingularSubtask>.from(
            grouped[id] ?? const <SingularSubtask>[],
          );
          final parentTask = taskById[id];
          if (parentTask != null) {
            _sortProjectChildSubtasks(state, parentTask, list);
          }
          _subtasksByTask[id] = list;
          _loadingSubtaskTaskIds.remove(id);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          _subtasksByTask[id] = const <SingularSubtask>[];
          _loadingSubtaskTaskIds.remove(id);
        }
      });
    }
  }

  void _refreshExpandedSubtasks() {
    if (_expandedTaskIds.isEmpty) return;
    final state = context.read<AppState>();
    final tasks = [
      for (final task in state.tasksForTeams({}))
        if (_expandedTaskIds.contains(task.id.trim())) task,
    ];
    if (tasks.isEmpty) return;
    unawaited(_ensureSubtasksLoadedForTasks(tasks, force: true));
  }

  void _sortProjectChildSubtasks(
    AppState state,
    Task parentTask,
    List<SingularSubtask> list,
  ) {
    list.sort((a, b) {
      final status = _projectChildSubtaskStatusRank(
        state,
        parentTask,
        a,
      ).compareTo(_projectChildSubtaskStatusRank(state, parentTask, b));
      if (status != 0) return status;
      final due = _compareNullableDueDates(a.dueDate, b.dueDate);
      if (due != 0) return due;
      return a.subtaskName.toLowerCase().compareTo(b.subtaskName.toLowerCase());
    });
  }

  int _projectChildSubtaskStatusRank(
    AppState state,
    Task parentTask,
    SingularSubtask subtask,
  ) {
    if (subtask.isDeleted) return 3;
    final status = AsanaTaskFilter.subtaskDisplayStatus(
      state,
      parentTask,
      subtask,
    ).trim().toLowerCase();
    if (status == 'completed' || status == 'complete') return 1;
    if (status == 'paused') return 2;
    return 0;
  }

  void _toggleProjectExpanded(String projectId, List<Task> tasks) {
    final willExpand = !_expandedProjectIds.contains(projectId);
    setState(() {
      if (!willExpand) {
        _expandedProjectIds.remove(projectId);
      } else {
        _expandedProjectIds.add(projectId);
      }
    });
    if (willExpand) {
      _ensureSubtasksLoadedForTasks(tasks);
    }
  }

  void _toggleSubprojectExpanded(String subprojectId) {
    final id = subprojectId.trim();
    if (id.isEmpty) return;
    setState(() {
      if (!_expandedSubprojectIds.add(id)) {
        _expandedSubprojectIds.remove(id);
      }
    });
  }

  void _toggleTaskExpanded(Task task) {
    final taskId = task.id.trim();
    if (taskId.isEmpty) return;
    final willExpand = !_expandedTaskIds.contains(taskId);
    setState(() {
      if (!willExpand) {
        _expandedTaskIds.remove(taskId);
      } else {
        _expandedTaskIds.add(taskId);
      }
    });
    if (willExpand) {
      _ensureSubtasksLoadedForTasks([task], force: true);
    }
  }

  void _clearStructureSelection() {
    setState(() {
      _selectedProjectIds.clear();
      _selectedSubprojectIds.clear();
      _selectedTaskIds.clear();
      _selectedSubtaskIds.clear();
      _pick = _StructurePick.none;
      _moveSourceProjectIds = {};
      _moveSourceSubprojectIds = {};
      _moveSourceTaskIds = {};
      _moveSourceSubtaskIds = {};
      _inactiveSelectionIds = {};
    });
  }

  void _dropMoveSource(Set<String> sources, String id) {
    setState(() {
      sources.remove(id);
      _selectedProjectIds.remove(id);
      _selectedSubprojectIds.remove(id);
      _selectedTaskIds.remove(id);
      _selectedSubtaskIds.remove(id);
      if (sources.isEmpty) {
        _pick = _StructurePick.none;
        _selectedProjectIds.clear();
        _selectedSubprojectIds.clear();
        _selectedTaskIds.clear();
        _selectedSubtaskIds.clear();
      }
    });
  }

  void _setProjectSelected(String projectId, bool selected) {
    switch (_pick) {
      case _StructurePick.makeSubprojectParent:
        if (!selected) {
          _dropMoveSource(_moveSourceProjectIds, projectId);
          return;
        }
        if (_moveSourceProjectIds.contains(projectId)) return;
        unawaited(_confirmMakeSubprojectUnder(projectId));
        return;
      case _StructurePick.moveSubprojectParent:
        if (!selected) return;
        unawaited(_finishMoveSubprojects(projectId));
        return;
      case _StructurePick.moveTaskParent:
        if (!selected) return;
        unawaited(_finishMoveTasks(projectId: projectId));
        return;
      case _StructurePick.makeSubtaskParent:
      case _StructurePick.moveSubtaskParent:
        return;
      case _StructurePick.none:
        break;
    }
    setState(() {
      if (selected) {
        _selectedProjectIds.add(projectId);
      } else {
        _selectedProjectIds.remove(projectId);
      }
    });
  }

  void _setSubprojectSelected(String subprojectId, bool selected) {
    switch (_pick) {
      case _StructurePick.moveSubprojectParent:
        if (!selected && _moveSourceSubprojectIds.contains(subprojectId)) {
          _dropMoveSource(_moveSourceSubprojectIds, subprojectId);
        }
        return;
      case _StructurePick.moveTaskParent:
        if (!selected) return;
        unawaited(_finishMoveTasks(subprojectId: subprojectId));
        return;
      case _StructurePick.makeSubprojectParent:
      case _StructurePick.makeSubtaskParent:
      case _StructurePick.moveSubtaskParent:
        return;
      case _StructurePick.none:
        break;
    }
    setState(() {
      if (selected) {
        _selectedSubprojectIds.add(subprojectId);
      } else {
        _selectedSubprojectIds.remove(subprojectId);
      }
    });
  }

  void _setTaskSelected(String taskId, bool selected) {
    switch (_pick) {
      case _StructurePick.makeSubtaskParent:
        if (!selected) {
          if (_moveSourceTaskIds.contains(taskId)) {
            _dropMoveSource(_moveSourceTaskIds, taskId);
          }
          return;
        }
        if (_moveSourceTaskIds.contains(taskId)) return;
        unawaited(_confirmMakeSubtaskUnder(taskId));
        return;
      case _StructurePick.moveSubtaskParent:
        if (!selected) return;
        unawaited(_finishMoveSubtasks(taskId));
        return;
      case _StructurePick.moveTaskParent:
        if (!selected && _moveSourceTaskIds.contains(taskId)) {
          _dropMoveSource(_moveSourceTaskIds, taskId);
        }
        return;
      case _StructurePick.makeSubprojectParent:
      case _StructurePick.moveSubprojectParent:
        return;
      case _StructurePick.none:
        break;
    }
    setState(() {
      if (selected) {
        _selectedTaskIds.add(taskId);
      } else {
        _selectedTaskIds.remove(taskId);
      }
    });
  }

  void _setSubtaskSelected(String subtaskId, bool selected) {
    if (_pick == _StructurePick.moveSubtaskParent) {
      if (!selected && _moveSourceSubtaskIds.contains(subtaskId)) {
        _dropMoveSource(_moveSourceSubtaskIds, subtaskId);
      }
      return;
    }
    if (_pick != _StructurePick.none) return;
    setState(() {
      if (selected) {
        _selectedSubtaskIds.add(subtaskId);
      } else {
        _selectedSubtaskIds.remove(subtaskId);
      }
    });
  }

  bool _staffHit(AppState state, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return false;
    final uuid = state.effectiveStaffUuid?.trim() ?? '';
    final appId =
        (state.effectiveStaffAppId ?? state.userStaffAppId)?.trim() ?? '';
    return (uuid.isNotEmpty && value == uuid) ||
        (appId.isNotEmpty && value == appId);
  }

  bool _viewerIsProjectPic(AppState state, ProjectRecord project) {
    if (state.superAdminActsAsPic) return true;
    return project.picStaffUuids.any((id) => _staffHit(state, id));
  }

  bool _viewerIsSubprojectPic(AppState state, SubprojectRecord subproject) {
    if (state.superAdminActsAsPic) return true;
    return subproject.picStaffUuids.any((id) => _staffHit(state, id));
  }

  bool _canMakeSubproject(AppState state, ProjectRecord project) {
    if (_projectIsDeleted(project) || project.hasMilestone) return false;
    if (!_viewerIsProjectPic(state, project)) return false;
    return state.subprojectsForProject(project.id).isEmpty;
  }

  bool _canDetachProject(AppState state, SubprojectRecord subproject) {
    if (subproject.isDeleted) return false;
    return _viewerIsSubprojectPic(state, subproject);
  }

  bool _viewerIsTaskPic(AppState state, Task task) {
    if (state.superAdminActsAsPic) return true;
    return _staffHit(state, task.pic);
  }

  bool _viewerIsSubtaskPic(AppState state, SingularSubtask subtask) {
    if (state.superAdminActsAsPic) return true;
    return _staffHit(state, subtask.pic);
  }

  bool _viewerCreatedTask(AppState state, Task task) {
    return _staffHit(state, task.createByAssigneeKey);
  }

  bool _viewerCreatedSubtask(AppState state, SingularSubtask subtask) {
    return _staffHit(state, subtask.createByStaffId);
  }

  bool _taskHasKnownSubtasks(String taskId) {
    final list = _subtasksByTask[taskId];
    if (list == null) return false;
    return list.any((subtask) => !subtask.isDeleted);
  }

  List<Task>? _selectedTasks(AppState state) {
    if (_selectedTaskIds.isEmpty) return const [];
    final byId = {
      for (final task in state.tasksForTeams({}))
        if (task.isSingularTableRow) task.id: task,
    };
    final out = <Task>[];
    for (final id in _selectedTaskIds) {
      final task = byId[id];
      if (task == null) return null;
      out.add(task);
    }
    return out;
  }

  List<SingularSubtask>? _selectedSubtasks() {
    if (_selectedSubtaskIds.isEmpty) return const [];
    final byId = <String, SingularSubtask>{};
    for (final list in _subtasksByTask.values) {
      for (final subtask in list) {
        byId[subtask.id] = subtask;
      }
    }
    final out = <SingularSubtask>[];
    for (final id in _selectedSubtaskIds) {
      final subtask = byId[id];
      if (subtask == null) return null;
      out.add(subtask);
    }
    return out;
  }

  bool _hasOtherTaskParent(AppState state, Set<String> excluded) {
    for (final task in state.tasksForTeams({})) {
      if (!task.isSingularTableRow || _taskDeleted(task)) continue;
      if (!excluded.contains(task.id)) return true;
    }
    return false;
  }

  bool _taskPlaceDiffers(Task task, String projectId, String subprojectId) {
    return (task.projectId ?? '') != projectId ||
        (task.subprojectId ?? '') != subprojectId;
  }

  bool _hasTaskMoveDestination(AppState state, List<Task> tasks) {
    for (final project in state.projects) {
      if (_projectIsDeleted(project)) continue;
      if (tasks.any((task) => _taskPlaceDiffers(task, project.id, ''))) {
        return true;
      }
      for (final subproject in state.subprojectsForProject(project.id)) {
        if (subproject.isDeleted) continue;
        if (tasks.any(
          (task) => _taskPlaceDiffers(task, subproject.projectId, subproject.id),
        )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _hasSubprojectMoveDestination(
    AppState state,
    List<SubprojectRecord> subprojects,
  ) {
    for (final project in state.projects) {
      if (_projectIsDeleted(project)) continue;
      if (subprojects.any((subproject) => subproject.projectId != project.id)) {
        return true;
      }
    }
    return false;
  }

  bool _hasSubtaskMoveDestination(AppState state, List<SingularSubtask> subtasks) {
    for (final task in state.tasksForTeams({})) {
      if (!task.isSingularTableRow || _taskDeleted(task)) continue;
      if (subtasks.any((subtask) => subtask.taskId != task.id)) return true;
    }
    return false;
  }

  String? _sharedTaskParentId(Iterable<Task> tasks) {
    String? projectId;
    String? subprojectId;
    var seen = false;
    for (final task in tasks) {
      final project = task.projectId?.trim() ?? '';
      final subproject = task.subprojectId?.trim() ?? '';
      if (!seen) {
        projectId = project;
        subprojectId = subproject;
        seen = true;
        continue;
      }
      if (projectId != project || subprojectId != subproject) return null;
    }
    if (!seen) return null;
    if (subprojectId != null && subprojectId.isNotEmpty) return subprojectId;
    if (projectId != null && projectId.isNotEmpty) return projectId;
    return null;
  }

  String? _sharedSubprojectParentId(Iterable<SubprojectRecord> subprojects) {
    String? projectId;
    for (final subproject in subprojects) {
      if (projectId == null) {
        projectId = subproject.projectId;
      } else if (projectId != subproject.projectId) {
        return null;
      }
    }
    return projectId;
  }

  String? _sharedSubtaskParentId(Iterable<SingularSubtask> subtasks) {
    String? taskId;
    for (final subtask in subtasks) {
      if (taskId == null) {
        taskId = subtask.taskId;
      } else if (taskId != subtask.taskId) {
        return null;
      }
    }
    return taskId;
  }

  String? _moveTaskDestinationLabel(
    AppState state, {
    String? projectId,
    String? subprojectId,
  }) {
    final subId = subprojectId?.trim() ?? '';
    if (subId.isNotEmpty) {
      final subproject = state.subprojectById(subId);
      if (subproject == null) return null;
      return _subprojectLabel(subproject);
    }
    final id = projectId?.trim() ?? '';
    if (id.isEmpty) return null;
    for (final project in state.projects) {
      if (project.id == id) return _projectLabel(project);
    }
    return null;
  }

  Widget _structureButton(String label, VoidCallback onPressed) {
    return _ProjectStructureButton(
      label: label,
      palette: widget.palette,
      onPressed: onPressed,
    );
  }

  List<Widget> _selectionButtons(AppState state) {
    if (_pick != _StructurePick.none) {
      return [_structureButton('Cancel', _clearStructureSelection)];
    }
    final projectOn = _selectedProjectIds.isNotEmpty;
    final subprojectOn = _selectedSubprojectIds.isNotEmpty;
    final taskOn = _selectedTaskIds.isNotEmpty;
    final subtaskOn = _selectedSubtaskIds.isNotEmpty;
    final structureOn = projectOn || subprojectOn;
    final workOn = taskOn || subtaskOn;
    if (structureOn && workOn) return const [];
    if (projectOn && subprojectOn) return const [];
    if (projectOn) {
      final selected = <ProjectRecord>[
        for (final project in state.projects)
          if (_selectedProjectIds.contains(project.id)) project,
      ];
      if (selected.length != _selectedProjectIds.length) return const [];
      final allEligible = selected.every(
        (project) => _canMakeSubproject(state, project),
      );
      final hasParent = state.projects.any(
        (project) =>
            !_projectIsDeleted(project) &&
            !_selectedProjectIds.contains(project.id),
      );
      if (!allEligible || !hasParent) return const [];
      return [_structureButton('Make Subproject', _beginMakeSubproject)];
    }
    if (subprojectOn) {
      final selected = <SubprojectRecord>[
        for (final id in _selectedSubprojectIds)
          if (state.subprojectById(id) case final subproject?) subproject,
      ];
      if (selected.length != _selectedSubprojectIds.length) return const [];
      final buttons = <Widget>[];
      if (selected.every((subproject) => _canDetachProject(state, subproject))) {
        buttons.add(_structureButton('Detach Project', _detachSelectedProjects));
      }
      if (selected.every(
            (subproject) => _viewerIsSubprojectPic(state, subproject),
          ) &&
          _hasSubprojectMoveDestination(state, selected)) {
        buttons.add(
          _structureButton('Move Subproject', _beginMoveSubprojects),
        );
      }
      return buttons;
    }
    final tasks = _selectedTasks(state);
    final subtasks = _selectedSubtasks();
    if (tasks == null || subtasks == null) return const [];
    if (taskOn && subtaskOn) {
      final canClone = tasks.every((task) => _viewerCreatedTask(state, task)) &&
          subtasks.every((subtask) => _viewerCreatedSubtask(state, subtask));
      if (!canClone) return const [];
      return [_structureButton('Clone', _cloneSelectedWork)];
    }
    if (taskOn) {
      final buttons = <Widget>[];
      if (tasks.every((task) => _viewerCreatedTask(state, task))) {
        buttons.add(_structureButton('Clone', _cloneSelectedWork));
      }
      if (tasks.every(
            (task) =>
                _viewerIsTaskPic(state, task) &&
                !_taskDeleted(task) &&
                !_taskHasKnownSubtasks(task.id),
          ) &&
          _hasOtherTaskParent(state, _selectedTaskIds)) {
        buttons.add(_structureButton('Make Subtask', _beginMakeSubtask));
      }
      if (tasks.every((task) => _viewerIsTaskPic(state, task)) &&
          _hasTaskMoveDestination(state, tasks)) {
        buttons.add(_structureButton('Move Task', _beginMoveTasks));
      }
      return buttons;
    }
    if (subtaskOn) {
      final buttons = <Widget>[];
      if (subtasks.every(
        (subtask) => _viewerCreatedSubtask(state, subtask) && !subtask.isDeleted,
      )) {
        buttons.add(_structureButton('Clone', _cloneSelectedWork));
      }
      if (subtasks.every(
        (subtask) => _viewerIsSubtaskPic(state, subtask) && !subtask.isDeleted,
      )) {
        buttons.add(_structureButton('Detach Task', _detachSelectedTasks));
        if (_hasSubtaskMoveDestination(state, subtasks)) {
          buttons.add(_structureButton('Move Subtask', _beginMoveSubtasks));
        }
      }
      return buttons;
    }
    return const [];
  }

  Future<void> _showStructureInfoDialog({
    required String title,
    required String content,
    String confirmText = 'OK',
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          backgroundColor: widget.palette.panelBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFEDEAE9), width: 1),
          ),
          elevation: 12,
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: asanaTextStyle(
                    theme.textTheme.titleMedium,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                asanaDialogRichText(
                  content,
                  asanaTextStyle(
                    theme.textTheme.bodyMedium,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: kAsanaTextSecondary,
                    height: 1.4,
                  )!,
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.palette.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: Text(confirmText),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showStructureConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    String cancelText = 'Cancel',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          backgroundColor: widget.palette.panelBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFEDEAE9), width: 1),
          ),
          elevation: 12,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: asanaTextStyle(
                    theme.textTheme.titleMedium,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                asanaDialogRichText(
                  content,
                  asanaTextStyle(
                    theme.textTheme.bodyMedium,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: kAsanaTextSecondary,
                    height: 1.4,
                  )!,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kAsanaTextPrimary,
                        side: const BorderSide(color: Color(0xFFEDEAE9)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: Text(cancelText),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.palette.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: Text(confirmText),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _projectIsDeleted(ProjectRecord project) {
    final status = project.status.trim().toLowerCase();
    return status == 'deleted' || status == 'delete';
  }

  String _projectLabel(ProjectRecord project) {
    final name = project.name.trim();
    return asanaDialogBold(name.isEmpty ? '(Unnamed project)' : name);
  }

  String _subprojectLabel(SubprojectRecord subproject) {
    final name = subproject.name.trim();
    return asanaDialogBold(name.isEmpty ? '(Unnamed sub-project)' : name);
  }

  Future<void> _beginMakeSubproject() async {
    final state = context.read<AppState>();
    final selected = <ProjectRecord>[
      for (final project in state.projects)
        if (_selectedProjectIds.contains(project.id)) project,
    ];
    if (selected.isEmpty) return;
    if (!mounted) return;
    await _showStructureInfoDialog(
      title: 'Make Subproject',
      content:
          'Check one project from the list. That project will become the parent, and each checked project will move under it as a sub-project. Tasks move with those projects.',
    );
    if (!mounted) return;
    setState(() {
      _pick = _StructurePick.makeSubprojectParent;
      _moveSourceProjectIds = {..._selectedProjectIds};
      _inactiveSelectionIds = {..._selectedProjectIds};
      _selectedSubprojectIds.clear();
      _selectedTaskIds.clear();
      _selectedSubtaskIds.clear();
    });
  }

  Future<void> _confirmMakeSubprojectUnder(String parentId) async {
    final state = context.read<AppState>();
    final sources = <ProjectRecord>[
      for (final project in state.projects)
        if (_moveSourceProjectIds.contains(project.id)) project,
    ];
    ProjectRecord? parent;
    for (final project in state.projects) {
      if (project.id == parentId) {
        parent = project;
        break;
      }
    }
    if (sources.isEmpty || parent == null) {
      _clearStructureSelection();
      return;
    }
    setState(() {
      _selectedProjectIds
        ..clear()
        ..addAll(_moveSourceProjectIds)
        ..add(parentId);
    });
    final sourceNames = sources.map(_projectLabel).join(', ');
    final parentName = _projectLabel(parent);
    final confirmed = await _showStructureConfirmDialog(
      title: 'Make Subproject',
      content: sources.length == 1
          ? 'Move $sourceNames under $parentName?'
          : 'Move these projects under $parentName?\n$sourceNames',
      confirmText: 'Yes',
      cancelText: 'No',
    );
    if (!mounted) return;
    if (confirmed != true) {
      _clearStructureSelection();
      return;
    }
    AsanaBlockingLoadingOverlay.show(context);
    final error = await DatabaseService.moveProjectsUnderProject(
      projects: sources,
      parentProjectId: parentId,
      updaterStaffLookupKey: state.effectiveStaffAppId,
    );
    AsanaBlockingLoadingOverlay.hide();
    if (!mounted) return;
    _clearStructureSelection();
    widget.onStructureChanged?.call();
    if (error != null) {
      await _showStructureInfoDialog(title: 'Could not move', content: error);
    }
  }

  Future<void> _detachSelectedProjects() async {
    final state = context.read<AppState>();
    final selected = <SubprojectRecord>[
      for (final id in _selectedSubprojectIds)
        if (state.subprojectById(id) case final subproject?)
          if (_canDetachProject(state, subproject)) subproject,
    ];
    if (selected.isEmpty) return;
    final names = selected.map(_subprojectLabel).join(', ');
    final confirmed = await _showStructureConfirmDialog(
      title: 'Detach Project',
      content: selected.length == 1
          ? '$names will leave its parent and become its own project. Its tasks move with it.'
          : 'These sub-projects will leave their parents and become their own projects. Their tasks move with them:\n$names',
      confirmText: 'Confirm',
      cancelText: 'Cancel',
    );
    if (confirmed != true || !mounted) return;
    AsanaBlockingLoadingOverlay.show(context);
    final error = await DatabaseService.promoteSubprojectsToProjects(
      subprojects: selected,
      updaterStaffLookupKey: state.effectiveStaffAppId,
    );
    AsanaBlockingLoadingOverlay.hide();
    if (!mounted) return;
    _clearStructureSelection();
    widget.onStructureChanged?.call();
    if (error != null) {
      await _showStructureInfoDialog(title: 'Could not detach', content: error);
    }
  }

  String _taskLabel(Task task) {
    final name = task.name.trim();
    return asanaDialogBold(name.isEmpty ? '(Unnamed task)' : name);
  }

  String _subtaskLabel(SingularSubtask subtask) {
    final name = subtask.subtaskName.trim();
    return asanaDialogBold(name.isEmpty ? '(Unnamed sub-task)' : name);
  }

  String? get _structureActorKey {
    final state = context.read<AppState>();
    return state.effectiveStaffAppId ?? state.userStaffAppId;
  }

  Future<void> _cloneSelectedWork() async {
    final state = context.read<AppState>();
    final tasks = _selectedTasks(state) ?? const <Task>[];
    final subtasks = _selectedSubtasks() ?? const <SingularSubtask>[];
    if (tasks.isEmpty && subtasks.isEmpty) return;
    AsanaBlockingLoadingOverlay.show(context);
    String? error;
    if (tasks.isNotEmpty) {
      error = await DatabaseService.cloneTasks(
        tasks: tasks,
        creatorStaffLookupKey: _structureActorKey,
      );
    }
    if (error == null && subtasks.isNotEmpty) {
      error = await DatabaseService.cloneSubtasks(
        subtasks: subtasks,
        creatorStaffLookupKey: _structureActorKey,
      );
    }
    AsanaBlockingLoadingOverlay.hide();
    if (!mounted) return;
    _clearStructureSelection();
    widget.onStructureChanged?.call();
    if (error != null) {
      await _showStructureInfoDialog(title: 'Could not clone', content: error);
    }
  }

  Future<void> _beginMakeSubtask() async {
    final state = context.read<AppState>();
    final selected = _selectedTasks(state);
    if (selected == null || selected.isEmpty) return;
    if (!mounted) return;
    await _showStructureInfoDialog(
      title: 'Make Subtask',
      content:
          'Check one task from the list. That task will become the parent, and each checked task will move under it as a sub-task.',
    );
    if (!mounted) return;
    setState(() {
      _pick = _StructurePick.makeSubtaskParent;
      _moveSourceTaskIds = {..._selectedTaskIds};
      _inactiveSelectionIds = {..._selectedTaskIds};
      _selectedProjectIds.clear();
      _selectedSubprojectIds.clear();
      _selectedSubtaskIds.clear();
    });
  }

  Future<void> _confirmMakeSubtaskUnder(String parentId) async {
    final state = context.read<AppState>();
    final sources = <Task>[
      for (final task in state.tasksForTeams({}))
        if (_moveSourceTaskIds.contains(task.id)) task,
    ];
    Task? parent;
    for (final task in state.tasksForTeams({})) {
      if (task.id == parentId) {
        parent = task;
        break;
      }
    }
    if (sources.isEmpty || parent == null || _taskDeleted(parent)) {
      _clearStructureSelection();
      return;
    }
    setState(() {
      _selectedTaskIds
        ..clear()
        ..addAll(_moveSourceTaskIds)
        ..add(parentId);
    });
    final sourceNames = sources.map(_taskLabel).join(', ');
    final parentName = _taskLabel(parent);
    final confirmed = await _showStructureConfirmDialog(
      title: 'Make Subtask',
      content: sources.length == 1
          ? 'Move $sourceNames under $parentName as a sub-task?'
          : 'Move these tasks under $parentName as sub-tasks?\n$sourceNames',
      confirmText: 'Yes',
      cancelText: 'No',
    );
    if (!mounted) return;
    if (confirmed != true) {
      _clearStructureSelection();
      return;
    }
    AsanaBlockingLoadingOverlay.show(context);
    final error = await DatabaseService.convertTasksToSubtasks(
      tasks: sources,
      parentTaskId: parentId,
      updaterStaffLookupKey: _structureActorKey,
    );
    AsanaBlockingLoadingOverlay.hide();
    if (!mounted) return;
    _clearStructureSelection();
    widget.onStructureChanged?.call();
    if (error != null) {
      await _showStructureInfoDialog(title: 'Could not move', content: error);
    }
  }

  Future<void> _detachSelectedTasks() async {
    final subtasks = _selectedSubtasks() ?? const <SingularSubtask>[];
    if (subtasks.isEmpty) return;
    final names = subtasks.map(_subtaskLabel).join(', ');
    final confirmed = await _showStructureConfirmDialog(
      title: 'Detach Task',
      content: subtasks.length == 1
          ? '$names will leave its parent task and become its own task under the same project.'
          : 'These sub-tasks will leave their parent tasks and become their own tasks under the same project:\n$names',
      confirmText: 'Confirm',
      cancelText: 'Cancel',
    );
    if (confirmed != true || !mounted) return;
    AsanaBlockingLoadingOverlay.show(context);
    final error = await DatabaseService.promoteSubtasksToTasks(
      subtasks: subtasks,
      updaterStaffLookupKey: _structureActorKey,
    );
    AsanaBlockingLoadingOverlay.hide();
    if (!mounted) return;
    _clearStructureSelection();
    widget.onStructureChanged?.call();
    if (error != null) {
      await _showStructureInfoDialog(title: 'Could not detach', content: error);
    }
  }

  Future<void> _beginMoveTasks() async {
    if (!mounted) return;
    await _showStructureInfoDialog(
      title: 'Move Task',
      content:
          'Check one project or sub-project from the list. The checked tasks will move under it. Their sub-tasks move with them.',
    );
    if (!mounted) return;
    final state = context.read<AppState>();
    final moving = <Task>[
      for (final task in state.tasksForTeams({}))
        if (_selectedTaskIds.contains(task.id)) task,
    ];
    final sharedParent = _sharedTaskParentId(moving);
    setState(() {
      _pick = _StructurePick.moveTaskParent;
      _moveSourceTaskIds = {..._selectedTaskIds};
      _inactiveSelectionIds = {
        ..._selectedTaskIds,
        if (sharedParent != null) sharedParent,
      };
      _selectedProjectIds.clear();
      _selectedSubprojectIds.clear();
      _selectedSubtaskIds.clear();
    });
  }

  Future<void> _finishMoveTasks({
    String? projectId,
    String? subprojectId,
  }) async {
    final state = context.read<AppState>();
    final sources = <Task>[
      for (final task in state.tasksForTeams({}))
        if (_moveSourceTaskIds.contains(task.id)) task,
    ];
    if (sources.isEmpty) {
      _clearStructureSelection();
      return;
    }
    final destination = _moveTaskDestinationLabel(
      state,
      projectId: projectId,
      subprojectId: subprojectId,
    );
    if (destination == null) {
      _clearStructureSelection();
      return;
    }
    setState(() {
      if (projectId != null) _selectedProjectIds.add(projectId);
      if (subprojectId != null) _selectedSubprojectIds.add(subprojectId);
    });
    final sourceNames = sources.map(_taskLabel).join(', ');
    final confirmed = await _showStructureConfirmDialog(
      title: 'Move Task',
      content: sources.length == 1
          ? 'Move $sourceNames under $destination?'
          : 'Move these tasks under $destination?\n$sourceNames',
      confirmText: 'Yes',
      cancelText: 'No',
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() {
        if (projectId != null) _selectedProjectIds.remove(projectId);
        if (subprojectId != null) _selectedSubprojectIds.remove(subprojectId);
      });
      return;
    }
    AsanaBlockingLoadingOverlay.show(context);
    final error = await DatabaseService.moveTasksUnder(
      tasks: sources,
      projectId: projectId,
      subprojectId: subprojectId,
      updaterStaffLookupKey: _structureActorKey,
    );
    AsanaBlockingLoadingOverlay.hide();
    if (!mounted) return;
    _clearStructureSelection();
    widget.onStructureChanged?.call();
    if (error != null) {
      await _showStructureInfoDialog(title: 'Could not move', content: error);
    }
  }

  Future<void> _beginMoveSubprojects() async {
    if (!mounted) return;
    await _showStructureInfoDialog(
      title: 'Move Subproject',
      content:
          'Check one project from the list. The checked sub-projects will move under it. Their tasks move with them.',
    );
    if (!mounted) return;
    final state = context.read<AppState>();
    final moving = <SubprojectRecord>[
      for (final id in _selectedSubprojectIds)
        if (state.subprojectById(id) case final subproject?) subproject,
    ];
    final sharedParent = _sharedSubprojectParentId(moving);
    setState(() {
      _pick = _StructurePick.moveSubprojectParent;
      _moveSourceSubprojectIds = {..._selectedSubprojectIds};
      _inactiveSelectionIds = {
        ..._selectedSubprojectIds,
        if (sharedParent != null) sharedParent,
      };
      _selectedProjectIds.clear();
      _selectedTaskIds.clear();
      _selectedSubtaskIds.clear();
    });
  }

  Future<void> _finishMoveSubprojects(String parentId) async {
    final state = context.read<AppState>();
    final sources = <SubprojectRecord>[
      for (final id in _moveSourceSubprojectIds)
        if (state.subprojectById(id) case final subproject?) subproject,
    ];
    if (sources.isEmpty) {
      _clearStructureSelection();
      return;
    }
    ProjectRecord? parent;
    for (final project in state.projects) {
      if (project.id == parentId) {
        parent = project;
        break;
      }
    }
    if (parent == null) {
      _clearStructureSelection();
      return;
    }
    setState(() => _selectedProjectIds.add(parentId));
    final sourceNames = sources.map(_subprojectLabel).join(', ');
    final parentName = _projectLabel(parent);
    final confirmed = await _showStructureConfirmDialog(
      title: 'Move Subproject',
      content: sources.length == 1
          ? 'Move $sourceNames under $parentName?'
          : 'Move these sub-projects under $parentName?\n$sourceNames',
      confirmText: 'Yes',
      cancelText: 'No',
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _selectedProjectIds.remove(parentId));
      return;
    }
    AsanaBlockingLoadingOverlay.show(context);
    final error = await DatabaseService.moveSubprojectsUnderProject(
      subprojects: sources,
      parentProjectId: parentId,
      updaterStaffLookupKey: _structureActorKey,
    );
    AsanaBlockingLoadingOverlay.hide();
    if (!mounted) return;
    if (error == null) {
      final newProjectName = parent.name.trim();
      for (final source in sources) {
        final oldProjectName =
            state.projectById(source.projectId)?.name.trim() ?? '';
        await sendHierarchyEventEmail(
          kind: 'subproject',
          event: 'updated',
          id: source.id,
          changes: [
            {
              'field': 'project',
              'oldValue': oldProjectName,
              'newValue': newProjectName,
            },
          ],
          previousAssigneeIds: source.assigneeStaffUuids,
        );
      }
    }
    _clearStructureSelection();
    widget.onStructureChanged?.call();
    if (error != null) {
      await _showStructureInfoDialog(title: 'Could not move', content: error);
    }
  }

  Future<void> _beginMoveSubtasks() async {
    if (!mounted) return;
    await _showStructureInfoDialog(
      title: 'Move Subtask',
      content:
          'Check one task from the list. The checked sub-tasks will move under it.',
    );
    if (!mounted) return;
    final moving = <SingularSubtask>[
      for (final list in _subtasksByTask.values)
        for (final subtask in list)
          if (_selectedSubtaskIds.contains(subtask.id)) subtask,
    ];
    final sharedParent = _sharedSubtaskParentId(moving);
    setState(() {
      _pick = _StructurePick.moveSubtaskParent;
      _moveSourceSubtaskIds = {..._selectedSubtaskIds};
      _inactiveSelectionIds = {
        ..._selectedSubtaskIds,
        if (sharedParent != null) sharedParent,
      };
      _selectedProjectIds.clear();
      _selectedSubprojectIds.clear();
      _selectedTaskIds.clear();
    });
  }

  Future<void> _finishMoveSubtasks(String parentId) async {
    final sources = <SingularSubtask>[];
    for (final list in _subtasksByTask.values) {
      for (final subtask in list) {
        if (_moveSourceSubtaskIds.contains(subtask.id)) sources.add(subtask);
      }
    }
    if (sources.isEmpty) {
      _clearStructureSelection();
      return;
    }
    final state = context.read<AppState>();
    Task? parent;
    for (final task in state.tasksForTeams({})) {
      if (task.id == parentId) {
        parent = task;
        break;
      }
    }
    if (parent == null) {
      _clearStructureSelection();
      return;
    }
    setState(() => _selectedTaskIds.add(parentId));
    final sourceNames = sources.map(_subtaskLabel).join(', ');
    final parentName = _taskLabel(parent);
    final confirmed = await _showStructureConfirmDialog(
      title: 'Move Subtask',
      content: sources.length == 1
          ? 'Move $sourceNames under $parentName?'
          : 'Move these sub-tasks under $parentName?\n$sourceNames',
      confirmText: 'Yes',
      cancelText: 'No',
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _selectedTaskIds.remove(parentId));
      return;
    }
    AsanaBlockingLoadingOverlay.show(context);
    final error = await DatabaseService.moveSubtasksUnderTask(
      subtasks: sources,
      parentTaskId: parentId,
      updaterStaffLookupKey: _structureActorKey,
    );
    AsanaBlockingLoadingOverlay.hide();
    if (!mounted) return;
    _clearStructureSelection();
    widget.onStructureChanged?.call();
    if (error != null) {
      await _showStructureInfoDialog(title: 'Could not move', content: error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState state;
    try {
      state = context.watch<AppState>();
    } catch (e) {
      return ColoredBox(
        color: widget.palette.panelBackground,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load projects. Open this screen from the main app after sign-in.\n\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    _displayProjects = AsanaProjectFilter.apply(
      state,
      _filters,
      searchQuery: widget.searchQuery,
    );
    _scheduleMilestoneProgressIfNeeded();
    final projects = _displayProjects;
    final tasksByProject = _tasksByProject(state);
    final theme = Theme.of(context);
    final tableColors = widget.palette.tableColors;
    final hierarchyColors = widget.palette.hierarchyRowColors;
    final compactTitle = MediaQuery.sizeOf(context).width < 600;

    return _InactiveSelection(
      ids: _inactiveSelectionIds,
      child: ColoredBox(
      color: widget.palette.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Project List',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: compactTitle ? 14 : 18,
                  fontWeight: FontWeight.w600,
                  color: kAsanaTextPrimary,
                  height: 1.25,
                ),
                maxLines: compactTitle ? 1 : null,
                overflow: compactTitle
                    ? TextOverflow.ellipsis
                    : TextOverflow.visible,
              ),
            ),
          ),
          AsanaPanelFilterToolbar(
            palette: widget.palette,
            createLabel: 'Create Project',
            onCreate: widget.onCreateProject,
            actionButtonHeight: kAsanaShortToolbarActionHeight,
            besideCreate: _selectionButtons(state),
            onClearAll: () {
              setState(_filters.resetToDefaults);
              _onFiltersChanged();
            },
            filterChildren: [
              AsanaFilterDropdown(
                title: 'Scope',
                value: _scopeLabel(),
                buttonWidth: 148,
                onPressed: _showScopeMenu,
              ),
              AsanaFilterDropdown(
                title: 'Status',
                value: _statusLabel(),
                onPressed: _showStatusMenu,
              ),
              AsanaFilterDropdown(
                title: 'Creator Team',
                value: _teamFilterLabel(state, _filters.creatorTeamIds),
                onPressed: _showCreatorTeamMenu,
              ),
              AsanaFilterDropdown(
                title: 'Creator Name',
                value: _creatorLabel(state),
                onPressed: _showCreatorMenu,
              ),
              AsanaFilterDropdown(
                title: 'PIC Team',
                value: _teamFilterLabel(state, _filters.picTeamIds),
                onPressed: _showPicTeamMenu,
              ),
              AsanaFilterDropdown(
                title: 'PIC',
                value: _picLabel(state),
                onPressed: _showPicMenu,
              ),
              AsanaFilterDropdown(
                title: 'Due Date',
                value: _dueDateLabel(),
                buttonWidth: asanaDueDateFilterButtonWidth(
                  _filters.createDateStart,
                  _filters.createDateEnd,
                ),
                onPressed: _showDueDateRangePicker,
              ),
              AsanaFilterDropdown(
                title: 'Sort',
                value: _sortLabel(),
                buttonWidth: 136,
                onPressed: _showSortMenu,
              ),
            ],
          ),
          Expanded(
            child: AsanaPanelListSurface(
              palette: widget.palette,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mobileList = constraints.maxWidth < 600;
                  final tableWidth =
                      constraints.maxWidth < _ProjectTableLayout.minTableWidth
                      ? _ProjectTableLayout.minTableWidth
                      : constraints.maxWidth;

                  if (projects.isEmpty) {
                    return Center(
                      child: Text(
                        'No projects match your filters.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  if (mobileList) {
                    return ListView.builder(
                      itemCount: projects.length,
                      itemBuilder: (context, index) {
                        final p = projects[index];
                        final rowTasks = tasksByProject[p.id] ?? const <Task>[];
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (index > 0)
                              Divider(height: 1, color: Colors.grey.shade300),
                            _ProjectMobileRow(
                              tableColors: tableColors,
                              hierarchyColors: hierarchyColors,
                              project: p,
                              progressPercent: _progressFor(p),
                              appState: state,
                              tasks: rowTasks,
                              subtasksByTask: _subtasksByTask,
                              expandedTaskIds: _expandedTaskIds,
                              expandedSubprojectIds: _expandedSubprojectIds,
                              loadingSubtaskTaskIds: _loadingSubtaskTaskIds,
                              expanded: _expandedProjectIds.contains(p.id),
                              onToggleExpand: () =>
                                  _toggleProjectExpanded(p.id, rowTasks),
                              onToggleTaskExpand: _toggleTaskExpanded,
                              onToggleSubprojectExpand:
                                  _toggleSubprojectExpanded,
                              onTap: () => widget.onOpenProject?.call(p.id),
                              onOpenTask: widget.onOpenTask,
                              onOpenSubtask: widget.onOpenSubtask,
                              onOpenSubproject: widget.onOpenSubproject,
                              selectionWidth: _kProjectSelectionWidth,
                              projectSelected: _selectedProjectIds.contains(
                                p.id,
                              ),
                              onProjectSelected: (checked) =>
                                  _setProjectSelected(p.id, checked),
                              selectedSubprojectIds: _selectedSubprojectIds,
                              onSubprojectSelected: _setSubprojectSelected,
                              selectedTaskIds: _selectedTaskIds,
                              onTaskSelected: _setTaskSelected,
                              selectedSubtaskIds: _selectedSubtaskIds,
                              onSubtaskSelected: _setSubtaskSelected,
                              forceProjectChecks: _pick ==
                                      _StructurePick.makeSubprojectParent ||
                                  _pick == _StructurePick.moveTaskParent ||
                                  _pick == _StructurePick.moveSubprojectParent,
                              forceSubprojectChecks:
                                  _pick == _StructurePick.moveTaskParent,
                              forceTaskChecks: _pick ==
                                      _StructurePick.makeSubtaskParent ||
                                  _pick == _StructurePick.moveSubtaskParent,
                            ),
                          ],
                        );
                      },
                    );
                  }

                  final table = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProjectTableHeader(
                        tableWidth: tableWidth,
                        fillColor: widget.palette.hierarchyHeaderColors.project,
                        reserveLeading: _kProjectSelectionWidth,
                      ),
                      Divider(height: 1, color: Colors.grey.shade300),
                      Expanded(
                        child: ListView.builder(
                          itemCount: projects.length,
                          itemBuilder: (context, index) {
                            final p = projects[index];
                            final rowTasks =
                                tasksByProject[p.id] ?? const <Task>[];
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (index > 0)
                                  Divider(
                                    height: 1,
                                    color: Colors.grey.shade300,
                                  ),
                                _ExpandableProjectTableRow(
                                  tableWidth: tableWidth,
                                  tableColors: tableColors,
                                  hierarchyColors: hierarchyColors,
                                  headerColors:
                                      widget.palette.hierarchyHeaderColors,
                                  project: p,
                                  progressPercent: _progressFor(p),
                                  appState: state,
                                  tasks: rowTasks,
                                  subtasksByTask: _subtasksByTask,
                                  expandedTaskIds: _expandedTaskIds,
                                  expandedSubprojectIds: _expandedSubprojectIds,
                                  loadingSubtaskTaskIds: _loadingSubtaskTaskIds,
                                  expanded: _expandedProjectIds.contains(p.id),
                                  onToggleExpand: () =>
                                      _toggleProjectExpanded(p.id, rowTasks),
                                  onToggleTaskExpand: _toggleTaskExpanded,
                                  onToggleSubprojectExpand:
                                      _toggleSubprojectExpanded,
                                  onRowTap: () =>
                                      widget.onOpenProject?.call(p.id),
                                  onOpenTask: widget.onOpenTask,
                                  onOpenSubtask: widget.onOpenSubtask,
                                  onOpenSubproject: widget.onOpenSubproject,
                                  selectionWidth: _kProjectSelectionWidth,
                                  projectSelected: _selectedProjectIds.contains(
                                    p.id,
                                  ),
                                  onProjectSelected: (checked) =>
                                      _setProjectSelected(p.id, checked),
                                  selectedSubprojectIds:
                                      _selectedSubprojectIds,
                                  onSubprojectSelected: _setSubprojectSelected,
                                  selectedTaskIds: _selectedTaskIds,
                                  onTaskSelected: _setTaskSelected,
                                  selectedSubtaskIds: _selectedSubtaskIds,
                                  onSubtaskSelected: _setSubtaskSelected,
                                  forceProjectChecks: _pick ==
                                          _StructurePick
                                              .makeSubprojectParent ||
                                      _pick == _StructurePick.moveTaskParent ||
                                      _pick ==
                                          _StructurePick.moveSubprojectParent,
                                  forceSubprojectChecks:
                                      _pick == _StructurePick.moveTaskParent,
                                  forceTaskChecks: _pick ==
                                          _StructurePick.makeSubtaskParent ||
                                      _pick ==
                                          _StructurePick.moveSubtaskParent,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );

                  if (constraints.maxWidth <
                      _ProjectTableLayout.minTableWidth) {
                    return ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          height: constraints.maxHeight,
                          child: table,
                        ),
                      ),
                    );
                  }
                  return table;
                },
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  String _scopeLabel() {
    if (_filters.scopes.isEmpty || _filters.scopes.contains('all')) {
      return 'All';
    }
    final labels = <String>[];
    if (_filters.scopes.contains('assigned')) labels.add('Assigned to me');
    if (_filters.scopes.contains('created')) labels.add('Created by me');
    if (labels.isNotEmpty) return labels.join(', ');
    return '${_filters.scopes.length} selected';
  }

  String _statusLabel() {
    if (_filters.statuses.isEmpty) return 'All';
    return _filters.statuses.join(', ');
  }

  String _staffName(AppState state, String id) {
    final key = id.trim();
    if (key.isEmpty) return '';
    final fromProject = _projectStaffNameById(key);
    if (fromProject != null && fromProject.isNotEmpty) return fromProject;
    return state.assigneeById(key)?.name.trim() ?? key;
  }

  String? _projectStaffNameById(String id) {
    for (final project in _displayProjects) {
      final creatorId = project.createByStaffUuid?.trim();
      if (creatorId == id) {
        final name = project.createByDisplayName?.trim();
        if (name != null && name.isNotEmpty && name != id) return name;
      }
      for (var i = 0; i < project.picStaffUuids.length; i++) {
        if (project.picStaffUuids[i].trim() != id) continue;
        if (i < project.picStaffDisplayNames.length) {
          final name = project.picStaffDisplayNames[i].trim();
          if (name.isNotEmpty && name != id) return name;
        }
      }
      for (var i = 0; i < project.assigneeStaffUuids.length; i++) {
        if (project.assigneeStaffUuids[i].trim() != id) continue;
        if (i < project.assigneeStaffDisplayNames.length) {
          final name = project.assigneeStaffDisplayNames[i].trim();
          if (name.isNotEmpty && name != id) return name;
        }
      }
    }
    return null;
  }

  String _staffFilterLabel(AppState state, List<String> ids) {
    if (ids.isEmpty) return 'All';
    if (ids.length == 1) return _staffName(state, ids.first);
    return '${ids.length} selected';
  }

  String _teamFilterLabel(AppState state, List<String> ids) {
    if (ids.isEmpty) {
      return 'All';
    }
    if (ids.length == 1) {
      return state.teamNameById(ids.first);
    }
    return '${ids.length} selected';
  }

  String _creatorLabel(AppState state) =>
      _staffFilterLabel(state, _filters.creatorStaffIds);

  String _picLabel(AppState state) =>
      _staffFilterLabel(state, _filters.picStaffIds);

  String _dueDateLabel() => asanaDueDateRangeFilterLabel(
    _filters.createDateStart,
    _filters.createDateEnd,
  );

  List<AsanaFilterCheckboxOption> _staffOptions(
    AppState state,
    Iterable<String?> ids,
  ) {
    final map = <String, String>{};
    for (final raw in ids) {
      final id = raw?.trim();
      if (id == null || id.isEmpty) continue;
      map[id] = _staffName(state, id);
    }
    final list = map.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      for (final a in list)
        AsanaFilterCheckboxOption(key: a.key, label: a.value),
    ];
  }

  List<AsanaFilterCheckboxOption> _teamOptions(
    AppState state,
    Iterable<String?> teamIds,
  ) {
    final map = <String, String>{};
    for (final raw in teamIds) {
      final id = raw?.trim();
      if (id == null || id.isEmpty) continue;
      map[id] = state.teamNameById(id);
    }
    final list = map.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      for (final team in list)
        AsanaFilterCheckboxOption(key: team.key, label: team.value),
    ];
  }

  Iterable<String?> _visibleCreatorIds() sync* {
    for (final project in _displayProjects) {
      yield project.createByStaffUuid;
    }
  }

  Iterable<String?> _visiblePicIds() sync* {
    for (final project in _displayProjects) {
      for (final id in project.picStaffUuids) {
        yield id;
      }
    }
  }

  Iterable<String?> _visibleCreatorTeamIds(AppState state) sync* {
    for (final id in _visibleCreatorIds()) {
      yield state.teamIdForStaffKey(id);
    }
  }

  Iterable<String?> _visiblePicTeamIds(AppState state) sync* {
    for (final id in _visiblePicIds()) {
      yield state.teamIdForStaffKey(id);
    }
  }

  Future<void> _showDueDateRangePicker(BuildContext buttonContext) async {
    final all = await showMenu<bool>(
      context: buttonContext,
      position: _menuPosition(buttonContext),
      initialValue: !_filters.createDateEngaged,
      color: Theme.of(buttonContext).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      items: const [
        PopupMenuItem(value: true, child: Text('All')),
        PopupMenuItem(value: false, child: Text('Choose date range')),
      ],
    );
    if (all == null) return;
    if (!mounted || !buttonContext.mounted) return;
    if (all) {
      setState(() {
        _filters.createDateStart = null;
        _filters.createDateEnd = null;
      });
      _rebuildList();
      return;
    }
    final picked = await showAsanaAnchoredDateRangePicker(
      anchorContext: buttonContext,
      start: _filters.createDateStart,
      end: _filters.createDateEnd,
    );
    if (picked == null) return;
    setState(() {
      _filters.createDateStart = asanaDateOnlyFromPicker(picked.start);
      _filters.createDateEnd = asanaDateOnlyFromPicker(picked.end);
    });
    _rebuildList();
  }

  Future<void> _showCreatorMenu(BuildContext buttonContext) async {
    final state = context.read<AppState>();
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: _staffOptions(state, _visibleCreatorIds()),
      initialSelection: _filters.creatorStaffIds.toSet(),
    );
    if (selection != null) {
      setState(() => _filters.creatorStaffIds = selection.toList());
      _rebuildList();
    }
  }

  Future<void> _showCreatorTeamMenu(BuildContext buttonContext) async {
    final state = context.read<AppState>();
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: _teamOptions(state, _visibleCreatorTeamIds(state)),
      initialSelection: _filters.creatorTeamIds.toSet(),
    );
    if (selection != null) {
      setState(() => _filters.creatorTeamIds = selection.toList());
      _rebuildList();
    }
  }

  Future<void> _showPicMenu(BuildContext buttonContext) async {
    final state = context.read<AppState>();
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: _staffOptions(state, _visiblePicIds()),
      initialSelection: _filters.picStaffIds.toSet(),
    );
    if (selection != null) {
      setState(() => _filters.picStaffIds = selection.toList());
      _rebuildList();
    }
  }

  Future<void> _showPicTeamMenu(BuildContext buttonContext) async {
    final state = context.read<AppState>();
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: _teamOptions(state, _visiblePicTeamIds(state)),
      initialSelection: _filters.picTeamIds.toSet(),
    );
    if (selection != null) {
      setState(() => _filters.picTeamIds = selection.toList());
      _rebuildList();
    }
  }

  String _sortLabel() {
    final name = switch (_filters.sortKey) {
      'name' => 'Name',
      'created' => 'Created',
      'updated' => 'Last updated',
      _ => 'Due date',
    };
    final arrow = _filters.sortAscending ? '↑' : '↓';
    return '$name $arrow';
  }

  Future<void> _showScopeMenu(BuildContext buttonContext) async {
    const allKey = 'all';
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: const [
        AsanaFilterCheckboxOption(key: allKey, label: 'All', isAll: true),
        AsanaFilterCheckboxOption(key: 'assigned', label: 'Assigned to me'),
        AsanaFilterCheckboxOption(key: 'created', label: 'Created by me'),
      ],
      initialSelection: _filters.scopes,
    );
    if (selection != null) {
      setState(() => _filters.scopes = selection);
      _onFiltersChanged();
    }
  }

  Future<void> _showStatusMenu(BuildContext buttonContext) async {
    const allKey = '__all__';
    const options = [
      'Not started',
      'In progress',
      'Paused',
      'Completed',
      'Deleted',
    ];
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: [
        const AsanaFilterCheckboxOption(key: allKey, label: 'All', isAll: true),
        for (final s in options) AsanaFilterCheckboxOption(key: s, label: s),
      ],
      initialSelection: _filters.statuses,
    );
    if (selection != null) {
      setState(() => _filters.statuses = selection);
      _onFiltersChanged();
    }
  }

  Future<void> _showSortMenu(BuildContext buttonContext) async {
    await showMenu<String>(
      context: buttonContext,
      position: _menuPosition(buttonContext),
      color: Theme.of(buttonContext).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      items: const [
        PopupMenuItem(value: 'due_asc', child: Text('Due date ↑')),
        PopupMenuItem(value: 'due_desc', child: Text('Due date ↓')),
        PopupMenuItem(value: 'created_desc', child: Text('Created ↓')),
        PopupMenuItem(value: 'created_asc', child: Text('Created ↑')),
        PopupMenuItem(value: 'updated_desc', child: Text('Last updated ↓')),
        PopupMenuItem(value: 'updated_asc', child: Text('Last updated ↑')),
        PopupMenuItem(value: 'name_asc', child: Text('Name A–Z')),
        PopupMenuItem(value: 'name_desc', child: Text('Name Z–A')),
      ],
    ).then((v) {
      if (v == null) return;
      setState(() {
        switch (v) {
          case 'due_desc':
            _filters.sortKey = 'due';
            _filters.sortAscending = false;
          case 'created_desc':
            _filters.sortKey = 'created';
            _filters.sortAscending = false;
          case 'created_asc':
            _filters.sortKey = 'created';
            _filters.sortAscending = true;
          case 'updated_desc':
            _filters.sortKey = 'updated';
            _filters.sortAscending = false;
          case 'updated_asc':
            _filters.sortKey = 'updated';
            _filters.sortAscending = true;
          case 'name_asc':
            _filters.sortKey = 'name';
            _filters.sortAscending = true;
          case 'name_desc':
            _filters.sortKey = 'name';
            _filters.sortAscending = false;
          default:
            _filters.sortKey = 'due';
            _filters.sortAscending = true;
        }
      });
      _onFiltersChanged();
    });
  }

  RelativeRect _menuPosition(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return const RelativeRect.fromLTRB(0, 80, 200, 0);
    }
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    return RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + size.height,
      offset.dx + size.width,
      offset.dy + size.height + 4,
    );
  }
}

class _ProjectTableLayout {
  _ProjectTableLayout(this.tableWidth, {this.reserveLeading = 0});

  final double tableWidth;
  final double reserveLeading;

  static const double minTableWidth = 1000;
  static const double typeCol = _ProjectExpandedTaskTableLayout.typeCol;
  static const double typeColGap = 10;

  /// Aligns project name with task list (matches [_TaskTableLayout.nameGutter]).
  static const double nameGutter = 36;

  /// Plain-text columns each followed by a gap before the next column.
  static const int textColumnGapCount = 6;
  static const double singleLineExtent = 24;
  static const double hPad = 12;
  static const double statusColWidth = 140;
  static const double updatedColWidth = 120;

  static const double _flexWeightSum = 0.28 + 0.075 + 0.065 + 0.098 + 0.112;

  late final double _inner =
      (tableWidth -
              reserveLeading -
              typeCol -
              typeColGap -
              kAsanaTextColumnGap * textColumnGapCount -
              hPad * 2 -
              statusColWidth -
              updatedColWidth)
          .clamp(320, double.infinity);

  double get nameCol => _inner * (0.28 / _flexWeightSum);
  double get dueCol => _inner * (0.075 / _flexWeightSum);
  double get creatorCol => _inner * (0.065 / _flexWeightSum);
  double get picCol => _inner * (0.098 / _flexWeightSum);
  double get assigneeCol => _inner * (0.112 / _flexWeightSum);
  double get updatedCol => updatedColWidth;
  double get statusCol => statusColWidth;
}

class _ProjectExpandedTaskTableLayout {
  _ProjectExpandedTaskTableLayout(this.tableWidth, {this.reserveLeading = 0});

  final double tableWidth;
  final double reserveLeading;

  static const double typeColGap = 10;
  static const double nameGutter = 36;
  static const double singleLineExtent = 24;
  static const double hPad = 12;
  static const double hierarchyIndentStep = 13;
  static const double typeLetterBox = 30;
  static const double typeCol = hierarchyIndentStep * 3 + typeLetterBox;

  static const double nestedStatusCol = _ProjectTableLayout.statusColWidth;
  static const double nestedSubmissionCol = 104;

  /// Fixed left-to-right slots: P → SP → T → ST.
  static int typeRank(String letter) {
    switch (letter.trim().toUpperCase()) {
      case 'SP':
        return 1;
      case 'T':
        return 2;
      case 'ST':
        return 3;
      default:
        return 0;
    }
  }

  static Widget typeMarker({
    required String letter,
    bool completed = false,
    bool deleted = false,
    String? status,
  }) {
    final left = typeRank(letter) * hierarchyIndentStep;
    return SizedBox(
      width: typeCol,
      child: Padding(
        padding: EdgeInsets.only(left: left.toDouble()),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AsanaRowTypeLetter(
            letter: letter,
            completed: completed,
            deleted: deleted,
            status: status,
          ),
        ),
      ),
    );
  }

  late final _projectCols = _ProjectTableLayout(
    tableWidth,
    reserveLeading: reserveLeading,
  );

  double get taskNameCol => _projectCols.nameCol;
  double get dueCol => _projectCols.dueCol;
  double get creatorCol => _projectCols.creatorCol;
  double get picCol => _projectCols.picCol;
  double get assigneeCol => _projectCols.assigneeCol;
  double get statusCol => _projectCols.statusCol;
  double get updatedCol => _projectCols.updatedCol;
}

class _ProjectTableHeader extends StatelessWidget {
  const _ProjectTableHeader({
    required this.tableWidth,
    required this.fillColor,
    this.reserveLeading = 0,
  });

  final double tableWidth;
  final Color fillColor;
  final double reserveLeading;

  @override
  Widget build(BuildContext context) {
    final cols = _ProjectTableLayout(
      tableWidth,
      reserveLeading: reserveLeading,
    );
    final style = asanaTableHeaderStyle(
      context,
      color: asanaOnHeaderFill(fillColor),
    );
    return asanaTableHeaderShell(
      fillColor: fillColor,
      horizontalPad: _ProjectTableLayout.hPad,
      child: Row(
        children: [
          if (reserveLeading > 0) SizedBox(width: reserveLeading),
          SizedBox(
            width: _ProjectTableLayout.typeCol,
            child: Text('', style: style),
          ),
          const SizedBox(width: _ProjectTableLayout.typeColGap),
          SizedBox(
            width: cols.nameCol,
            child: Row(
              children: [
                const SizedBox(width: _ProjectTableLayout.nameGutter),
                Expanded(child: Text('Project Name', style: style)),
              ],
            ),
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.dueCol,
            label: 'Due Date',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.creatorCol,
            label: 'Creator',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.picCol,
            label: 'PIC',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.assigneeCol,
            label: 'Assignees',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.statusCol,
            label: 'Status',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.updatedCol,
            label: 'Last updated',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
        ],
      ),
    );
  }
}

class _ExpandableProjectTableRow extends StatelessWidget {
  const _ExpandableProjectTableRow({
    required this.tableWidth,
    required this.tableColors,
    required this.hierarchyColors,
    required this.headerColors,
    required this.project,
    required this.progressPercent,
    required this.appState,
    required this.tasks,
    required this.subtasksByTask,
    required this.expandedTaskIds,
    required this.expandedSubprojectIds,
    required this.loadingSubtaskTaskIds,
    required this.expanded,
    required this.onToggleExpand,
    required this.onToggleTaskExpand,
    required this.onToggleSubprojectExpand,
    this.onRowTap,
    this.onOpenTask,
    this.onOpenSubtask,
    this.onOpenSubproject,
    this.selectionWidth = 0,
    this.projectSelected = false,
    this.onProjectSelected,
    this.selectedSubprojectIds = const {},
    this.onSubprojectSelected,
    this.selectedTaskIds = const {},
    this.onTaskSelected,
    this.selectedSubtaskIds = const {},
    this.onSubtaskSelected,
    this.forceProjectChecks = false,
    this.forceSubprojectChecks = false,
    this.forceTaskChecks = false,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final AsanaHierarchyRowColors hierarchyColors;
  final AsanaHierarchyHeaderColors headerColors;
  final ProjectRecord project;
  final int progressPercent;
  final AppState appState;
  final List<Task> tasks;
  final Map<String, List<SingularSubtask>> subtasksByTask;
  final Set<String> expandedTaskIds;
  final Set<String> expandedSubprojectIds;
  final Set<String> loadingSubtaskTaskIds;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final void Function(Task task) onToggleTaskExpand;
  final void Function(String subprojectId) onToggleSubprojectExpand;
  final VoidCallback? onRowTap;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;
  final void Function(String subprojectId, String projectId)? onOpenSubproject;
  final double selectionWidth;
  final bool projectSelected;
  final ValueChanged<bool>? onProjectSelected;
  final Set<String> selectedSubprojectIds;
  final void Function(String subprojectId, bool selected)? onSubprojectSelected;
  final Set<String> selectedTaskIds;
  final void Function(String taskId, bool selected)? onTaskSelected;
  final Set<String> selectedSubtaskIds;
  final void Function(String subtaskId, bool selected)? onSubtaskSelected;
  final bool forceProjectChecks;
  final bool forceSubprojectChecks;
  final bool forceTaskChecks;

  @override
  Widget build(BuildContext context) {
    final subprojects = AsanaProjectFilter.visibleSubprojectsForProject(
      appState,
      project.id,
    );
    final hasChildren = tasks.isNotEmpty || subprojects.isNotEmpty;
    return SizedBox(
      width: tableWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProjectTableRow(
            tableWidth: tableWidth,
            tableColors: tableColors,
            rowColor: hierarchyColors.project,
            project: project,
            progressPercent: progressPercent,
            appState: appState,
            onRowTap: onRowTap,
            reserveLeading: selectionWidth,
            selected: projectSelected,
            forceSelectionVisible: forceProjectChecks,
            onSelected: onProjectSelected,
            expandControl: hasChildren
                ? _ProjectExpandChevron(
                    expanded: expanded,
                    onPressed: onToggleExpand,
                    color: asanaInkIfDark(hierarchyColors.project),
                  )
                : null,
          ),
          if (hasChildren)
            _AnimatedProjectTaskExpansion(
              expanded: expanded,
              child: ColoredBox(
                color: hierarchyColors.subtask,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ..._expandedProjectChildRows(
                        tableWidth: tableWidth,
                        tableColors: tableColors,
                        hierarchyColors: hierarchyColors,
                        headerColors: headerColors,
                        appState: appState,
                        subprojects: subprojects,
                        tasks: tasks,
                        subtasksByTask: subtasksByTask,
                        expandedTaskIds: expandedTaskIds,
                        expandedSubprojectIds: expandedSubprojectIds,
                        loadingSubtaskTaskIds: loadingSubtaskTaskIds,
                        onToggleTaskExpand: onToggleTaskExpand,
                        onToggleSubprojectExpand: onToggleSubprojectExpand,
                        onOpenTask: onOpenTask,
                        onOpenSubtask: onOpenSubtask,
                        onOpenSubproject: onOpenSubproject,
                        reserveLeading: selectionWidth,
                        selectedSubprojectIds: selectedSubprojectIds,
                        onSubprojectSelected: onSubprojectSelected,
                        selectedTaskIds: selectedTaskIds,
                        onTaskSelected: onTaskSelected,
                        selectedSubtaskIds: selectedSubtaskIds,
                        onSubtaskSelected: onSubtaskSelected,
                        forceSubprojectChecks: forceSubprojectChecks,
                        forceTaskChecks: forceTaskChecks,
                      ),
                      _ProjectTableHeader(
                        tableWidth: tableWidth,
                        fillColor: headerColors.project,
                        reserveLeading: selectionWidth,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedProjectTaskExpansion extends StatelessWidget {
  const _AnimatedProjectTaskExpansion({
    required this.expanded,
    required this.child,
  });

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        offset: expanded ? Offset.zero : const Offset(0, -0.08),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded ? child : const SizedBox(width: double.infinity),
        ),
      ),
    );
  }
}

class _ProjectExpandChevron extends StatelessWidget {
  const _ProjectExpandChevron({
    required this.expanded,
    required this.onPressed,
    this.color,
  });

  final bool expanded;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _ProjectTableLayout.nameGutter,
      height: _ProjectTableLayout.singleLineExtent,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 20,
              color: color ?? kAsanaTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectTaskSectionHeader extends StatelessWidget {
  const _ProjectTaskSectionHeader({
    required this.tableWidth,
    required this.fillColor,
    this.nameLabel = 'Task Name',
    this.showSubmission = true,
    this.reserveLeading = 0,
  });

  final double tableWidth;
  final Color fillColor;
  final String nameLabel;
  final bool showSubmission;
  final double reserveLeading;

  @override
  Widget build(BuildContext context) {
    final cols = _ProjectExpandedTaskTableLayout(
      tableWidth,
      reserveLeading: reserveLeading,
    );
    final style = asanaTableHeaderStyle(
      context,
      color: asanaOnHeaderFill(fillColor),
    );
    return asanaTableHeaderShell(
      fillColor: fillColor,
      horizontalPad: _ProjectExpandedTaskTableLayout.hPad,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (reserveLeading > 0) SizedBox(width: reserveLeading),
          SizedBox(
            width: _ProjectExpandedTaskTableLayout.typeCol,
            child: Text('', style: style),
          ),
          const SizedBox(width: _ProjectExpandedTaskTableLayout.typeColGap),
          SizedBox(
            width: cols.taskNameCol,
            height: kAsanaTableHeaderLineExtent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(
                  width: _ProjectExpandedTaskTableLayout.nameGutter,
                ),
                Expanded(
                  child: Text(
                    nameLabel,
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.dueCol,
            label: 'Due Date',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.creatorCol,
            label: 'Creator',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.picCol,
            label: 'PIC',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.assigneeCol,
            label: 'Assignees',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.statusCol,
            label: 'Status',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.updatedCol,
            label: 'Last updated',
            style: style,
            rowHeight: kAsanaTableHeaderLineExtent,
          ),
          if (showSubmission) ...[
            asanaTextColumnGap(),
            asanaTableHeaderLabel(
              width: _ProjectExpandedTaskTableLayout.nestedSubmissionCol,
              label: 'Submission',
              style: style,
              rowHeight: kAsanaTableHeaderLineExtent,
            ),
          ],
        ],
      ),
    );
  }
}

List<Widget> _expandedProjectChildRows({
  required double tableWidth,
  required AsanaTableColors tableColors,
  required AsanaHierarchyRowColors hierarchyColors,
  required AsanaHierarchyHeaderColors headerColors,
  required AppState appState,
  required List<SubprojectRecord> subprojects,
  required List<Task> tasks,
  required Map<String, List<SingularSubtask>> subtasksByTask,
  required Set<String> expandedTaskIds,
  required Set<String> expandedSubprojectIds,
  required Set<String> loadingSubtaskTaskIds,
  required void Function(Task task) onToggleTaskExpand,
  required void Function(String subprojectId) onToggleSubprojectExpand,
  void Function(String taskId)? onOpenTask,
  void Function(String subtaskId)? onOpenSubtask,
  void Function(String subprojectId, String projectId)? onOpenSubproject,
  double reserveLeading = 0,
  Set<String> selectedSubprojectIds = const {},
  void Function(String subprojectId, bool selected)? onSubprojectSelected,
  Set<String> selectedTaskIds = const {},
  void Function(String taskId, bool selected)? onTaskSelected,
  Set<String> selectedSubtaskIds = const {},
  void Function(String subtaskId, bool selected)? onSubtaskSelected,
  bool forceSubprojectChecks = false,
  bool forceTaskChecks = false,
}) {
  final widgets = <Widget>[];
  final nestedTaskIds = <String>{};
  String? openSection;

  void addSectionHeader(String nameLabel) {
    widgets.add(
      _ProjectTaskSectionHeader(
        tableWidth: tableWidth,
        nameLabel: nameLabel,
        fillColor: headerColors.forNameLabel(nameLabel),
        showSubmission: nameLabel != 'Sub-project Name',
        reserveLeading: reserveLeading,
      ),
    );
  }

  void ensureSection(String section, String nameLabel) {
    if (openSection == section) return;
    addSectionHeader(nameLabel);
    openSection = section;
  }

  void interruptSection() => openSection = null;

  bool taskShowsSubtasks(Task task) {
    if (!expandedTaskIds.contains(task.id)) return false;
    if (loadingSubtaskTaskIds.contains(task.id)) return true;
    final list = subtasksByTask[task.id];
    return list != null && list.isNotEmpty;
  }

  void addTask(Task task, {required int indentLevel}) {
    ensureSection('task', 'Task Name');
    widgets.add(
      _ProjectTaskDataRow(
        tableWidth: tableWidth,
        tableColors: tableColors,
        hierarchyColors: hierarchyColors,
        headerColors: headerColors,
        appState: appState,
        task: task,
        indentLevel: indentLevel,
        subtasks: subtasksByTask[task.id] ?? const <SingularSubtask>[],
        subtasksKnown: subtasksByTask.containsKey(task.id),
        expanded: expandedTaskIds.contains(task.id),
        loadingSubtasks: loadingSubtaskTaskIds.contains(task.id),
        showDivider: widgets.isNotEmpty,
        onToggleExpand: () => onToggleTaskExpand(task),
        onOpenTask: onOpenTask,
        onOpenSubtask: onOpenSubtask,
        reserveLeading: reserveLeading,
        selected: selectedTaskIds.contains(task.id),
        forceSelectionVisible: forceTaskChecks,
        onSelected: onTaskSelected == null
            ? null
            : (checked) => onTaskSelected(task.id, checked),
        selectedSubtaskIds: selectedSubtaskIds,
        onSubtaskSelected: onSubtaskSelected,
      ),
    );
    if (taskShowsSubtasks(task)) interruptSection();
  }

  if (subprojects.isNotEmpty) {
    for (final subproject in subprojects) {
      final childTasks = [
        for (final task in tasks)
          if (task.subprojectId?.trim() == subproject.id) task,
      ];
      nestedTaskIds.addAll(childTasks.map((t) => t.id));
      final expanded = expandedSubprojectIds.contains(subproject.id);
      ensureSection('sp', 'Sub-project Name');
      widgets.add(
        _ProjectSubprojectDataRow(
          tableWidth: tableWidth,
          tableColors: tableColors,
          hierarchyColors: hierarchyColors,
          subproject: subproject,
          showDivider: widgets.isNotEmpty,
          hasTasks: childTasks.isNotEmpty,
          expanded: expanded,
          onToggleExpand: () => onToggleSubprojectExpand(subproject.id),
          onOpenSubproject: onOpenSubproject,
          reserveLeading: reserveLeading,
          selected: selectedSubprojectIds.contains(subproject.id),
          forceSelectionVisible: forceSubprojectChecks,
          onSelected: onSubprojectSelected == null
              ? null
              : (checked) => onSubprojectSelected(subproject.id, checked),
        ),
      );
      if (expanded && childTasks.isNotEmpty) {
        for (final task in childTasks) {
          addTask(task, indentLevel: 2);
        }
        interruptSection();
      }
    }
  }
  final directTasks = [
    for (final task in tasks)
      if (!nestedTaskIds.contains(task.id)) task,
  ];
  for (final task in directTasks) {
    addTask(task, indentLevel: 1);
  }
  return widgets;
}

class _ProjectSubprojectDataRow extends StatelessWidget {
  const _ProjectSubprojectDataRow({
    required this.tableWidth,
    required this.tableColors,
    required this.hierarchyColors,
    required this.subproject,
    required this.showDivider,
    required this.hasTasks,
    required this.expanded,
    required this.onToggleExpand,
    this.onOpenSubproject,
    this.reserveLeading = 0,
    this.selected = false,
    this.forceSelectionVisible = false,
    this.onSelected,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final AsanaHierarchyRowColors hierarchyColors;
  final SubprojectRecord subproject;
  final bool showDivider;
  final bool hasTasks;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final void Function(String subprojectId, String projectId)? onOpenSubproject;
  final double reserveLeading;
  final bool selected;
  final bool forceSelectionVisible;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final completed = subproject.isCompleted;
    final cols = _ProjectExpandedTaskTableLayout(
      tableWidth,
      reserveLeading: reserveLeading,
    );
    final ink = asanaInkIfDark(hierarchyColors.subproject);
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: true,
      color: ink,
    );
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
      color: ink,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider)
          Divider(
            height: 1,
            indent:
                _ProjectExpandedTaskTableLayout.hPad +
                _ProjectExpandedTaskTableLayout.typeCol +
                _ProjectExpandedTaskTableLayout.typeColGap +
                _ProjectExpandedTaskTableLayout.nameGutter,
            color: Colors.grey.shade200,
          ),
        Material(
          color: hierarchyColors.subproject,
          child: InkWell(
            onTap: onOpenSubproject == null
                ? null
                : () => onOpenSubproject!(subproject.id, subproject.projectId),
            child: Padding(
            padding: const EdgeInsets.fromLTRB(
              _ProjectExpandedTaskTableLayout.hPad,
              10,
              _ProjectExpandedTaskTableLayout.hPad,
              10,
            ),
            child: SizedBox(
              width: tableWidth - _ProjectExpandedTaskTableLayout.hPad * 2,
              child: Row(
                children: [
                  if (onSelected != null)
                    _ProjectSelectionBox(
                      width: reserveLeading,
                      selected: selected,
                      forceVisible: forceSelectionVisible,
                      itemId: subproject.id,
                      onChanged: onSelected!,
                    ),
                  _ProjectExpandedTaskTableLayout.typeMarker(
                    letter: 'SP',
                    completed: completed,
                    deleted: subproject.isDeleted,
                    status: subproject.isPaused
                        ? 'Paused'
                        : subproject.status,
                  ),
                  const SizedBox(
                    width: _ProjectExpandedTaskTableLayout.typeColGap,
                  ),
                  SizedBox(
                    width: cols.taskNameCol,
                    child: Row(
                      children: [
                        SizedBox(
                          width: _ProjectExpandedTaskTableLayout.nameGutter,
                          height:
                              _ProjectExpandedTaskTableLayout.singleLineExtent,
                          child: hasTasks
                              ? _ProjectNestedExpandChevron(
                                  expanded: expanded,
                                  loading: false,
                                  onPressed: onToggleExpand,
                                  color: asanaInkIfDark(
                                    hierarchyColors.subproject,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        Expanded(
                          child: AsanaNameWithFreshness(
                            name: subproject.name.trim().isEmpty
                                ? '(Unnamed sub-project)'
                                : subproject.name.trim(),
                            style: nameStyle,
                            createdAt: subproject.createDate,
                            updatedAt: subproject.updateDate,
                          ),
                        ),
                      ],
                    ),
                  ),
                  asanaTextColumnGap(),
                  SizedBox(
                    width: cols.dueCol,
                    child: Text(
                      subproject.endDate == null
                          ? '—'
                          : HkTime.formatInstantAsHk(
                              subproject.endDate!,
                              'MMM d, yyyy',
                            ),
                      style: rowValueStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  asanaTextColumnGap(),
                  SizedBox(
                    width: cols.creatorCol,
                    child: Text(
                      (subproject.createByDisplayName ?? '').trim().isEmpty
                          ? '—'
                          : subproject.createByDisplayName!.trim(),
                      style: rowValueStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  asanaTextColumnGap(),
                  SizedBox(
                    width: cols.picCol,
                    child: Text(
                      subproject.picStaffDisplayNames
                              .where((n) => n.trim().isNotEmpty)
                              .join(', ')
                              .trim()
                              .isEmpty
                          ? '—'
                          : subproject.picStaffDisplayNames
                              .where((n) => n.trim().isNotEmpty)
                              .join(', '),
                      style: rowValueStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  asanaTextColumnGap(),
                  SizedBox(
                    width: cols.assigneeCol,
                    child: Text(
                      subproject.assigneeStaffDisplayNames
                              .where((n) => n.trim().isNotEmpty)
                              .join(', ')
                              .trim()
                              .isEmpty
                          ? '—'
                          : subproject.assigneeStaffDisplayNames
                              .where((n) => n.trim().isNotEmpty)
                              .join(', '),
                      style: rowValueStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  asanaTextColumnGap(),
                  SizedBox(
                    width: cols.statusCol,
                    child: AsanaTableCellChip(
                      child: AsanaStatusChip(
                        status: subproject.isPaused
                            ? 'Paused'
                            : subproject.status,
                      ),
                    ),
                  ),
                  asanaTextColumnGap(),
                  SizedBox(
                    width: cols.updatedCol,
                    child: Text(
                      _formatUpdatedDate(subproject.updateDate),
                      style: rowValueStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
      ],
    );
  }
}

class _ProjectTaskDataRow extends StatelessWidget {
  const _ProjectTaskDataRow({
    required this.tableWidth,
    required this.tableColors,
    required this.hierarchyColors,
    required this.headerColors,
    required this.appState,
    required this.task,
    this.indentLevel = 1,
    required this.subtasks,
    required this.subtasksKnown,
    required this.expanded,
    required this.loadingSubtasks,
    required this.showDivider,
    required this.onToggleExpand,
    this.onOpenTask,
    this.onOpenSubtask,
    this.reserveLeading = 0,
    this.selected = false,
    this.forceSelectionVisible = false,
    this.onSelected,
    this.selectedSubtaskIds = const {},
    this.onSubtaskSelected,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final AsanaHierarchyRowColors hierarchyColors;
  final AsanaHierarchyHeaderColors headerColors;
  final AppState appState;
  final Task task;
  final int indentLevel;
  final List<SingularSubtask> subtasks;
  final bool subtasksKnown;
  final bool expanded;
  final bool loadingSubtasks;
  final bool showDivider;
  final VoidCallback onToggleExpand;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;
  final double reserveLeading;
  final bool selected;
  final bool forceSelectionVisible;
  final ValueChanged<bool>? onSelected;
  final Set<String> selectedSubtaskIds;
  final void Function(String subtaskId, bool selected)? onSubtaskSelected;

  @override
  Widget build(BuildContext context) {
    final status = AsanaTaskFilter.taskDisplayStatus(appState, task);
    final completed = _taskCompleted(task);
    final ink = asanaInkIfDark(hierarchyColors.task);
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
      color: ink,
    );
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: true,
      color: ink,
    );
    final cols = _ProjectExpandedTaskTableLayout(
      tableWidth,
      reserveLeading: reserveLeading,
    );
    final hasSubtasks = subtasks.isNotEmpty;
    final showSubtaskControl = loadingSubtasks || hasSubtasks;
    final showSubtaskExpansion = loadingSubtasks || hasSubtasks;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider)
          Divider(
            height: 1,
            indent:
                _ProjectExpandedTaskTableLayout.hPad +
                _ProjectExpandedTaskTableLayout.typeCol +
                _ProjectExpandedTaskTableLayout.typeColGap +
                _ProjectExpandedTaskTableLayout.nameGutter,
            color: Colors.grey.shade200,
          ),
        Material(
          color: hierarchyColors.task,
          child: InkWell(
            onTap: () => onOpenTask?.call(task.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                _ProjectExpandedTaskTableLayout.hPad,
                10,
                _ProjectExpandedTaskTableLayout.hPad,
                10,
              ),
              child: SizedBox(
                width: tableWidth - _ProjectExpandedTaskTableLayout.hPad * 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (onSelected != null)
                      _ProjectSelectionBox(
                        width: reserveLeading,
                        selected: selected,
                        forceVisible: forceSelectionVisible,
                        itemId: task.id,
                        onChanged: onSelected!,
                      )
                    else if (reserveLeading > 0)
                      SizedBox(width: reserveLeading),
                    _ProjectExpandedTaskTableLayout.typeMarker(
                      letter: 'T',
                      completed: completed,
                      deleted: _taskDeleted(task),
                      status: status,
                    ),
                    const SizedBox(
                      width: _ProjectExpandedTaskTableLayout.typeColGap,
                    ),
                    SizedBox(
                      width: cols.taskNameCol,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: _ProjectExpandedTaskTableLayout.nameGutter,
                            height: _ProjectExpandedTaskTableLayout
                                .singleLineExtent,
                            child: Center(
                              child: showSubtaskControl
                                  ? _ProjectNestedExpandChevron(
                                      expanded: expanded,
                                      loading: loadingSubtasks,
                                      onPressed: onToggleExpand,
                                      color: asanaInkIfDark(
                                        hierarchyColors.task,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          Expanded(
                            child: AsanaNameWithFreshness(
                              name: task.name.trim().isEmpty
                                  ? '(Unnamed task)'
                                  : task.name.trim(),
                              style: nameStyle,
                              createdAt: task.createdAt,
                              updatedAt: task.updateDate,
                            ),
                          ),
                        ],
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.dueCol,
                      child: Text(
                        _formatDueDate(
                          visibleScheduleDate(
                            task.endDate,
                            task.commencementStatus,
                          ),
                        ),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.creatorCol,
                      child: Text(
                        (task.createByStaffName ?? '').trim().isEmpty
                            ? '—'
                            : task.createByStaffName!.trim(),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.picCol,
                      child: Text(
                        _formatTaskPic(appState, task.pic),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.assigneeCol,
                      child: Text(
                        _formatTaskAssignees(appState, task.assigneeIds),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.statusCol,
                      child: AsanaTableCellChip(
                        child: AsanaStatusChip(status: status),
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.updatedCol,
                      child: Text(
                        _formatUpdatedDate(
                          task.lastUpdated ?? task.updateDate,
                        ),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width:
                          _ProjectExpandedTaskTableLayout.nestedSubmissionCol,
                      child: AsanaTableCellChip(
                        child: AsanaSubmissionChip(submission: task.submission),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showSubtaskExpansion)
          _AnimatedProjectTaskExpansion(
            expanded: expanded,
            child: ColoredBox(
              color: hierarchyColors.subtask,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProjectTaskSectionHeader(
                    tableWidth: tableWidth,
                    nameLabel: 'Sub-task Name',
                    fillColor: headerColors.subtask,
                    reserveLeading: reserveLeading,
                  ),
                  if (loadingSubtasks)
                    const _ProjectSubtaskStatusRow(
                      message: 'Loading sub-tasks...',
                    )
                  else
                    for (var i = 0; i < subtasks.length; i++)
                      _ProjectSubtaskDataRow(
                        tableWidth: tableWidth,
                        tableColors: tableColors,
                        hierarchyColors: hierarchyColors,
                        appState: appState,
                        parentTask: task,
                        subtask: subtasks[i],
                        indentLevel: indentLevel + 1,
                        showDivider: i > 0,
                        onOpenSubtask: onOpenSubtask,
                        reserveLeading: reserveLeading,
                        selected: selectedSubtaskIds.contains(subtasks[i].id),
                        forceSelectionVisible: false,
                        onSelected: onSubtaskSelected == null
                            ? null
                            : (checked) =>
                                  onSubtaskSelected!(subtasks[i].id, checked),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ProjectNestedExpandChevron extends StatelessWidget {
  const _ProjectNestedExpandChevron({
    required this.expanded,
    required this.loading,
    required this.onPressed,
    this.color,
  });

  final bool expanded;
  final bool loading;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _ProjectExpandedTaskTableLayout.nameGutter,
      height: _ProjectExpandedTaskTableLayout.singleLineExtent,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  )
                : Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 22,
                    color: color ?? kAsanaTextPrimary,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ProjectSubtaskStatusRow extends StatelessWidget {
  const _ProjectSubtaskStatusRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _ProjectExpandedTaskTableLayout.hPad,
        8,
        _ProjectExpandedTaskTableLayout.hPad,
        10,
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: kAsanaTextSecondary),
      ),
    );
  }
}

class _ProjectSubtaskDataRow extends StatelessWidget {
  const _ProjectSubtaskDataRow({
    required this.tableWidth,
    required this.tableColors,
    required this.hierarchyColors,
    required this.appState,
    required this.parentTask,
    required this.subtask,
    this.indentLevel = 2,
    required this.showDivider,
    this.onOpenSubtask,
    this.reserveLeading = 0,
    this.selected = false,
    this.forceSelectionVisible = false,
    this.onSelected,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final AsanaHierarchyRowColors hierarchyColors;
  final AppState appState;
  final Task parentTask;
  final SingularSubtask subtask;
  final int indentLevel;
  final bool showDivider;
  final void Function(String subtaskId)? onOpenSubtask;
  final double reserveLeading;
  final bool selected;
  final bool forceSelectionVisible;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final status = AsanaTaskFilter.subtaskDisplayStatus(
      appState,
      parentTask,
      subtask,
    );
    final completed = _subtaskCompleted(subtask);
    final ink = asanaInkIfDark(hierarchyColors.subtask);
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
      color: ink,
    );
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: true,
      color: ink,
    );
    final cols = _ProjectExpandedTaskTableLayout(
      tableWidth,
      reserveLeading: reserveLeading,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider)
          Divider(
            height: 1,
            indent:
                _ProjectExpandedTaskTableLayout.hPad +
                _ProjectExpandedTaskTableLayout.typeCol +
                _ProjectExpandedTaskTableLayout.typeColGap +
                _ProjectExpandedTaskTableLayout.nameGutter,
            color: Colors.grey.shade200,
          ),
        Material(
          color: hierarchyColors.subtask,
          child: InkWell(
            onTap: () => onOpenSubtask?.call(subtask.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                _ProjectExpandedTaskTableLayout.hPad,
                10,
                _ProjectExpandedTaskTableLayout.hPad,
                10,
              ),
              child: SizedBox(
                width: tableWidth - _ProjectExpandedTaskTableLayout.hPad * 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (onSelected != null)
                      _ProjectSelectionBox(
                        width: reserveLeading,
                        selected: selected,
                        forceVisible: forceSelectionVisible,
                        itemId: subtask.id,
                        onChanged: onSelected!,
                      )
                    else if (reserveLeading > 0)
                      SizedBox(width: reserveLeading),
                    _ProjectExpandedTaskTableLayout.typeMarker(
                      letter: 'ST',
                      completed: completed,
                      deleted: subtask.isDeleted,
                      status: status,
                    ),
                    const SizedBox(
                      width: _ProjectExpandedTaskTableLayout.typeColGap,
                    ),
                    SizedBox(
                      width: cols.taskNameCol,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: _ProjectExpandedTaskTableLayout.nameGutter,
                            height: _ProjectExpandedTaskTableLayout
                                .singleLineExtent,
                            child: const SizedBox.shrink(),
                          ),
                          Expanded(
                            child: AsanaNameWithFreshness(
                              name: subtask.subtaskName.trim().isEmpty
                                  ? '(Unnamed sub-task)'
                                  : subtask.subtaskName.trim(),
                              style: nameStyle,
                              createdAt: subtask.createDate,
                              updatedAt: subtask.updateDate,
                            ),
                          ),
                        ],
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.dueCol,
                      child: Text(
                        _formatDueDate(
                          visibleScheduleDate(
                            subtask.dueDate,
                            subtask.commencementStatus,
                          ),
                        ),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.creatorCol,
                      child: Text(
                        (subtask.createByStaffName ?? '').trim().isEmpty
                            ? '—'
                            : subtask.createByStaffName!.trim(),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.picCol,
                      child: Text(
                        _formatTaskPic(appState, subtask.pic),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.assigneeCol,
                      child: Text(
                        _formatTaskAssignees(appState, subtask.assigneeIds),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.statusCol,
                      child: AsanaTableCellChip(
                        child: AsanaStatusChip(status: status),
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.updatedCol,
                      child: Text(
                        _formatUpdatedDate(
                          subtask.lastUpdated ?? subtask.updateDate,
                        ),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width:
                          _ProjectExpandedTaskTableLayout.nestedSubmissionCol,
                      child: AsanaTableCellChip(
                        child: AsanaSubmissionChip(
                          submission: subtask.submission,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProjectProgressPercent extends StatelessWidget {
  const _ProjectProgressPercent({required this.percent, this.color});

  final int percent;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ??
        (percent >= 100
            ? const Color(0xFF1B7A4E)
            : percent <= 0
            ? kAsanaTextSecondary
            : Theme.of(context).colorScheme.primary);
    final fill = (percent.clamp(0, 100)) / 100;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text(
            '$percent%',
            style: asanaTextStyle(
              Theme.of(context).textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFFE6E7E8)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: fill,
                        heightFactor: 1,
                        child: ColoredBox(color: color),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectTableRow extends StatelessWidget {
  const _ProjectTableRow({
    required this.tableWidth,
    required this.tableColors,
    required this.rowColor,
    required this.project,
    required this.progressPercent,
    required this.appState,
    this.onRowTap,
    this.expandControl,
    this.reserveLeading = 0,
    this.selected = false,
    this.onSelected,
    this.forceSelectionVisible = false,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final Color rowColor;
  final ProjectRecord project;
  final int progressPercent;
  final AppState appState;
  final VoidCallback? onRowTap;
  final Widget? expandControl;
  final double reserveLeading;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool forceSelectionVisible;

  bool get _completed => project.status.trim() == 'Completed';
  bool get _deleted {
    final s = project.status.trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  @override
  Widget build(BuildContext context) {
    final cols = _ProjectTableLayout(
      tableWidth,
      reserveLeading: reserveLeading,
    );
    final ink = asanaInkIfDark(rowColor);
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: _completed,
      color: ink,
    );
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: _completed,
      color: ink,
    );

    final status = project.isPaused ? 'Paused' : project.status;
    return Material(
      color: rowColor,
      child: InkWell(
        onTap: onRowTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _ProjectTableLayout.hPad,
            vertical: 10,
          ),
          child: SizedBox(
            width: tableWidth - _ProjectTableLayout.hPad * 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (onSelected != null)
                  _ProjectSelectionBox(
                    width: reserveLeading,
                    selected: selected,
                    forceVisible: forceSelectionVisible,
                    itemId: project.id,
                    onChanged: onSelected!,
                  ),
                _ProjectExpandedTaskTableLayout.typeMarker(
                  letter: 'P',
                  completed: _completed,
                  deleted: _deleted,
                  status: status,
                ),
                const SizedBox(width: _ProjectTableLayout.typeColGap),
                SizedBox(
                  width: cols.nameCol,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _ProjectTableLayout.nameGutter,
                        height: _ProjectTableLayout.singleLineExtent,
                        child: Center(
                          child: expandControl ?? const SizedBox.shrink(),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AsanaNameWithFreshness(
                              name: project.name,
                              style: nameStyle,
                              createdAt: project.createDate,
                              updatedAt: project.updateDate,
                            ),
                            _ProjectProgressPercent(
                              percent: progressPercent,
                              color: ink,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.dueCol,
                  child: Text(
                    _formatDueDate(project.endDate),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.creatorCol,
                  child: Text(
                    AsanaProjectFilter.creatorLine(project, appState),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.picCol,
                  child: Text(
                    AsanaProjectFilter.picLine(project, appState),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.assigneeCol,
                  child: Text(
                    AsanaProjectFilter.assigneesLine(project, appState),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.statusCol,
                  child: AsanaTableCellChip(
                    child: AsanaStatusChip(
                      status: project.isPaused ? 'Paused' : project.status,
                    ),
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.updatedCol,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _formatUpdatedDate(project.updateDate),
                      style: rowValueStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                    ),
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

/// Shared mobile card: type letter + optional chevron, then name / Cr·PIC / Start·Due + status.
class _ProjectMobileBlock extends StatelessWidget {
  const _ProjectMobileBlock({
    required this.rowColor,
    required this.letter,
    required this.status,
    required this.name,
    required this.nameStyle,
    required this.valueStyle,
    required this.creator,
    required this.pic,
    this.startDate,
    this.dueDate,
    this.createdAt,
    this.updatedAt,
    this.completed = false,
    this.deleted = false,
    this.expandControl,
    this.onTap,
    this.onLongPress,
    this.trailingChips = const [],
    this.progressPercent,
    this.bottomLeading,
  });

  final Color rowColor;
  final String letter;
  final String status;
  final String name;
  final TextStyle? nameStyle;
  final TextStyle? valueStyle;
  final String creator;
  final String pic;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool completed;
  final bool deleted;
  final Widget? expandControl;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final List<Widget> trailingChips;
  final int? progressPercent;
  final Widget? bottomLeading;

  @override
  Widget build(BuildContext context) {
    final ink = asanaInkIfDark(rowColor);
    final paintedName = ink == null ? nameStyle : nameStyle?.copyWith(color: ink);
    final paintedValue = ink == null
        ? valueStyle
        : valueStyle?.copyWith(color: ink);
    final metaLine = 'Cr: $creator · PIC: $pic';
    final dateLine =
        'Start: ${_formatDueDate(startDate)} · Due: ${_formatDueDate(dueDate)}';
    final card = InkWell(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AsanaRowTypeLetter(
                            letter: letter,
                            completed: completed,
                            deleted: deleted,
                            status: status,
                          ),
                          if (expandControl != null) ...[
                            const SizedBox(height: 2),
                            expandControl!,
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AsanaNameWithFreshness(
                          name: name,
                          style: paintedName,
                          createdAt: createdAt,
                          updatedAt: updatedAt,
                          maxLines: 2,
                        ),
                        if (progressPercent != null)
                          _ProjectProgressPercent(
                            percent: progressPercent!,
                            color: ink,
                          ),
                        const SizedBox(height: 5),
                        Text(
                          metaLine,
                          style: paintedValue,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Text(
                              dateLine,
                              style: paintedValue,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            AsanaStatusChip(status: status),
                            ...trailingChips,
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (bottomLeading != null) ...[
                const SizedBox(height: 4),
                bottomLeading!,
              ],
            ],
          ),
        ),
    );
    final check = onLongPress;
    return Material(
      color: rowColor,
      child: check == null
          ? card
          : RawGestureDetector(
              gestures: <Type, GestureRecognizerFactory>{
                LongPressGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      LongPressGestureRecognizer
                    >(
                      () => LongPressGestureRecognizer(
                        duration: const Duration(milliseconds: 200),
                      ),
                      (instance) => instance.onLongPress = check,
                    ),
              },
              child: card,
            ),
    );
  }
}

class _ProjectMobileRow extends StatelessWidget {
  const _ProjectMobileRow({
    required this.tableColors,
    required this.hierarchyColors,
    required this.project,
    required this.progressPercent,
    required this.appState,
    required this.tasks,
    required this.subtasksByTask,
    required this.expandedTaskIds,
    required this.expandedSubprojectIds,
    required this.loadingSubtaskTaskIds,
    required this.expanded,
    required this.onToggleExpand,
    required this.onToggleTaskExpand,
    required this.onToggleSubprojectExpand,
    this.onTap,
    this.onOpenTask,
    this.onOpenSubtask,
    this.onOpenSubproject,
    this.selectionWidth = 0,
    this.projectSelected = false,
    this.onProjectSelected,
    this.selectedSubprojectIds = const {},
    this.onSubprojectSelected,
    this.selectedTaskIds = const {},
    this.onTaskSelected,
    this.selectedSubtaskIds = const {},
    this.onSubtaskSelected,
    this.forceProjectChecks = false,
    this.forceSubprojectChecks = false,
    this.forceTaskChecks = false,
  });

  final AsanaTableColors tableColors;
  final AsanaHierarchyRowColors hierarchyColors;
  final ProjectRecord project;
  final int progressPercent;
  final AppState appState;
  final List<Task> tasks;
  final Map<String, List<SingularSubtask>> subtasksByTask;
  final Set<String> expandedTaskIds;
  final Set<String> expandedSubprojectIds;
  final Set<String> loadingSubtaskTaskIds;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final void Function(Task task) onToggleTaskExpand;
  final void Function(String subprojectId) onToggleSubprojectExpand;
  final VoidCallback? onTap;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;
  final void Function(String subprojectId, String projectId)? onOpenSubproject;
  final double selectionWidth;
  final bool projectSelected;
  final ValueChanged<bool>? onProjectSelected;
  final Set<String> selectedSubprojectIds;
  final void Function(String subprojectId, bool selected)? onSubprojectSelected;
  final Set<String> selectedTaskIds;
  final void Function(String taskId, bool selected)? onTaskSelected;
  final Set<String> selectedSubtaskIds;
  final void Function(String subtaskId, bool selected)? onSubtaskSelected;
  final bool forceProjectChecks;
  final bool forceSubprojectChecks;
  final bool forceTaskChecks;

  bool get _completed => project.status.trim() == 'Completed';
  bool get _deleted {
    final s = project.status.trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  @override
  Widget build(BuildContext context) {
    final name = project.name.trim().isEmpty
        ? '(Unnamed project)'
        : project.name.trim();
    final nameStyle = asanaTableRowNameStyle(context, completed: _completed);
    final valueStyle = asanaTableRowValueStyle(context, completed: _completed);
    final hasChildren = tasks.isNotEmpty ||
        AsanaProjectFilter.visibleSubprojectsForProject(
          appState,
          project.id,
        ).isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProjectMobileBlock(
          rowColor: hierarchyColors.project,
          letter: 'P',
          status: project.isPaused ? 'Paused' : project.status,
          name: name,
          nameStyle: nameStyle,
          valueStyle: valueStyle,
          creator: AsanaProjectFilter.creatorLine(project, appState),
          pic: AsanaProjectFilter.picLine(project, appState),
          startDate: project.startDate,
          dueDate: project.endDate,
          createdAt: project.createDate,
          updatedAt: project.updateDate,
          completed: _completed,
          deleted: _deleted,
          progressPercent: progressPercent,
          onTap: onTap,
          onLongPress: _InactiveSelection.toggle(
            context: context,
            itemId: project.id,
            selected: projectSelected,
            onSelected: onProjectSelected,
          ),
          bottomLeading: onProjectSelected == null
              ? null
              : _ProjectSelectionBox(
                  width: selectionWidth,
                  selected: projectSelected,
                  forceVisible: forceProjectChecks,
                  itemId: project.id,
                  onChanged: onProjectSelected!,
                ),
          expandControl: hasChildren
              ? _ProjectMobileExpandChevron(
                  expanded: expanded,
                  onPressed: onToggleExpand,
                  color: asanaInkIfDark(hierarchyColors.project),
                )
              : null,
        ),
        if (tasks.isNotEmpty ||
            AsanaProjectFilter.visibleSubprojectsForProject(
              appState,
              project.id,
            ).isNotEmpty)
          _AnimatedProjectTaskExpansion(
            expanded: expanded,
            child: ColoredBox(
              color: hierarchyColors.subtask,
              child: _ProjectMobileTaskList(
                projectId: project.id,
                tasks: tasks,
                subtasksByTask: subtasksByTask,
                expandedTaskIds: expandedTaskIds,
                expandedSubprojectIds: expandedSubprojectIds,
                loadingSubtaskTaskIds: loadingSubtaskTaskIds,
                tableColors: tableColors,
                hierarchyColors: hierarchyColors,
                appState: appState,
                onToggleTaskExpand: onToggleTaskExpand,
                onToggleSubprojectExpand: onToggleSubprojectExpand,
                onOpenTask: onOpenTask,
                onOpenSubtask: onOpenSubtask,
                onOpenSubproject: onOpenSubproject,
                selectionWidth: selectionWidth,
                selectedSubprojectIds: selectedSubprojectIds,
                onSubprojectSelected: onSubprojectSelected,
                selectedTaskIds: selectedTaskIds,
                onTaskSelected: onTaskSelected,
                selectedSubtaskIds: selectedSubtaskIds,
                onSubtaskSelected: onSubtaskSelected,
                forceSubprojectChecks: forceSubprojectChecks,
                forceTaskChecks: forceTaskChecks,
              ),
            ),
          ),
      ],
    );
  }
}

class _ProjectMobileExpandChevron extends StatelessWidget {
  const _ProjectMobileExpandChevron({
    required this.expanded,
    required this.onPressed,
    this.color,
  });

  final bool expanded;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        child: Icon(
          expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 20,
          color: color ?? kAsanaTextSecondary,
        ),
      ),
    );
  }
}

class _ProjectMobileTaskList extends StatelessWidget {
  const _ProjectMobileTaskList({
    required this.projectId,
    required this.tasks,
    required this.subtasksByTask,
    required this.expandedTaskIds,
    required this.expandedSubprojectIds,
    required this.loadingSubtaskTaskIds,
    required this.tableColors,
    required this.hierarchyColors,
    required this.appState,
    required this.onToggleTaskExpand,
    required this.onToggleSubprojectExpand,
    this.onOpenTask,
    this.onOpenSubtask,
    this.onOpenSubproject,
    this.selectionWidth = 0,
    this.selectedSubprojectIds = const {},
    this.onSubprojectSelected,
    this.selectedTaskIds = const {},
    this.onTaskSelected,
    this.selectedSubtaskIds = const {},
    this.onSubtaskSelected,
    this.forceSubprojectChecks = false,
    this.forceTaskChecks = false,
  });

  final String projectId;
  final List<Task> tasks;
  final Map<String, List<SingularSubtask>> subtasksByTask;
  final Set<String> expandedTaskIds;
  final Set<String> expandedSubprojectIds;
  final Set<String> loadingSubtaskTaskIds;
  final AsanaTableColors tableColors;
  final AsanaHierarchyRowColors hierarchyColors;
  final AppState appState;
  final void Function(Task task) onToggleTaskExpand;
  final void Function(String subprojectId) onToggleSubprojectExpand;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;
  final void Function(String subprojectId, String projectId)? onOpenSubproject;
  final double selectionWidth;
  final Set<String> selectedSubprojectIds;
  final void Function(String subprojectId, bool selected)? onSubprojectSelected;
  final Set<String> selectedTaskIds;
  final void Function(String taskId, bool selected)? onTaskSelected;
  final Set<String> selectedSubtaskIds;
  final void Function(String subtaskId, bool selected)? onSubtaskSelected;
  final bool forceSubprojectChecks;
  final bool forceTaskChecks;

  @override
  Widget build(BuildContext context) {
    final subprojects = AsanaProjectFilter.visibleSubprojectsForProject(
      appState,
      projectId,
    );
    final nestedTaskIds = <String>{};
    final children = <Widget>[];

    void addTask(Task task) {
      if (children.isNotEmpty) {
        children.add(Divider(height: 1, color: Colors.grey.shade300));
      }
      children.add(
        _ProjectMobileTaskRow(
          task: task,
          subtasks: subtasksByTask[task.id] ?? const <SingularSubtask>[],
          subtasksKnown: subtasksByTask.containsKey(task.id),
          expanded: expandedTaskIds.contains(task.id),
          loadingSubtasks: loadingSubtaskTaskIds.contains(task.id),
          tableColors: tableColors,
          hierarchyColors: hierarchyColors,
          appState: appState,
          onToggleExpand: () => onToggleTaskExpand(task),
          onTap: onOpenTask == null ? null : () => onOpenTask!(task.id),
          onOpenSubtask: onOpenSubtask,
          selectionWidth: selectionWidth,
          selected: selectedTaskIds.contains(task.id),
          forceSelectionVisible: forceTaskChecks,
          onSelected: onTaskSelected == null
              ? null
              : (checked) => onTaskSelected!(task.id, checked),
          selectedSubtaskIds: selectedSubtaskIds,
          onSubtaskSelected: onSubtaskSelected,
        ),
      );
    }

    for (final subproject in subprojects) {
      final childTasks = [
        for (final task in tasks)
          if (task.subprojectId?.trim() == subproject.id) task,
      ];
      nestedTaskIds.addAll(childTasks.map((t) => t.id));
      final expanded = expandedSubprojectIds.contains(subproject.id);
      final picLine = subproject.picStaffDisplayNames
          .where((n) => n.trim().isNotEmpty)
          .join(', ');
      if (children.isNotEmpty) {
        children.add(Divider(height: 1, color: Colors.grey.shade300));
      }
      children.add(
        _ProjectMobileBlock(
          rowColor: hierarchyColors.subproject,
          letter: 'SP',
          status: subproject.isPaused ? 'Paused' : subproject.status,
          name: subproject.name.trim().isEmpty
              ? '(Unnamed sub-project)'
              : subproject.name.trim(),
          nameStyle: asanaTableRowNameStyle(
            context,
            completed: subproject.isCompleted,
          ),
          valueStyle: asanaTableRowValueStyle(
            context,
            completed: subproject.isCompleted,
          ),
          creator: (subproject.createByDisplayName ?? '').trim().isEmpty
              ? '—'
              : subproject.createByDisplayName!.trim(),
          pic: picLine.isEmpty ? '—' : picLine,
          startDate: subproject.startDate,
          dueDate: subproject.endDate,
          createdAt: subproject.createDate,
          updatedAt: subproject.updateDate,
          completed: subproject.isCompleted,
          deleted: subproject.isDeleted,
          bottomLeading: onSubprojectSelected == null
              ? null
              : _ProjectSelectionBox(
                  width: selectionWidth,
                  selected: selectedSubprojectIds.contains(subproject.id),
                  forceVisible: forceSubprojectChecks,
                  itemId: subproject.id,
                  onChanged: (checked) =>
                      onSubprojectSelected!(subproject.id, checked),
                ),
          onTap: onOpenSubproject == null
              ? null
              : () => onOpenSubproject!(subproject.id, subproject.projectId),
          onLongPress: _InactiveSelection.toggle(
            context: context,
            itemId: subproject.id,
            selected: selectedSubprojectIds.contains(subproject.id),
            onSelected: onSubprojectSelected == null
                ? null
                : (checked) => onSubprojectSelected!(subproject.id, checked),
          ),
          expandControl: childTasks.isNotEmpty
              ? _ProjectMobileExpandChevron(
                  expanded: expanded,
                  onPressed: () => onToggleSubprojectExpand(subproject.id),
                  color: asanaInkIfDark(hierarchyColors.subproject),
                )
              : null,
        ),
      );
      if (expanded) {
        for (final task in childTasks) {
          addTask(task);
        }
      }
    }
    for (final task in tasks) {
      if (nestedTaskIds.contains(task.id)) continue;
      addTask(task);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _ProjectMobileTaskRow extends StatelessWidget {
  const _ProjectMobileTaskRow({
    required this.task,
    required this.subtasks,
    required this.subtasksKnown,
    required this.expanded,
    required this.loadingSubtasks,
    required this.tableColors,
    required this.hierarchyColors,
    required this.appState,
    required this.onToggleExpand,
    this.onTap,
    this.onOpenSubtask,
    this.selectionWidth = 0,
    this.selected = false,
    this.forceSelectionVisible = false,
    this.onSelected,
    this.selectedSubtaskIds = const {},
    this.onSubtaskSelected,
  });

  final Task task;
  final List<SingularSubtask> subtasks;
  final bool subtasksKnown;
  final bool expanded;
  final bool loadingSubtasks;
  final AsanaTableColors tableColors;
  final AsanaHierarchyRowColors hierarchyColors;
  final AppState appState;
  final VoidCallback onToggleExpand;
  final VoidCallback? onTap;
  final void Function(String subtaskId)? onOpenSubtask;
  final double selectionWidth;
  final bool selected;
  final bool forceSelectionVisible;
  final ValueChanged<bool>? onSelected;
  final Set<String> selectedSubtaskIds;
  final void Function(String subtaskId, bool selected)? onSubtaskSelected;

  @override
  Widget build(BuildContext context) {
    final completed = _taskCompleted(task);
    final status = AsanaTaskFilter.taskDisplayStatus(appState, task);
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: true,
    );
    final valueStyle = asanaTableRowValueStyle(context, completed: completed);
    final name = task.name.trim().isEmpty ? '(Unnamed task)' : task.name.trim();
    final hasSubtasks = subtasks.isNotEmpty;
    final showSubtaskControl = loadingSubtasks || hasSubtasks;
    final showSubtaskExpansion = loadingSubtasks || hasSubtasks;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProjectMobileBlock(
          rowColor: hierarchyColors.task,
          letter: 'T',
          status: status,
          name: name,
          nameStyle: nameStyle,
          valueStyle: valueStyle,
          creator: (task.createByStaffName ?? '').trim().isEmpty
              ? '—'
              : task.createByStaffName!.trim(),
          pic: _formatTaskPic(appState, task.pic),
          startDate: visibleScheduleDate(
            task.startDate,
            task.commencementStatus,
          ),
          dueDate: visibleScheduleDate(
            task.endDate,
            task.commencementStatus,
          ),
          createdAt: task.createdAt,
          updatedAt: task.updateDate,
          completed: completed,
          deleted: _taskDeleted(task),
          onTap: onTap,
          onLongPress: _InactiveSelection.toggle(
            context: context,
            itemId: task.id,
            selected: selected,
            onSelected: onSelected,
          ),
          bottomLeading: onSelected == null
              ? null
              : _ProjectSelectionBox(
                  width: selectionWidth,
                  selected: selected,
                  forceVisible: forceSelectionVisible,
                  itemId: task.id,
                  onChanged: onSelected!,
                ),
          expandControl: showSubtaskControl
              ? (loadingSubtasks
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    : _ProjectMobileExpandChevron(
                        expanded: expanded,
                        onPressed: onToggleExpand,
                        color: asanaInkIfDark(hierarchyColors.task),
                      ))
              : null,
          trailingChips: [
            AsanaSubmissionChip(submission: task.submission),
          ],
        ),
        if (showSubtaskExpansion)
          _AnimatedProjectTaskExpansion(
            expanded: expanded,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loadingSubtasks)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 8, 14, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Loading sub-tasks...'),
                    ),
                  )
                else
                  for (var i = 0; i < subtasks.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: Colors.grey.shade300),
                    _ProjectMobileSubtaskRow(
                      parentTask: task,
                      subtask: subtasks[i],
                      tableColors: tableColors,
                      hierarchyColors: hierarchyColors,
                      appState: appState,
                      onTap: onOpenSubtask == null
                          ? null
                          : () => onOpenSubtask!(subtasks[i].id),
                      selectionWidth: selectionWidth,
                      selected: selectedSubtaskIds.contains(subtasks[i].id),
                      onSelected: onSubtaskSelected == null
                          ? null
                          : (checked) =>
                                onSubtaskSelected!(subtasks[i].id, checked),
                    ),
                  ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ProjectMobileSubtaskRow extends StatelessWidget {
  const _ProjectMobileSubtaskRow({
    required this.parentTask,
    required this.subtask,
    required this.tableColors,
    required this.hierarchyColors,
    required this.appState,
    this.onTap,
    this.selectionWidth = 0,
    this.selected = false,
    this.onSelected,
  });

  final Task parentTask;
  final SingularSubtask subtask;
  final AsanaTableColors tableColors;
  final AsanaHierarchyRowColors hierarchyColors;
  final AppState appState;
  final VoidCallback? onTap;
  final double selectionWidth;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final completed = _subtaskCompleted(subtask);
    final status = AsanaTaskFilter.subtaskDisplayStatus(
      appState,
      parentTask,
      subtask,
    );
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: true,
    );
    final valueStyle = asanaTableRowValueStyle(context, completed: completed);
    final name = subtask.subtaskName.trim().isEmpty
        ? '(Unnamed sub-task)'
        : subtask.subtaskName.trim();

    return _ProjectMobileBlock(
      rowColor: hierarchyColors.subtask,
      letter: 'ST',
      status: status,
      name: name,
      nameStyle: nameStyle,
      valueStyle: valueStyle,
      creator: (subtask.createByStaffName ?? '').trim().isEmpty
          ? '—'
          : subtask.createByStaffName!.trim(),
      pic: _formatTaskPic(appState, subtask.pic),
      bottomLeading: onSelected == null
          ? null
          : _ProjectSelectionBox(
              width: selectionWidth,
              selected: selected,
              itemId: subtask.id,
              onChanged: onSelected!,
            ),
      startDate: visibleScheduleDate(
        subtask.startDate,
        subtask.commencementStatus,
      ),
      dueDate: visibleScheduleDate(
        subtask.dueDate,
        subtask.commencementStatus,
      ),
      createdAt: subtask.createDate,
      updatedAt: subtask.updateDate,
      completed: completed,
      deleted: subtask.isDeleted,
      onTap: onTap,
      onLongPress: _InactiveSelection.toggle(
        context: context,
        itemId: subtask.id,
        selected: selected,
        onSelected: onSelected,
      ),
      trailingChips: [
        AsanaSubmissionChip(submission: subtask.submission),
      ],
    );
  }
}

String _formatDueDate(DateTime? d) {
  if (d == null) return '—';
  final today = HkTime.todayDateOnlyHk();
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  return HkTime.formatInstantAsHk(d, 'MMM d');
}

String _formatUpdatedDate(DateTime? d) {
  if (d == null) return '—';
  return HkTime.formatInstantAsHk(d, 'MMM d, HH:mm');
}

bool _taskCompleted(Task task) {
  final status = task.dbStatus?.trim().toLowerCase() ?? '';
  return status == 'completed' || status == 'complete';
}

bool _taskDeleted(Task task) {
  final status = task.dbStatus?.trim().toLowerCase() ?? '';
  return status == 'deleted' || status == 'delete';
}

bool _subtaskCompleted(SingularSubtask subtask) {
  final status = subtask.status.trim().toLowerCase();
  return status == 'completed' || status == 'complete';
}

String _formatTaskPic(AppState state, String? key) {
  final id = key?.trim();
  if (id == null || id.isEmpty) return '—';
  return state.assigneeById(id)?.name.trim() ?? id;
}

String _formatTaskAssignees(AppState state, Iterable<String> ids) {
  final names = ids
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .map((id) => state.assigneeById(id)?.name.trim() ?? id)
      .where((name) => name.isNotEmpty)
      .toList();
  return names.isEmpty ? '—' : names.join(', ');
}

class _ProjectStructureButton extends StatelessWidget {
  const _ProjectStructureButton({
    required this.label,
    required this.palette,
    required this.onPressed,
  });

  final String label;
  final AsanaLandingPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: asanaToolbarActionStyle(
        palette.accent,
        height: kAsanaShortToolbarActionHeight,
      ),
      child: Text(label),
    );
  }
}

class _ProjectSelectionBox extends StatefulWidget {
  const _ProjectSelectionBox({
    required this.width,
    required this.selected,
    required this.onChanged,
    this.forceVisible = false,
    this.itemId = '',
  });

  final double width;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final bool forceVisible;
  final String itemId;

  @override
  State<_ProjectSelectionBox> createState() => _ProjectSelectionBoxState();
}

class _ProjectSelectionBoxState extends State<_ProjectSelectionBox> {
  bool _hovering = false;

  void _toggle() {
    if (_InactiveSelection.contains(context, widget.itemId)) return;
    widget.onChanged(!widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final locked = _InactiveSelection.contains(context, widget.itemId);
    final visible = widget.selected || widget.forceVisible || _hovering;
    return MouseRegion(
      onEnter: locked ? null : (_) => setState(() => _hovering = true),
      onExit: locked ? null : (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: locked ? null : _toggle,
        child: SizedBox(
          width: widget.width,
          height: 32,
          child: Opacity(
            opacity: visible ? (locked ? 0.45 : 1) : 0,
            child: IgnorePointer(
              child: Checkbox(
                value: widget.selected,
                onChanged: locked ? null : (_) {},
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                checkColor: locked ? const Color(0xFF9E9E9E) : Colors.black,
                fillColor: const WidgetStatePropertyAll(Colors.white),
                side: BorderSide(
                  color: locked ? const Color(0xFFBDBDBD) : Colors.black,
                  width: 1.6,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}