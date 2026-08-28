import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/project_record.dart';
import '../../models/singular_subtask.dart';
import '../../models/task.dart';
import '../../services/database_service.dart';
import '../asana_landing_screen.dart';
import 'asana_filter_widgets.dart';
import 'asana_project_filter.dart';
import 'asana_task_filter.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

/// Read-only project -> task -> sub-task map for office work visualization.
class AsanaMapPanel extends StatefulWidget {
  const AsanaMapPanel({
    super.key,
    required this.palette,
    required this.searchQuery,
    this.refreshToken = 0,
    this.onOpenProject,
    this.onOpenTask,
    this.onOpenSubtask,
  });

  final AsanaLandingPalette palette;
  final String searchQuery;
  final int refreshToken;
  final void Function(String projectId)? onOpenProject;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;

  @override
  State<AsanaMapPanel> createState() => _AsanaMapPanelState();
}

class _AsanaMapPanelState extends State<AsanaMapPanel> {
  final Map<String, List<SingularSubtask>> _subtasksByTask = {};
  final Set<String> _expandedProjectIds = {};
  final Set<String> _expandedTaskIds = {};
  final Set<String> _projectCreatorTeamIds = {};
  final Set<String> _projectPicIds = {};
  final Set<String> _projectStatuses = {};
  final Set<String> _taskCreatorTeamIds = {};
  final Set<String> _taskPicIds = {};
  final Set<String> _taskStatuses = {};
  final Set<String> _subtaskStatuses = {};
  String _sortKey = 'due_asc';
  String _dataSig = '';
  int _loadGeneration = 0;
  bool _loadingSubtasks = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshSubtasks();
    });
  }

  @override
  void didUpdateWidget(covariant AsanaMapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.searchQuery != widget.searchQuery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshSubtasks();
      });
    }
  }

  Future<void> _refreshSubtasks() async {
    final tasks = _visibleTasks(context.read<AppState>());
    final ids = tasks.map((t) => t.id.trim()).where((id) => id.isNotEmpty);
    final gen = ++_loadGeneration;
    if (mounted) setState(() => _loadingSubtasks = true);
    try {
      final grouped =
          await DatabaseService.fetchSubtasksGroupedForLandingPrefetch(
            ids.toList(),
          );
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _subtasksByTask
          ..clear()
          ..addAll(grouped.map((k, v) => MapEntry(k, _sortedSubtasks(v))));
        _loadingSubtasks = false;
      });
    } catch (_) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() => _loadingSubtasks = false);
    }
  }

  List<Task> _visibleTasks(AppState state) {
    final tasks = state.tasksForTeams({}).where((task) {
      if (!task.isSingularTableRow) return false;
      final status = task.dbStatus?.trim().toLowerCase() ?? '';
      return status != 'deleted' && status != 'delete';
    }).toList();
    tasks.sort(_compareTasks);
    return tasks;
  }

  List<ProjectRecord> _visibleProjects(AppState state) {
    final filters = AsanaProjectFilterState();
    return AsanaProjectFilter.apply(state, filters, searchQuery: '');
  }

  List<SingularSubtask> _sortedSubtasks(List<SingularSubtask> subtasks) {
    final list = subtasks.where((s) => !s.isDeleted).toList();
    list.sort(
      (a, b) =>
          a.subtaskName.toLowerCase().compareTo(b.subtaskName.toLowerCase()),
    );
    return list;
  }

  List<_ProjectMapNode> _buildNodes(AppState state) {
    final projects = _visibleProjects(state).where((p) {
      final status = p.status.trim().toLowerCase();
      return status != 'deleted' && status != 'delete';
    }).toList()..sort(_compareProjects);
    final tasksByProject = <String, List<Task>>{};
    for (final task in _visibleTasks(state)) {
      final projectId = task.projectId?.trim();
      if (projectId == null || projectId.isEmpty) continue;
      tasksByProject.putIfAbsent(projectId, () => []).add(task);
    }

    final query = widget.searchQuery.trim().toLowerCase();
    final nodes = <_ProjectMapNode>[];
    for (final project in projects) {
      final tasks = tasksByProject[project.id] ?? const <Task>[];
      final projectMatches =
          _matches(project.name, query) ||
          _matches(_projectPicLabel(project), query) ||
          _matches(project.status, query);
      final projectPassesFilters = _passesProjectFilters(state, project);
      if (!projectPassesFilters) continue;
      final projectOwnMatches =
          projectPassesFilters && _passesSearch(projectMatches, query);
      final taskNodes = <_TaskMapNode>[];
      for (final task in tasks) {
        final subtasks = _subtasksByTask[task.id] ?? const <SingularSubtask>[];
        final taskStatus = AsanaTaskFilter.taskDisplayStatus(state, task);
        final taskPic = _staffName(state, task.pic);
        final taskMatches =
            _matches(task.name, query) ||
            _matches(taskPic, query) ||
            _matches(taskStatus, query);
        final taskOwnMatches =
            _passesTaskFilters(state, task, taskStatus) &&
            _passesSearch(taskMatches, query);
        final subtaskNodes = <SingularSubtask>[];
        for (final subtask in subtasks) {
          final subStatus = AsanaTaskFilter.subtaskDisplayStatus(
            state,
            task,
            subtask,
          );
          final subPic = _staffName(state, subtask.pic);
          final subMatches =
              _matches(subtask.subtaskName, query) ||
              _matches(subPic, query) ||
              _matches(subStatus, query);
          final subOwnMatches =
              (_subtaskStatuses.isNotEmpty || query.isNotEmpty) &&
              _passesSubtaskFilters(subStatus) &&
              _passesSearch(subMatches, query);
          if (subOwnMatches ||
              (projectOwnMatches && !_hasTaskOrSubtaskFilters) ||
              (taskOwnMatches && _subtaskStatuses.isEmpty)) {
            subtaskNodes.add(subtask);
          }
        }
        if (taskOwnMatches ||
            subtaskNodes.isNotEmpty ||
            (projectOwnMatches && !_hasTaskOrSubtaskFilters)) {
          taskNodes.add(_TaskMapNode(task: task, subtasks: subtaskNodes));
        }
      }
      if (projectOwnMatches || taskNodes.isNotEmpty) {
        nodes.add(_ProjectMapNode(project: project, tasks: taskNodes));
      }
    }
    for (final node in nodes) {
      node.tasks.sort((a, b) => _compareTaskNodes(state, a, b));
      for (final taskNode in node.tasks) {
        taskNode.subtasks.sort(
          (a, b) => _compareSubtasks(state, taskNode.task, a, b),
        );
      }
    }
    return nodes;
  }

  List<_TaskMapNode> _buildStandaloneTaskNodes(AppState state) {
    if (_hasProjectFilters) return const [];
    final query = widget.searchQuery.trim().toLowerCase();
    final nodes = <_TaskMapNode>[];
    for (final task in _visibleTasks(state)) {
      final projectId = task.projectId?.trim();
      if (projectId != null && projectId.isNotEmpty) continue;
      final subtasks = _subtasksByTask[task.id] ?? const <SingularSubtask>[];
      final taskStatus = AsanaTaskFilter.taskDisplayStatus(state, task);
      final taskPic = _staffName(state, task.pic);
      final taskMatches =
          _matches(task.name, query) ||
          _matches(taskPic, query) ||
          _matches(taskStatus, query);
      final taskOwnMatches =
          _passesTaskFilters(state, task, taskStatus) &&
          _passesSearch(taskMatches, query);
      final subtaskNodes = <SingularSubtask>[];
      for (final subtask in subtasks) {
        final subStatus = AsanaTaskFilter.subtaskDisplayStatus(
          state,
          task,
          subtask,
        );
        final subPic = _staffName(state, subtask.pic);
        final subMatches =
            _matches(subtask.subtaskName, query) ||
            _matches(subPic, query) ||
            _matches(subStatus, query);
        final subOwnMatches =
            (_subtaskStatuses.isNotEmpty || query.isNotEmpty) &&
            _passesSubtaskFilters(subStatus) &&
            _passesSearch(subMatches, query);
        if (subOwnMatches || (taskOwnMatches && _subtaskStatuses.isEmpty)) {
          subtaskNodes.add(subtask);
        }
      }
      if (taskOwnMatches || subtaskNodes.isNotEmpty) {
        subtaskNodes.sort((a, b) => _compareSubtasks(state, task, a, b));
        nodes.add(_TaskMapNode(task: task, subtasks: subtaskNodes));
      }
    }
    nodes.sort((a, b) => _compareTaskNodes(state, a, b));
    return nodes;
  }

  bool get _hasProjectFilters =>
      _projectCreatorTeamIds.isNotEmpty ||
      _projectPicIds.isNotEmpty ||
      _projectStatuses.isNotEmpty;

  bool get _hasTaskOrSubtaskFilters =>
      _taskCreatorTeamIds.isNotEmpty ||
      _taskPicIds.isNotEmpty ||
      _taskStatuses.isNotEmpty ||
      _subtaskStatuses.isNotEmpty;

  bool _passesSearch(bool matches, String query) => query.isEmpty || matches;

  bool _passesProjectFilters(AppState state, ProjectRecord project) {
    final projectStatus = project.isPaused ? 'Paused' : project.status;
    return _passesTeamFilter(
          state,
          project.createByStaffUuid,
          _projectCreatorTeamIds,
        ) &&
        _passesStaffFilter(project.picStaffUuids, _projectPicIds) &&
        _passesStatusFilter(projectStatus, _projectStatuses);
  }

  bool _passesTaskFilters(AppState state, Task task, String taskStatus) {
    return _passesTeamFilter(
          state,
          task.createByAssigneeKey,
          _taskCreatorTeamIds,
        ) &&
        _passesStaffFilter([task.pic], _taskPicIds) &&
        _passesStatusFilter(taskStatus, _taskStatuses);
  }

  bool _passesSubtaskFilters(String status) {
    return _passesStatusFilter(status, _subtaskStatuses);
  }

  bool _passesTeamFilter(
    AppState state,
    String? staffKey,
    Set<String> selectedTeamIds,
  ) {
    if (selectedTeamIds.isEmpty) return true;
    final teamId = state.teamIdForStaffKey(staffKey);
    return teamId != null && selectedTeamIds.contains(teamId);
  }

  bool _passesStaffFilter(Iterable<String?> ids, Set<String> selectedIds) {
    if (selectedIds.isEmpty) return true;
    return ids.any((id) {
      final key = id?.trim();
      return key != null && key.isNotEmpty && selectedIds.contains(key);
    });
  }

  bool _passesStatusFilter(String status, Set<String> selectedStatuses) {
    if (selectedStatuses.isEmpty) return true;
    return selectedStatuses.contains(_statusKey(status));
  }

  String _statusKey(String status) => status.trim().toLowerCase();

  bool _matches(String? value, String query) {
    if (query.isEmpty) return true;
    return (value ?? '').toLowerCase().contains(query);
  }

  int _compareText(String a, String b) {
    final cmp = a.toLowerCase().compareTo(b.toLowerCase());
    return _sortKey == 'name_desc' ? -cmp : cmp;
  }

  int _compareNullableDate(
    DateTime? a,
    DateTime? b, {
    required bool ascending,
  }) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final cmp = DateUtils.dateOnly(a).compareTo(DateUtils.dateOnly(b));
    return ascending ? cmp : -cmp;
  }

  int _compareProjects(ProjectRecord a, ProjectRecord b) {
    switch (_sortKey) {
      case 'due_desc':
        return _compareNullableDate(a.endDate, b.endDate, ascending: false);
      case 'created_desc':
        return _compareNullableDate(
          a.createDate,
          b.createDate,
          ascending: false,
        );
      case 'created_asc':
        return _compareNullableDate(
          a.createDate,
          b.createDate,
          ascending: true,
        );
      case 'name_desc':
        return _compareText(a.name, b.name);
      case 'name_asc':
        return _compareText(a.name, b.name);
      case 'due_asc':
      default:
        return _compareNullableDate(a.endDate, b.endDate, ascending: true);
    }
  }

  int _compareTasks(Task a, Task b) {
    switch (_sortKey) {
      case 'due_desc':
        return _compareNullableDate(a.endDate, b.endDate, ascending: false);
      case 'created_desc':
        return _compareNullableDate(a.createdAt, b.createdAt, ascending: false);
      case 'created_asc':
        return _compareNullableDate(a.createdAt, b.createdAt, ascending: true);
      case 'name_desc':
        return _compareText(a.name, b.name);
      case 'name_asc':
        return _compareText(a.name, b.name);
      case 'due_asc':
      default:
        return _compareNullableDate(a.endDate, b.endDate, ascending: true);
    }
  }

  int _compareTaskNodes(AppState state, _TaskMapNode a, _TaskMapNode b) {
    return _compareTasks(a.task, b.task);
  }

  int _compareSubtasks(
    AppState state,
    Task task,
    SingularSubtask a,
    SingularSubtask b,
  ) {
    switch (_sortKey) {
      case 'due_desc':
        return _compareNullableDate(a.dueDate, b.dueDate, ascending: false);
      case 'created_desc':
        return _compareNullableDate(
          a.createDate,
          b.createDate,
          ascending: false,
        );
      case 'created_asc':
        return _compareNullableDate(
          a.createDate,
          b.createDate,
          ascending: true,
        );
      case 'name_desc':
        return _compareText(a.subtaskName, b.subtaskName);
      case 'name_asc':
        return _compareText(a.subtaskName, b.subtaskName);
      case 'due_asc':
      default:
        return _compareNullableDate(a.dueDate, b.dueDate, ascending: true);
    }
  }

  String _projectPicLabel(ProjectRecord project) {
    final names = project.picStaffDisplayNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isNotEmpty) return names.join(', ');
    return project.picStaffUuids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .join(', ');
  }

  String _staffName(AppState state, String? id) {
    final key = id?.trim();
    if (key == null || key.isEmpty) return '';
    return state.assigneeById(key)?.name.trim() ?? key;
  }

  String _filterLabel(Set<String> values, String Function(String) labelFor) {
    if (values.isEmpty) return 'All';
    if (values.length == 1) return labelFor(values.first);
    return '${values.length} selected';
  }

  List<AsanaFilterCheckboxOption> _projectOptions(List<_ProjectMapNode> nodes) {
    return [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      for (final node in nodes)
        AsanaFilterCheckboxOption(
          key: node.project.id,
          label: node.project.name.trim().isEmpty
              ? 'Untitled project'
              : node.project.name.trim(),
        ),
    ];
  }

  List<AsanaFilterCheckboxOption> _picOptions(
    AppState state,
    List<_ProjectMapNode> nodes,
  ) {
    final names = <String, String>{};
    for (final node in nodes) {
      for (var i = 0; i < node.project.picStaffUuids.length; i++) {
        final id = node.project.picStaffUuids[i].trim();
        if (id.isEmpty) continue;
        final display = i < node.project.picStaffDisplayNames.length
            ? node.project.picStaffDisplayNames[i].trim()
            : '';
        names[id] = display.isEmpty ? id : display;
      }
      for (final taskNode in node.tasks) {
        final taskPic = taskNode.task.pic?.trim();
        if (taskPic != null && taskPic.isNotEmpty) {
          names[taskPic] = _staffName(state, taskPic);
        }
        for (final subtask in taskNode.subtasks) {
          final subPic = subtask.pic?.trim();
          if (subPic != null && subPic.isNotEmpty) {
            names[subPic] = _staffName(state, subPic);
          }
        }
      }
    }
    final sorted = names.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      for (final entry in sorted)
        AsanaFilterCheckboxOption(key: entry.key, label: entry.value),
    ];
  }

  List<AsanaFilterCheckboxOption> _statusOptions(
    AppState state,
    List<_ProjectMapNode> nodes,
  ) {
    final labels = <String, String>{};
    void add(String status) {
      final key = _statusKey(status);
      if (key.isEmpty) return;
      labels[key] = AsanaStatusChip.statusStyle(status).$1;
    }

    for (final node in nodes) {
      add(node.project.isPaused ? 'Paused' : node.project.status);
      for (final taskNode in node.tasks) {
        add(AsanaTaskFilter.taskDisplayStatus(state, taskNode.task));
        for (final subtask in taskNode.subtasks) {
          add(
            AsanaTaskFilter.subtaskDisplayStatus(state, taskNode.task, subtask),
          );
        }
      }
    }
    final sorted = labels.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      for (final entry in sorted)
        AsanaFilterCheckboxOption(key: entry.key, label: entry.value),
    ];
  }

  List<AsanaFilterCheckboxOption> _teamOptions(
    AppState state,
    Iterable<String?> staffKeys,
  ) {
    final teams = <String, String>{};
    for (final staffKey in staffKeys) {
      final teamId = state.teamIdForStaffKey(staffKey);
      if (teamId == null || teamId.trim().isEmpty) continue;
      teams[teamId] = state.teamNameById(teamId);
    }
    final sorted = teams.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      for (final entry in sorted)
        AsanaFilterCheckboxOption(key: entry.key, label: entry.value),
    ];
  }

  List<AsanaFilterCheckboxOption> _staffOptions(
    AppState state,
    Iterable<String?> staffKeys, {
    Map<String, String> displayNames = const {},
  }) {
    final names = <String, String>{};
    for (final staffKey in staffKeys) {
      final id = staffKey?.trim();
      if (id == null || id.isEmpty) continue;
      final display = displayNames[id]?.trim();
      names[id] = display != null && display.isNotEmpty
          ? display
          : _staffName(state, id);
    }
    final sorted = names.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      for (final entry in sorted)
        AsanaFilterCheckboxOption(key: entry.key, label: entry.value),
    ];
  }

  List<AsanaFilterCheckboxOption> _statusOptionsFrom(
    Iterable<String> statuses,
  ) {
    final labels = <String, String>{};
    for (final status in statuses) {
      final key = _statusKey(status);
      if (key.isEmpty) continue;
      labels[key] = AsanaStatusChip.statusStyle(status).$1;
    }
    final sorted = labels.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      for (final entry in sorted)
        AsanaFilterCheckboxOption(key: entry.key, label: entry.value),
    ];
  }

  Map<String, String> _projectPicDisplayNames(AppState state) {
    final names = <String, String>{};
    for (final project in _visibleProjects(state)) {
      for (var i = 0; i < project.picStaffUuids.length; i++) {
        final id = project.picStaffUuids[i].trim();
        if (id.isEmpty) continue;
        final display = i < project.picStaffDisplayNames.length
            ? project.picStaffDisplayNames[i].trim()
            : '';
        if (display.isNotEmpty) names[id] = display;
      }
    }
    return names;
  }

  Iterable<String?> _projectCreatorKeys(AppState state) sync* {
    for (final project in _visibleProjects(state)) {
      yield project.createByStaffUuid;
    }
  }

  Iterable<String?> _projectPicKeys(AppState state) sync* {
    for (final project in _visibleProjects(state)) {
      for (final id in project.picStaffUuids) {
        yield id;
      }
    }
  }

  Iterable<String> _projectStatusValues(AppState state) sync* {
    for (final project in _visibleProjects(state)) {
      final status = project.status.trim().toLowerCase();
      if (status == 'deleted' || status == 'delete') continue;
      yield project.isPaused ? 'Paused' : project.status;
    }
  }

  Iterable<String?> _taskCreatorKeys(AppState state) sync* {
    for (final task in _visibleTasks(state)) {
      yield task.createByAssigneeKey;
    }
  }

  Iterable<String?> _taskPicKeys(AppState state) sync* {
    for (final task in _visibleTasks(state)) {
      yield task.pic;
    }
  }

  Iterable<String> _taskStatusValues(AppState state) sync* {
    for (final task in _visibleTasks(state)) {
      yield AsanaTaskFilter.taskDisplayStatus(state, task);
    }
  }

  Iterable<String> _subtaskStatusValues(AppState state) sync* {
    for (final task in _visibleTasks(state)) {
      for (final subtask
          in _subtasksByTask[task.id] ?? const <SingularSubtask>[]) {
        yield AsanaTaskFilter.subtaskDisplayStatus(state, task, subtask);
      }
    }
  }

  String _statusLabelFor(String key) => AsanaStatusChip.statusStyle(key).$1;

  String _sortLabel() {
    switch (_sortKey) {
      case 'due_desc':
        return 'Due date ↓';
      case 'created_desc':
        return 'Created ↓';
      case 'created_asc':
        return 'Created ↑';
      case 'name_asc':
        return 'Name A-Z';
      case 'name_desc':
        return 'Name Z-A';
      case 'due_asc':
      default:
        return 'Due date ↑';
    }
  }

  Future<void> _showSortMenu(BuildContext buttonContext) async {
    final selected = await showMenu<String>(
      context: buttonContext,
      position: _menuPosition(buttonContext),
      color: Theme.of(buttonContext).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      items: const [
        PopupMenuItem(value: 'due_asc', child: Text('Due date ↑')),
        PopupMenuItem(value: 'due_desc', child: Text('Due date ↓')),
        PopupMenuItem(value: 'created_desc', child: Text('Created ↓')),
        PopupMenuItem(value: 'created_asc', child: Text('Created ↑')),
        PopupMenuItem(value: 'name_asc', child: Text('Name A-Z')),
        PopupMenuItem(value: 'name_desc', child: Text('Name Z-A')),
      ],
    );
    if (selected == null || !mounted) return;
    setState(() => _sortKey = selected);
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

  Future<void> _showFilterMenu({
    required BuildContext anchorContext,
    required List<AsanaFilterCheckboxOption> options,
    required Set<String> selected,
    required void Function(Set<String>) apply,
  }) async {
    final result = await showAsanaCheckboxFilterPanel(
      anchorContext: anchorContext,
      options: options,
      initialSelection: selected,
    );
    if (result == null || !mounted) return;
    setState(() {
      apply(result.contains('__all__') ? <String>{} : result);
    });
  }

  void _syncDefaultExpansion(List<_ProjectMapNode> nodes) {
    if (_expandedProjectIds.isNotEmpty || _expandedTaskIds.isNotEmpty) return;
    for (final node in nodes) {
      _expandedProjectIds.add(node.project.id);
      for (final taskNode in node.tasks) {
        _expandedTaskIds.add(taskNode.task.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sig = [
      widget.refreshToken,
      state.projects
          .map((p) => '${p.id}:${p.status}:${p.pauseStatus}')
          .join('|'),
      state.tasks.map((t) => '${t.id}:${t.projectId}:${t.dbStatus}').join('|'),
    ].join('||');
    if (sig != _dataSig) {
      _dataSig = sig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshSubtasks();
      });
    }

    final nodes = _buildNodes(state);
    final standaloneTasks = _buildStandaloneTaskNodes(state);
    _syncDefaultExpansion(nodes);
    final theme = Theme.of(context);

    return ColoredBox(
      color: widget.palette.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Project, Task and Sub-task Map',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: kAsanaTextPrimary,
                      height: 1.25,
                    ),
                  ),
                ),
                if (_loadingSubtasks)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          AsanaPanelFilterToolbar(
            palette: widget.palette,
            createLabel: '',
            onCreate: null,
            onClearAll: () {
              setState(() {
                _projectCreatorTeamIds.clear();
                _projectPicIds.clear();
                _projectStatuses.clear();
                _taskCreatorTeamIds.clear();
                _taskPicIds.clear();
                _taskStatuses.clear();
                _subtaskStatuses.clear();
                _sortKey = 'due_asc';
              });
            },
            filterChildren: [
              AsanaFilterDropdown(
                title: 'Project Team',
                value: _filterLabel(_projectCreatorTeamIds, state.teamNameById),
                buttonWidth: 144,
                onPressed: (anchor) => _showFilterMenu(
                  anchorContext: anchor,
                  options: _teamOptions(state, _projectCreatorKeys(state)),
                  selected: _projectCreatorTeamIds,
                  apply: (value) => _projectCreatorTeamIds
                    ..clear()
                    ..addAll(value),
                ),
              ),
              AsanaFilterDropdown(
                title: 'Project PIC',
                value: _filterLabel(_projectPicIds, (id) {
                  final names = _projectPicDisplayNames(state);
                  return names[id] ?? _staffName(state, id);
                }),
                buttonWidth: 140,
                onPressed: (anchor) => _showFilterMenu(
                  anchorContext: anchor,
                  options: _staffOptions(
                    state,
                    _projectPicKeys(state),
                    displayNames: _projectPicDisplayNames(state),
                  ),
                  selected: _projectPicIds,
                  apply: (value) => _projectPicIds
                    ..clear()
                    ..addAll(value),
                ),
              ),
              AsanaFilterDropdown(
                title: 'Project Status',
                value: _filterLabel(_projectStatuses, _statusLabelFor),
                buttonWidth: 148,
                onPressed: (anchor) => _showFilterMenu(
                  anchorContext: anchor,
                  options: _statusOptionsFrom(_projectStatusValues(state)),
                  selected: _projectStatuses,
                  apply: (value) => _projectStatuses
                    ..clear()
                    ..addAll(value),
                ),
              ),
              AsanaFilterDropdown(
                title: 'Task Team',
                value: _filterLabel(_taskCreatorTeamIds, state.teamNameById),
                buttonWidth: 132,
                onPressed: (anchor) => _showFilterMenu(
                  anchorContext: anchor,
                  options: _teamOptions(state, _taskCreatorKeys(state)),
                  selected: _taskCreatorTeamIds,
                  apply: (value) => _taskCreatorTeamIds
                    ..clear()
                    ..addAll(value),
                ),
              ),
              AsanaFilterDropdown(
                title: 'Task PIC',
                value: _filterLabel(_taskPicIds, (id) => _staffName(state, id)),
                buttonWidth: 126,
                onPressed: (anchor) => _showFilterMenu(
                  anchorContext: anchor,
                  options: _staffOptions(state, _taskPicKeys(state)),
                  selected: _taskPicIds,
                  apply: (value) => _taskPicIds
                    ..clear()
                    ..addAll(value),
                ),
              ),
              AsanaFilterDropdown(
                title: 'Task Status',
                value: _filterLabel(_taskStatuses, _statusLabelFor),
                buttonWidth: 136,
                onPressed: (anchor) => _showFilterMenu(
                  anchorContext: anchor,
                  options: _statusOptionsFrom(_taskStatusValues(state)),
                  selected: _taskStatuses,
                  apply: (value) => _taskStatuses
                    ..clear()
                    ..addAll(value),
                ),
              ),
              AsanaFilterDropdown(
                title: 'Subtask Status',
                value: _filterLabel(_subtaskStatuses, _statusLabelFor),
                buttonWidth: 148,
                onPressed: (anchor) => _showFilterMenu(
                  anchorContext: anchor,
                  options: _statusOptionsFrom(_subtaskStatusValues(state)),
                  selected: _subtaskStatuses,
                  apply: (value) => _subtaskStatuses
                    ..clear()
                    ..addAll(value),
                ),
              ),
              AsanaFilterDropdown(
                title: 'Sort',
                value: _sortLabel(),
                buttonWidth: 126,
                onPressed: _showSortMenu,
              ),
            ],
          ),
          Expanded(
            child: AsanaPanelListSurface(
              palette: widget.palette,
              child: nodes.isEmpty && standaloneTasks.isEmpty
                  ? Center(
                      child: Text(
                        'No project map items to show.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(14),
                        itemCount: nodes.length + standaloneTasks.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: Colors.grey.shade500),
                        itemBuilder: (context, index) {
                          if (index < nodes.length) {
                            return _ProjectTreeDiagram(
                              palette: widget.palette,
                              state: state,
                              node: nodes[index],
                              onOpenProject: widget.onOpenProject,
                              onOpenTask: widget.onOpenTask,
                              onOpenSubtask: widget.onOpenSubtask,
                            );
                          }
                          return _StandaloneTaskTreeDiagram(
                            palette: widget.palette,
                            state: state,
                            node: standaloneTasks[index - nodes.length],
                            onOpenTask: widget.onOpenTask,
                            onOpenSubtask: widget.onOpenSubtask,
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectNode(
    BuildContext context,
    AppState state,
    _ProjectMapNode node,
  ) {
    final expanded = _expandedProjectIds.contains(node.project.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MapNodeRow(
          level: 0,
          typeLetter: 'P',
          name: node.project.name,
          pic: _projectPicLabel(node.project),
          status: node.project.isPaused ? 'Paused' : node.project.status,
          hasChildren: node.tasks.isNotEmpty,
          expanded: expanded,
          onToggle: () => setState(() {
            if (expanded) {
              _expandedProjectIds.remove(node.project.id);
            } else {
              _expandedProjectIds.add(node.project.id);
            }
          }),
          onTap: () => widget.onOpenProject?.call(node.project.id),
        ),
        if (expanded)
          for (final taskNode in node.tasks)
            _buildTaskNode(context, state, taskNode),
      ],
    );
  }

  Widget _buildTaskNode(
    BuildContext context,
    AppState state,
    _TaskMapNode node,
  ) {
    final expanded = _expandedTaskIds.contains(node.task.id);
    final status = AsanaTaskFilter.taskDisplayStatus(state, node.task);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MapNodeRow(
          level: 1,
          typeLetter: 'T',
          name: node.task.name,
          pic: _staffName(state, node.task.pic),
          status: status,
          hasChildren: node.subtasks.isNotEmpty,
          expanded: expanded,
          onToggle: () => setState(() {
            if (expanded) {
              _expandedTaskIds.remove(node.task.id);
            } else {
              _expandedTaskIds.add(node.task.id);
            }
          }),
          onTap: () => widget.onOpenTask?.call(node.task.id),
        ),
        if (expanded)
          for (final subtask in node.subtasks)
            _MapNodeRow(
              level: 2,
              typeLetter: 'S',
              name: subtask.subtaskName,
              pic: _staffName(state, subtask.pic),
              status: AsanaTaskFilter.subtaskDisplayStatus(
                state,
                node.task,
                subtask,
              ),
              hasChildren: false,
              expanded: false,
              onTap: () => widget.onOpenSubtask?.call(subtask.id),
            ),
      ],
    );
  }
}

class _MapNodeRow extends StatelessWidget {
  const _MapNodeRow({
    required this.level,
    required this.typeLetter,
    required this.name,
    required this.pic,
    required this.status,
    required this.hasChildren,
    required this.expanded,
    this.onToggle,
    this.onTap,
  });

  final int level;
  final String typeLetter;
  final String name;
  final String pic;
  final String status;
  final bool hasChildren;
  final bool expanded;
  final VoidCallback? onToggle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leftPadding = 12.0 + (level * 28.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(leftPadding, 8, 12, 8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: hasChildren
                    ? IconButton(
                        tooltip: expanded ? 'Collapse' : 'Expand',
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        onPressed: onToggle,
                        icon: Icon(
                          expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                        ),
                      )
                    : const SizedBox(width: 24),
              ),
              AsanaRowTypeLetter(
                letter: typeLetter,
                completed: status.trim().toLowerCase() == 'completed',
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Text(
                  name.trim().isEmpty ? 'Untitled' : name.trim(),
                  style: asanaTextStyle(
                    theme.textTheme.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextPrimary,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: _MapMetaText(label: 'PIC', value: pic),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 132,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AsanaStatusChip(
                    status: status,
                    fontSize: 12,
                    preserveFullLabel: true,
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

class _MapMetaText extends StatelessWidget {
  const _MapMetaText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final display = value.trim().isEmpty ? '—' : value.trim();
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: display),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: asanaTextStyle(
        Theme.of(context).textTheme.bodySmall,
        color: kAsanaTextSecondary,
        height: 1.25,
      ),
    );
  }
}

class _InitialHorizontalScrollView extends StatefulWidget {
  const _InitialHorizontalScrollView({
    required this.initialOffset,
    required this.child,
  });

  final double initialOffset;
  final Widget child;

  @override
  State<_InitialHorizontalScrollView> createState() =>
      _InitialHorizontalScrollViewState();
}

class _InitialHorizontalScrollViewState
    extends State<_InitialHorizontalScrollView> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(initialScrollOffset: widget.initialOffset);
  }

  @override
  void didUpdateWidget(covariant _InitialHorizontalScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.initialOffset - widget.initialOffset).abs() < 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(
        widget.initialOffset.clamp(0.0, _controller.position.maxScrollExtent),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      child: widget.child,
    );
  }
}

class _ProjectTreeDiagram extends StatelessWidget {
  const _ProjectTreeDiagram({
    required this.palette,
    required this.state,
    required this.node,
    this.onOpenProject,
    this.onOpenTask,
    this.onOpenSubtask,
  });

  static const double _boxWidth = 174;
  static const double _boxHeight = 72;
  static const double _horizontalGap = 28;
  static const double _verticalGap = 70;
  static const double _padding = 22;

  final AsanaLandingPalette palette;
  final AppState state;
  final _ProjectMapNode node;
  final void Function(String projectId)? onOpenProject;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;

  @override
  Widget build(BuildContext context) {
    final root = _toDiagramNode();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _measure(root);
          final contentWidth = root.subtreeWidth + (_padding * 2);
          final viewportWidth = constraints.maxWidth;
          final fitsInViewport = contentWidth <= viewportWidth;
          final width = fitsInViewport ? viewportWidth : contentWidth;
          final rootCenter = fitsInViewport
              ? width / 2
              : _padding + root.subtreeWidth / 2;
          _place(root, rootCenter, _padding, 0);
          final initialScrollOffset = fitsInViewport
              ? 0.0
              : (rootCenter - viewportWidth / 2)
                    .clamp(0.0, math.max(0.0, width - viewportWidth))
                    .toDouble();
          final maxDepth = _maxDepth(root);
          final height =
              _padding * 2 +
              _boxHeight +
              maxDepth * (_boxHeight + _verticalGap);
          final placed = <_PlacedDiagramNode>[];
          _collect(root, placed);
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: _InitialHorizontalScrollView(
              initialOffset: initialScrollOffset,
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TreeConnectorPainter(placed, palette),
                      ),
                    ),
                    for (final item in placed)
                      Positioned(
                        left: item.x - _boxWidth / 2,
                        top: item.y,
                        width: _boxWidth,
                        height: _boxHeight,
                        child: _DiagramBox(item: item, palette: palette),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  _DiagramNode _toDiagramNode() {
    return _DiagramNode(
      type: _DiagramNodeType.project,
      id: node.project.id,
      name: node.project.name,
      pic: _projectPicLabel(node.project),
      status: node.project.isPaused ? 'Paused' : node.project.status,
      onTap: () => onOpenProject?.call(node.project.id),
      children: [
        for (final taskNode in node.tasks)
          _DiagramNode(
            type: _DiagramNodeType.task,
            id: taskNode.task.id,
            name: taskNode.task.name,
            pic: _staffName(taskNode.task.pic),
            status: AsanaTaskFilter.taskDisplayStatus(state, taskNode.task),
            onTap: () => onOpenTask?.call(taskNode.task.id),
            children: [
              for (final subtask in taskNode.subtasks)
                _DiagramNode(
                  type: _DiagramNodeType.subtask,
                  id: subtask.id,
                  name: subtask.subtaskName,
                  pic: _staffName(subtask.pic),
                  status: AsanaTaskFilter.subtaskDisplayStatus(
                    state,
                    taskNode.task,
                    subtask,
                  ),
                  onTap: () => onOpenSubtask?.call(subtask.id),
                  children: const [],
                ),
            ],
          ),
      ],
    );
  }

  String _projectPicLabel(ProjectRecord project) {
    final names = project.picStaffDisplayNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isNotEmpty) return names.join(', ');
    return project.picStaffUuids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .join(', ');
  }

  String _staffName(String? id) {
    final key = id?.trim();
    if (key == null || key.isEmpty) return '';
    return state.assigneeById(key)?.name.trim() ?? key;
  }

  double _measure(_DiagramNode node) {
    if (node.children.isEmpty) {
      node.subtreeWidth = _boxWidth;
      return node.subtreeWidth;
    }
    final childWidth = node.children.fold<double>(
      0,
      (sum, child) => sum + _measure(child),
    );
    final gaps = _horizontalGap * (node.children.length - 1);
    node.subtreeWidth = childWidth + gaps;
    if (node.subtreeWidth < _boxWidth) node.subtreeWidth = _boxWidth;
    return node.subtreeWidth;
  }

  void _place(_DiagramNode node, double centerX, double top, int depth) {
    node.x = centerX;
    node.y = top;
    var nextLeft = centerX - node.subtreeWidth / 2;
    for (final child in node.children) {
      final childCenter = nextLeft + child.subtreeWidth / 2;
      _place(child, childCenter, top + _boxHeight + _verticalGap, depth + 1);
      nextLeft += child.subtreeWidth + _horizontalGap;
    }
  }

  int _maxDepth(_DiagramNode node) {
    if (node.children.isEmpty) return 0;
    return 1 + node.children.map(_maxDepth).reduce((a, b) => a > b ? a : b);
  }

  void _collect(_DiagramNode node, List<_PlacedDiagramNode> out) {
    final placed = _PlacedDiagramNode(
      node: node,
      x: node.x,
      y: node.y,
      children: node.children
          .map((child) => Offset(child.x, child.y))
          .toList(growable: false),
    );
    out.add(placed);
    for (final child in node.children) {
      _collect(child, out);
    }
  }
}

class _StandaloneTaskTreeDiagram extends StatelessWidget {
  const _StandaloneTaskTreeDiagram({
    required this.palette,
    required this.state,
    required this.node,
    this.onOpenTask,
    this.onOpenSubtask,
  });

  final AsanaLandingPalette palette;
  final AppState state;
  final _TaskMapNode node;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;

  @override
  Widget build(BuildContext context) {
    final root = _DiagramNode(
      type: _DiagramNodeType.task,
      id: node.task.id,
      name: node.task.name,
      pic: _staffName(node.task.pic),
      status: AsanaTaskFilter.taskDisplayStatus(state, node.task),
      onTap: () => onOpenTask?.call(node.task.id),
      children: [
        for (final subtask in node.subtasks)
          _DiagramNode(
            type: _DiagramNodeType.subtask,
            id: subtask.id,
            name: subtask.subtaskName,
            pic: _staffName(subtask.pic),
            status: AsanaTaskFilter.subtaskDisplayStatus(
              state,
              node.task,
              subtask,
            ),
            onTap: () => onOpenSubtask?.call(subtask.id),
            children: const [],
          ),
      ],
    );

    return _GenericTreeDiagram(root: root, palette: palette);
  }

  String _staffName(String? id) {
    final key = id?.trim();
    if (key == null || key.isEmpty) return '';
    return state.assigneeById(key)?.name.trim() ?? key;
  }
}

class _GenericTreeDiagram extends StatelessWidget {
  const _GenericTreeDiagram({required this.root, required this.palette});

  final _DiagramNode root;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _measure(root);
          final contentWidth =
              root.subtreeWidth + (_ProjectTreeDiagram._padding * 2);
          final viewportWidth = constraints.maxWidth;
          final fitsInViewport = contentWidth <= viewportWidth;
          final width = fitsInViewport ? viewportWidth : contentWidth;
          final rootCenter = fitsInViewport
              ? width / 2
              : _ProjectTreeDiagram._padding + root.subtreeWidth / 2;
          _place(root, rootCenter, _ProjectTreeDiagram._padding);
          final initialScrollOffset = fitsInViewport
              ? 0.0
              : (rootCenter - viewportWidth / 2)
                    .clamp(0.0, math.max(0.0, width - viewportWidth))
                    .toDouble();
          final maxDepth = _maxDepth(root);
          final height =
              _ProjectTreeDiagram._padding * 2 +
              _ProjectTreeDiagram._boxHeight +
              maxDepth *
                  (_ProjectTreeDiagram._boxHeight +
                      _ProjectTreeDiagram._verticalGap);
          final placed = <_PlacedDiagramNode>[];
          _collect(root, placed);
          return _InitialHorizontalScrollView(
            initialOffset: initialScrollOffset,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TreeConnectorPainter(placed, palette),
                    ),
                  ),
                  for (final item in placed)
                    Positioned(
                      left: item.x - _ProjectTreeDiagram._boxWidth / 2,
                      top: item.y,
                      width: _ProjectTreeDiagram._boxWidth,
                      height: _ProjectTreeDiagram._boxHeight,
                      child: _DiagramBox(item: item, palette: palette),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double _measure(_DiagramNode node) {
    if (node.children.isEmpty) {
      node.subtreeWidth = _ProjectTreeDiagram._boxWidth;
      return node.subtreeWidth;
    }
    final childWidth = node.children.fold<double>(
      0,
      (sum, child) => sum + _measure(child),
    );
    final gaps =
        _ProjectTreeDiagram._horizontalGap * (node.children.length - 1);
    node.subtreeWidth = childWidth + gaps;
    if (node.subtreeWidth < _ProjectTreeDiagram._boxWidth) {
      node.subtreeWidth = _ProjectTreeDiagram._boxWidth;
    }
    return node.subtreeWidth;
  }

  void _place(_DiagramNode node, double centerX, double top) {
    node.x = centerX;
    node.y = top;
    var nextLeft = centerX - node.subtreeWidth / 2;
    for (final child in node.children) {
      final childCenter = nextLeft + child.subtreeWidth / 2;
      _place(
        child,
        childCenter,
        top + _ProjectTreeDiagram._boxHeight + _ProjectTreeDiagram._verticalGap,
      );
      nextLeft += child.subtreeWidth + _ProjectTreeDiagram._horizontalGap;
    }
  }

  int _maxDepth(_DiagramNode node) {
    if (node.children.isEmpty) return 0;
    return 1 + node.children.map(_maxDepth).reduce((a, b) => a > b ? a : b);
  }

  void _collect(_DiagramNode node, List<_PlacedDiagramNode> out) {
    out.add(
      _PlacedDiagramNode(
        node: node,
        x: node.x,
        y: node.y,
        children: node.children
            .map((child) => Offset(child.x, child.y))
            .toList(growable: false),
      ),
    );
    for (final child in node.children) {
      _collect(child, out);
    }
  }
}

class _DiagramBox extends StatelessWidget {
  const _DiagramBox({required this.item, required this.palette});

  final _PlacedDiagramNode item;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _DiagramBoxStyle.forType(item.node.type, palette);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: item.node.onTap,
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: style.background,
            border: Border.all(color: style.border),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 4,
                offset: Offset(1, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.node.name.trim().isEmpty
                    ? 'Untitled'
                    : item.node.name.trim(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: asanaTextStyle(
                  theme.textTheme.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: style.text,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                item.node.pic.trim().isEmpty ? '—' : item.node.pic.trim(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: asanaTextStyle(
                  theme.textTheme.labelSmall,
                  color: style.secondaryText,
                  height: 1.1,
                ),
              ),
              Text(
                AsanaStatusChip.statusStyle(item.node.status).$1,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: asanaTextStyle(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w600,
                  color: style.text,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TreeConnectorPainter extends CustomPainter {
  const _TreeConnectorPainter(this.nodes, this.palette);

  final List<_PlacedDiagramNode> nodes;
  final AsanaLandingPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = palette.accent.withValues(alpha: 0.78)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final parent in nodes) {
      if (parent.children.isEmpty) continue;
      final parentBottom = Offset(
        parent.x,
        parent.y + _ProjectTreeDiagram._boxHeight,
      );
      final junctionY = parentBottom.dy + _ProjectTreeDiagram._verticalGap / 2;
      canvas.drawLine(parentBottom, Offset(parent.x, junctionY), paint);
      for (final child in parent.children) {
        final childTop = Offset(child.dx, child.dy);
        canvas.drawLine(
          Offset(parent.x, junctionY),
          Offset(child.dx, junctionY),
          paint,
        );
        canvas.drawLine(Offset(child.dx, junctionY), childTop, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TreeConnectorPainter oldDelegate) {
    return oldDelegate.nodes != nodes || oldDelegate.palette != palette;
  }
}

enum _DiagramNodeType { project, task, subtask }

class _DiagramBoxStyle {
  const _DiagramBoxStyle({
    required this.background,
    required this.border,
    required this.text,
    required this.secondaryText,
  });

  final Color background;
  final Color border;
  final Color text;
  final Color secondaryText;

  static _DiagramBoxStyle forType(
    _DiagramNodeType type,
    AsanaLandingPalette palette,
  ) {
    final surface = palette.listSurface;
    final accent = palette.accent;
    switch (type) {
      case _DiagramNodeType.project:
        return _DiagramBoxStyle(
          background: accent,
          border: accent,
          text: Colors.white,
          secondaryText: Colors.white.withValues(alpha: 0.86),
        );
      case _DiagramNodeType.task:
        return _DiagramBoxStyle(
          background: Color.alphaBlend(
            accent.withValues(alpha: palette.darkChrome ? 0.34 : 0.28),
            surface,
          ),
          border: accent.withValues(alpha: 0.52),
          text: kAsanaTextPrimary,
          secondaryText: kAsanaTextSecondary,
        );
      case _DiagramNodeType.subtask:
        return _DiagramBoxStyle(
          background: Color.alphaBlend(
            accent.withValues(alpha: palette.darkChrome ? 0.13 : 0.12),
            surface,
          ),
          border: accent.withValues(alpha: 0.30),
          text: kAsanaTextSecondary,
          secondaryText: kAsanaTextSecondary,
        );
    }
  }
}

class _DiagramNode {
  _DiagramNode({
    required this.type,
    required this.id,
    required this.name,
    required this.pic,
    required this.status,
    required this.onTap,
    required this.children,
  });

  final _DiagramNodeType type;
  final String id;
  final String name;
  final String pic;
  final String status;
  final VoidCallback onTap;
  final List<_DiagramNode> children;
  double subtreeWidth = 0;
  double x = 0;
  double y = 0;
}

class _PlacedDiagramNode {
  const _PlacedDiagramNode({
    required this.node,
    required this.x,
    required this.y,
    required this.children,
  });

  final _DiagramNode node;
  final double x;
  final double y;
  final List<Offset> children;
}

class _ProjectMapNode {
  const _ProjectMapNode({required this.project, required this.tasks});

  final ProjectRecord project;
  final List<_TaskMapNode> tasks;
}

class _TaskMapNode {
  const _TaskMapNode({required this.task, required this.subtasks});

  final Task task;
  final List<SingularSubtask> subtasks;
}
