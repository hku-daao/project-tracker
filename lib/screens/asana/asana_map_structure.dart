part of 'asana_map_panel.dart';

enum _MapStructurePick {
  none,
  makeSubprojectParent,
  makeSubtaskParent,
  moveTaskParent,
  moveSubprojectParent,
  moveSubtaskParent,
}

class _MapSelectionScope extends InheritedWidget {
  const _MapSelectionScope({
    required this.pick,
    required this.selectedProjectIds,
    required this.selectedSubprojectIds,
    required this.selectedTaskIds,
    required this.selectedSubtaskIds,
    required this.inactiveIds,
    required this.onChanged,
    required super.child,
  });

  final _MapStructurePick pick;
  final Set<String> selectedProjectIds;
  final Set<String> selectedSubprojectIds;
  final Set<String> selectedTaskIds;
  final Set<String> selectedSubtaskIds;
  final Set<String> inactiveIds;
  final void Function(_DiagramNodeType type, String id, bool selected) onChanged;

  static _MapSelectionScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_MapSelectionScope>();
  }

  bool isSelected(_DiagramNodeType type, String id) {
    return switch (type) {
      _DiagramNodeType.project => selectedProjectIds.contains(id),
      _DiagramNodeType.subproject => selectedSubprojectIds.contains(id),
      _DiagramNodeType.task => selectedTaskIds.contains(id),
      _DiagramNodeType.subtask => selectedSubtaskIds.contains(id),
      _DiagramNodeType.levelSpacer => false,
    };
  }

  bool isLocked(String id) => id.isNotEmpty && inactiveIds.contains(id);

  bool showCheckbox(_DiagramNodeType type, String id) {
    if (type == _DiagramNodeType.levelSpacer) return false;
    if (isLocked(id)) return true;
    return switch (pick) {
      _MapStructurePick.none => true,
      _MapStructurePick.makeSubprojectParent ||
      _MapStructurePick.moveSubprojectParent => type == _DiagramNodeType.project,
      _MapStructurePick.moveTaskParent =>
        type == _DiagramNodeType.project ||
            type == _DiagramNodeType.subproject,
      _MapStructurePick.makeSubtaskParent ||
      _MapStructurePick.moveSubtaskParent => type == _DiagramNodeType.task,
    };
  }

  @override
  bool updateShouldNotify(_MapSelectionScope oldWidget) => true;
}

