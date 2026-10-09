import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../commencement_status.dart';
import '../../config/dev_auth_context.dart';
import '../../models/project_record.dart';
import '../../models/singular_subtask.dart';
import '../../models/subproject_record.dart';
import '../../models/task.dart';
import '../../services/database_service.dart';
import '../../services/asana_filter_cookie_storage.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_filter_widgets.dart';
import 'asana_project_filter.dart';
import 'asana_task_filter.dart';
import 'asana_name_freshness.dart';
import 'asana_project_milestone_section.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

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
  });

  final AsanaLandingPalette palette;
  final String searchQuery;
  final int refreshToken;
  final void Function(String projectId)? onOpenProject;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;
  final void Function(String subprojectId, String projectId)? onOpenSubproject;
  final VoidCallback? onCreateProject;

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

    return ColoredBox(
      color: widget.palette.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _scopeSectionTitle(),
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

  String _scopeSectionTitle() {
    if (_filters.scopes.isEmpty || _filters.scopes.contains('all')) {
      return 'Projects created by or assigned to my team';
    }
    if (_filters.scopes.length == 1) {
      if (_filters.scopes.contains('assigned')) {
        return 'Projects assigned to me';
      }
      if (_filters.scopes.contains('created')) return 'Projects created by me';
    }
    if (_filters.scopes.contains('assigned') &&
        _filters.scopes.contains('created')) {
      return 'Projects created by or assigned to me';
    }
    return 'Projects (Multiple scopes)';
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
  _ProjectTableLayout(this.tableWidth);

  final double tableWidth;

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
  _ProjectExpandedTaskTableLayout(this.tableWidth);

  final double tableWidth;

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

  late final _projectCols = _ProjectTableLayout(tableWidth);

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
  });

  final double tableWidth;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    final cols = _ProjectTableLayout(tableWidth);
    final style = asanaTableHeaderStyle(
      context,
      color: asanaOnHeaderFill(fillColor),
    );
    return asanaTableHeaderShell(
      fillColor: fillColor,
      horizontalPad: _ProjectTableLayout.hPad,
      child: Row(
        children: [
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

  @override
  Widget build(BuildContext context) {
    final subprojects = appState.subprojectsForProject(project.id);
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
            expandControl: hasChildren
                ? _ProjectExpandChevron(
                    expanded: expanded,
                    onPressed: onToggleExpand,
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
                      ),
                      _ProjectTableHeader(
                        tableWidth: tableWidth,
                        fillColor: headerColors.project,
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
  });

  final bool expanded;
  final VoidCallback onPressed;

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
              color: kAsanaTextSecondary,
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
  });

  final double tableWidth;
  final Color fillColor;
  final String nameLabel;
  final bool showSubmission;

  @override
  Widget build(BuildContext context) {
    final cols = _ProjectExpandedTaskTableLayout(tableWidth);
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

  @override
  Widget build(BuildContext context) {
    final completed = subproject.isCompleted;
    final cols = _ProjectExpandedTaskTableLayout(tableWidth);
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: true,
    );
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
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

  @override
  Widget build(BuildContext context) {
    final status = AsanaTaskFilter.taskDisplayStatus(appState, task);
    final completed = _taskCompleted(task);
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
    );
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: true,
    );
    final cols = _ProjectExpandedTaskTableLayout(tableWidth);
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
  });

  final bool expanded;
  final bool loading;
  final VoidCallback onPressed;

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
                    color: kAsanaTextPrimary,
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

  @override
  Widget build(BuildContext context) {
    final status = AsanaTaskFilter.subtaskDisplayStatus(
      appState,
      parentTask,
      subtask,
    );
    final completed = _subtaskCompleted(subtask);
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
    );
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: true,
    );
    final cols = _ProjectExpandedTaskTableLayout(tableWidth);

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
  const _ProjectProgressPercent({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final color = percent >= 100
        ? const Color(0xFF1B7A4E)
        : percent <= 0
        ? kAsanaTextSecondary
        : Theme.of(context).colorScheme.primary;
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
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final Color rowColor;
  final ProjectRecord project;
  final int progressPercent;
  final AppState appState;
  final VoidCallback? onRowTap;
  final Widget? expandControl;

  bool get _completed => project.status.trim() == 'Completed';
  bool get _deleted {
    final s = project.status.trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  @override
  Widget build(BuildContext context) {
    final cols = _ProjectTableLayout(tableWidth);
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: _completed,
    );
    final nameStyle = asanaTableRowNameStyle(context, completed: _completed);

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
                            _ProjectProgressPercent(percent: progressPercent),
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
    this.trailingChips = const [],
    this.progressPercent,
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
  final List<Widget> trailingChips;
  final int? progressPercent;

  @override
  Widget build(BuildContext context) {
    final metaLine = 'Cr: $creator · PIC: $pic';
    final dateLine =
        'Start: ${_formatDueDate(startDate)} · Due: ${_formatDueDate(dueDate)}';
    return Material(
      color: rowColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
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
                      style: nameStyle,
                      createdAt: createdAt,
                      updatedAt: updatedAt,
                      maxLines: 2,
                    ),
                    if (progressPercent != null)
                      _ProjectProgressPercent(percent: progressPercent!),
                    const SizedBox(height: 5),
                    Text(
                      metaLine,
                      style: valueStyle,
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
                          style: valueStyle,
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
        ),
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
        appState.subprojectsForProject(project.id).isNotEmpty;
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
          expandControl: hasChildren
              ? _ProjectMobileExpandChevron(
                  expanded: expanded,
                  onPressed: onToggleExpand,
                )
              : null,
        ),
        if (tasks.isNotEmpty ||
            appState.subprojectsForProject(project.id).isNotEmpty)
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
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        child: Icon(
          expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 20,
          color: kAsanaTextSecondary,
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

  @override
  Widget build(BuildContext context) {
    final subprojects = appState.subprojectsForProject(projectId);
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
          onTap: onOpenSubproject == null
              ? null
              : () => onOpenSubproject!(subproject.id, subproject.projectId),
          expandControl: childTasks.isNotEmpty
              ? _ProjectMobileExpandChevron(
                  expanded: expanded,
                  onPressed: () => onToggleSubprojectExpand(subproject.id),
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
  });

  final Task parentTask;
  final SingularSubtask subtask;
  final AsanaTableColors tableColors;
  final AsanaHierarchyRowColors hierarchyColors;
  final AppState appState;
  final VoidCallback? onTap;

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