mixin _MapStructureActions on State<AsanaMapPanel> {
  Map<String, List<SingularSubtask>> get _subtasksByTask;

  final Set<String> _selectedProjectIds = {};
  final Set<String> _selectedSubprojectIds = {};
  final Set<String> _selectedTaskIds = {};
  final Set<String> _selectedSubtaskIds = {};
  _MapStructurePick _mapPick = _MapStructurePick.none;
  Set<String> _moveSourceProjectIds = {};
  Set<String> _moveSourceSubprojectIds = {};
  Set<String> _moveSourceTaskIds = {};
  Set<String> _moveSourceSubtaskIds = {};
  Set<String> _inactiveSelectionIds = {};

  Widget _mapSelectionScope({required Widget child}) {
    return _MapSelectionScope(
      pick: _mapPick,
      selectedProjectIds: _selectedProjectIds,
      selectedSubprojectIds: _selectedSubprojectIds,
      selectedTaskIds: _selectedTaskIds,
      selectedSubtaskIds: _selectedSubtaskIds,
      inactiveIds: _inactiveSelectionIds,
      onChanged: _setMapSelected,
      child: child,
    );
  }

  List<Widget> _mapSelectionButtons(AppState state) {
    if (_mapPick != _MapStructurePick.none) {
      return [_mapStructureButton('Cancel', _clearMapSelection)];
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
            !_mapProjectIsDeleted(project) &&
            !_selectedProjectIds.contains(project.id),
      );
      if (!allEligible || !hasParent) return const [];
      return [_mapStructureButton('Make Subproject', _beginMakeSubproject)];
    }
    if (subprojectOn) {
      final selected = <SubprojectRecord>[
        for (final id in _selectedSubprojectIds)
          if (state.subprojectById(id) case final subproject?) subproject,
      ];
      if (selected.length != _selectedSubprojectIds.length) return const [];
      final buttons = <Widget>[];
      if (selected.every((subproject) => _canDetachProject(state, subproject))) {
        buttons.add(_mapStructureButton('Detach Project', _detachSelectedProjects));
      }
      if (selected.every(
            (subproject) => _viewerCanStructureSubproject(state, subproject),
          ) &&
          _hasSubprojectMoveDestination(state, selected)) {
        buttons.add(
          _mapStructureButton('Move Subproject', _beginMoveSubprojects),
        );
      }
      return buttons;
    }
    final tasks = _selectedTasks(state);
    final subtasks = _selectedSubtasks();
    if (tasks == null || subtasks == null) return const [];
    if (taskOn && subtaskOn) {
      final canClone =
          tasks.every((task) => _viewerCanStructureTask(state, task)) &&
          subtasks.every(
            (subtask) => _viewerCanStructureSubtask(state, subtask),
          );
      if (!canClone) return const [];
      return [_mapStructureButton('Clone', _cloneSelectedWork)];
    }
    if (taskOn) {
      final buttons = <Widget>[];
      if (tasks.every((task) => _viewerCanStructureTask(state, task))) {
        buttons.add(_mapStructureButton('Clone', _cloneSelectedWork));
      }
      if (tasks.every(
            (task) =>
                _viewerCanStructureTask(state, task) &&
                !_mapTaskDeleted(task) &&
                !_taskHasKnownSubtasks(task.id),
          ) &&
          _hasOtherTaskParent(state, _selectedTaskIds)) {
        buttons.add(_mapStructureButton('Make Subtask', _beginMakeSubtask));
      }
      if (tasks.every((task) => _viewerCanStructureTask(state, task)) &&
          _hasTaskMoveDestination(state, tasks)) {
        buttons.add(_mapStructureButton('Move Task', _beginMoveTasks));
      }
      return buttons;
    }
    if (subtaskOn) {
      final buttons = <Widget>[];
      if (subtasks.every(
        (subtask) =>
            _viewerCanStructureSubtask(state, subtask) && !subtask.isDeleted,
      )) {
        buttons.add(_mapStructureButton('Clone', _cloneSelectedWork));
      }
      if (subtasks.every(
        (subtask) =>
            _viewerCanStructureSubtask(state, subtask) && !subtask.isDeleted,
      )) {
        buttons.add(_mapStructureButton('Detach Task', _detachSelectedTasks));
        if (_hasSubtaskMoveDestination(state, subtasks)) {
          buttons.add(
            _mapStructureButton('Move Subtask', _beginMoveSubtasks),
          );
        }
      }
      return buttons;
    }
    return const [];
  }

  void _setMapSelected(_DiagramNodeType type, String id, bool selected) {
    switch (type) {
      case _DiagramNodeType.project:
        _setProjectSelected(id, selected);
      case _DiagramNodeType.subproject:
        _setSubprojectSelected(id, selected);
      case _DiagramNodeType.task:
        _setTaskSelected(id, selected);
      case _DiagramNodeType.subtask:
        _setSubtaskSelected(id, selected);
      case _DiagramNodeType.levelSpacer:
        break;
    }
  }

  void _clearMapSelection() {
    setState(() {
      _selectedProjectIds.clear();
      _selectedSubprojectIds.clear();
      _selectedTaskIds.clear();
      _selectedSubtaskIds.clear();
      _mapPick = _MapStructurePick.none;
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
        _mapPick = _MapStructurePick.none;
        _selectedProjectIds.clear();
        _selectedSubprojectIds.clear();
        _selectedTaskIds.clear();
        _selectedSubtaskIds.clear();
      }
    });
  }

  void _setProjectSelected(String projectId, bool selected) {
    switch (_mapPick) {
      case _MapStructurePick.makeSubprojectParent:
        if (!selected) {
          _dropMoveSource(_moveSourceProjectIds, projectId);
          return;
        }
        if (_moveSourceProjectIds.contains(projectId)) return;
        unawaited(_confirmMakeSubprojectUnder(projectId));
        return;
      case _MapStructurePick.moveSubprojectParent:
        if (!selected) return;
        unawaited(_finishMoveSubprojects(projectId));
        return;
      case _MapStructurePick.moveTaskParent:
        if (!selected) return;
        unawaited(_finishMoveTasks(projectId: projectId));
        return;
      case _MapStructurePick.makeSubtaskParent:
      case _MapStructurePick.moveSubtaskParent:
        return;
      case _MapStructurePick.none:
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
    switch (_mapPick) {
      case _MapStructurePick.moveSubprojectParent:
        if (!selected && _moveSourceSubprojectIds.contains(subprojectId)) {
          _dropMoveSource(_moveSourceSubprojectIds, subprojectId);
        }
        return;
      case _MapStructurePick.moveTaskParent:
        if (!selected) return;
        unawaited(_finishMoveTasks(subprojectId: subprojectId));
        return;
      case _MapStructurePick.makeSubprojectParent:
      case _MapStructurePick.makeSubtaskParent:
      case _MapStructurePick.moveSubtaskParent:
        return;
      case _MapStructurePick.none:
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
    switch (_mapPick) {
      case _MapStructurePick.makeSubtaskParent:
        if (!selected) {
          if (_moveSourceTaskIds.contains(taskId)) {
            _dropMoveSource(_moveSourceTaskIds, taskId);
          }
          return;
        }
        if (_moveSourceTaskIds.contains(taskId)) return;
        unawaited(_confirmMakeSubtaskUnder(taskId));
        return;
      case _MapStructurePick.moveSubtaskParent:
        if (!selected) return;
        unawaited(_finishMoveSubtasks(taskId));
        return;
      case _MapStructurePick.moveTaskParent:
        if (!selected && _moveSourceTaskIds.contains(taskId)) {
          _dropMoveSource(_moveSourceTaskIds, taskId);
        }
        return;
      case _MapStructurePick.makeSubprojectParent:
      case _MapStructurePick.moveSubprojectParent:
        return;
      case _MapStructurePick.none:
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
    if (_mapPick == _MapStructurePick.moveSubtaskParent) {
      if (!selected && _moveSourceSubtaskIds.contains(subtaskId)) {
        _dropMoveSource(_moveSourceSubtaskIds, subtaskId);
      }
      return;
    }
    if (_mapPick != _MapStructurePick.none) return;
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

  bool _viewerCreatedProject(AppState state, ProjectRecord project) {
    return _staffHit(state, project.createByStaffUuid);
  }

  bool _viewerCreatedSubproject(AppState state, SubprojectRecord subproject) {
    return _staffHit(state, subproject.createByStaffUuid);
  }

  bool _viewerCanStructureProject(AppState state, ProjectRecord project) {
    return _viewerIsProjectPic(state, project) ||
        _viewerCreatedProject(state, project);
  }

  bool _viewerCanStructureSubproject(
    AppState state,
    SubprojectRecord subproject,
  ) {
    return _viewerIsSubprojectPic(state, subproject) ||
        _viewerCreatedSubproject(state, subproject);
  }

  bool _canMakeSubproject(AppState state, ProjectRecord project) {
    if (_mapProjectIsDeleted(project) || project.hasMilestone) return false;
    if (!_viewerCanStructureProject(state, project)) return false;
    return state.subprojectsForProject(project.id).isEmpty;
  }

  bool _canDetachProject(AppState state, SubprojectRecord subproject) {
    if (subproject.isDeleted) return false;
    return _viewerCanStructureSubproject(state, subproject);
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

  bool _viewerCanStructureTask(AppState state, Task task) {
    return _viewerIsTaskPic(state, task) || _viewerCreatedTask(state, task);
  }

  bool _viewerCanStructureSubtask(AppState state, SingularSubtask subtask) {
    return _viewerIsSubtaskPic(state, subtask) ||
        _viewerCreatedSubtask(state, subtask);
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
      if (!task.isSingularTableRow || _mapTaskDeleted(task)) continue;
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
      if (_mapProjectIsDeleted(project)) continue;
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
      if (_mapProjectIsDeleted(project)) continue;
      if (subprojects.any((subproject) => subproject.projectId != project.id)) {
        return true;
      }
    }
    return false;
  }

  bool _hasSubtaskMoveDestination(AppState state, List<SingularSubtask> subtasks) {
    for (final task in state.tasksForTeams({})) {
      if (!task.isSingularTableRow || _mapTaskDeleted(task)) continue;
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

  Widget _mapStructureButton(String label, VoidCallback onPressed) {
    return FilledButton(
      onPressed: onPressed,
      style: asanaToolbarActionStyle(
        widget.palette.accent,
        height: kAsanaShortToolbarActionHeight,
      ),
      child: Text(label),
    );
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
    List<String> scrollLines = const [],
  }) {
    return showAsanaConfirmDialog(
      context: context,
      title: title,
      content: content,
      confirmText: confirmText,
      cancelText: cancelText,
      palette: widget.palette,
      scrollLines: scrollLines,
    );
  }

  bool _mapProjectIsDeleted(ProjectRecord project) {
    final status = project.status.trim().toLowerCase();
    return status == 'deleted' || status == 'delete';
  }

  bool _mapTaskDeleted(Task task) {
    final status = task.dbStatus?.trim().toLowerCase() ?? '';
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
          'Check one project on the map. That project will become the parent, and each checked project will move under it as a sub-project. Tasks move with those projects.',
    );
    if (!mounted) return;
    setState(() {
      _mapPick = _MapStructurePick.makeSubprojectParent;
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
      _clearMapSelection();
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
          : 'Move these projects under $parentName?',
      scrollLines: sources.length == 1
          ? const <String>[]
          : [
              for (final item in sources)
                asanaDialogUnbold(_projectLabel(item)),
            ],
      confirmText: 'Yes',
      cancelText: 'No',
    );
    if (!mounted) return;
    if (confirmed != true) {
      _clearMapSelection();
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
    _clearMapSelection();
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
          : 'These sub-projects will leave their parents and become their own projects. Their tasks move with them.',
      scrollLines: selected.length == 1
          ? const <String>[]
          : [
              for (final item in selected)
                asanaDialogUnbold(_subprojectLabel(item)),
            ],
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
    _clearMapSelection();
    widget.onStructureChanged?.call();
    if (error != null) {
      await _showStructureInfoDialog(title: 'Could not detach', content: error);
    }
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
    _clearMapSelection();
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
          'Check one task on the map. That task will become the parent, and each checked task will move under it as a sub-task.',
    );
    if (!mounted) return;
    setState(() {
      _mapPick = _MapStructurePick.makeSubtaskParent;
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
    if (sources.isEmpty || parent == null || _mapTaskDeleted(parent)) {
      _clearMapSelection();
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
          : 'Move these tasks under $parentName as sub-tasks?',
      scrollLines: sources.length == 1
          ? const <String>[]
          : [
              for (final item in sources) asanaDialogUnbold(_taskLabel(item)),
            ],
      confirmText: 'Yes',
      cancelText: 'No',
    );
    if (!mounted) return;
    if (confirmed != true) {
      _clearMapSelection();
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
    _clearMapSelection();
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
          : 'These sub-tasks will leave their parent tasks and become their own tasks under the same project.',
      scrollLines: subtasks.length == 1
          ? const <String>[]
          : [
              for (final item in subtasks)
                asanaDialogUnbold(_subtaskLabel(item)),
            ],
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
    _clearMapSelection();
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
          'Check one project or sub-project on the map. The checked tasks will move under it. Their sub-tasks move with them.',
    );
    if (!mounted) return;
    final state = context.read<AppState>();
    final moving = <Task>[
      for (final task in state.tasksForTeams({}))
        if (_selectedTaskIds.contains(task.id)) task,
    ];
    final sharedParent = _sharedTaskParentId(moving);
    setState(() {
      _mapPick = _MapStructurePick.moveTaskParent;
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
      _clearMapSelection();
      return;
    }
    final destination = _moveTaskDestinationLabel(
      state,
      projectId: projectId,
      subprojectId: subprojectId,
    );
    if (destination == null) {
      _clearMapSelection();
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
          : 'Move these tasks under $destination?',
      scrollLines: sources.length == 1
          ? const <String>[]
          : [
              for (final item in sources) asanaDialogUnbold(_taskLabel(item)),
            ],
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
    _clearMapSelection();
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
          'Check one project on the map. The checked sub-projects will move under it. Their tasks move with them.',
    );
    if (!mounted) return;
    final state = context.read<AppState>();
    final moving = <SubprojectRecord>[
      for (final id in _selectedSubprojectIds)
        if (state.subprojectById(id) case final subproject?) subproject,
    ];
    final sharedParent = _sharedSubprojectParentId(moving);
    setState(() {
      _mapPick = _MapStructurePick.moveSubprojectParent;
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
      _clearMapSelection();
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
      _clearMapSelection();
      return;
    }
    setState(() => _selectedProjectIds.add(parentId));
    final sourceNames = sources.map(_subprojectLabel).join(', ');
    final parentName = _projectLabel(parent);
    final confirmed = await _showStructureConfirmDialog(
      title: 'Move Subproject',
      content: sources.length == 1
          ? 'Move $sourceNames under $parentName?'
          : 'Move these sub-projects under $parentName?',
      scrollLines: sources.length == 1
          ? const <String>[]
          : [
              for (final item in sources)
                asanaDialogUnbold(_subprojectLabel(item)),
            ],
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
    _clearMapSelection();
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
          'Check one task on the map. The checked sub-tasks will move under it.',
    );
    if (!mounted) return;
    final moving = <SingularSubtask>[
      for (final list in _subtasksByTask.values)
        for (final subtask in list)
          if (_selectedSubtaskIds.contains(subtask.id)) subtask,
    ];
    final sharedParent = _sharedSubtaskParentId(moving);
    setState(() {
      _mapPick = _MapStructurePick.moveSubtaskParent;
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
      _clearMapSelection();
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
      _clearMapSelection();
      return;
    }
    setState(() => _selectedTaskIds.add(parentId));
    final sourceNames = sources.map(_subtaskLabel).join(', ');
    final parentName = _taskLabel(parent);
    final confirmed = await _showStructureConfirmDialog(
      title: 'Move Subtask',
      content: sources.length == 1
          ? 'Move $sourceNames under $parentName?'
          : 'Move these sub-tasks under $parentName?',
      scrollLines: sources.length == 1
          ? const <String>[]
          : [
              for (final item in sources)
                asanaDialogUnbold(_subtaskLabel(item)),
            ],
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
    _clearMapSelection();
    widget.onStructureChanged?.call();
    if (error != null) {
      await _showStructureInfoDialog(title: 'Could not move', content: error);
    }
  }
}
