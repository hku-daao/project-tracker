import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../commencement_status.dart';
import '../../models/project_record.dart';
import '../../models/singular_subtask.dart';
import '../../models/subproject_record.dart';
import '../../models/task.dart';
import '../../services/database_service.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_due_badge.dart';
import 'asana_project_filter.dart';
import 'asana_project_milestone_section.dart';
import 'asana_task_filter.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

/// Home tab: greeting, task lists, people summary, and projects.
class AsanaHomePanel extends StatefulWidget {
  const AsanaHomePanel({
    super.key,
    required this.palette,
    this.searchQuery = '',
    this.onOpenTask,
    this.onOpenSubtask,
    this.onOpenProject,
    this.onOpenSubproject,
  });

  final AsanaLandingPalette palette;
  final String searchQuery;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;
  final void Function(String projectId)? onOpenProject;
  final void Function(String subprojectId, String projectId)? onOpenSubproject;

  @override
  State<AsanaHomePanel> createState() => _AsanaHomePanelState();

  static const double _cardRadius = 16;
  static const double _gridGap = 12;
  static const double _panelTitleFontSize = 22;

  /// Home content width at or above this keeps the 2×2 card grid.
  static const double _twoColumnGridMinWidth = 1000;

  static const int _minVisibleTaskRows = 5;
  static const double _taskRowHeight = 44;
  static const double _homeWorkNameInset = 10;
  static const double _rowDividerHeight = 1;
  static const double _tableHeaderHeight = 34;
  static const double _cardPaddingVertical = 30;
  static const double _cardTitleBlockHeight = _panelTitleFontSize * 1.2 + 12;
  static const double homeListMinHeight =
      _rowDividerHeight +
      _minVisibleTaskRows * _taskRowHeight +
      (_minVisibleTaskRows - 1) * _rowDividerHeight;
  static const double homeCardMinHeight =
      _cardPaddingVertical +
      _cardTitleBlockHeight +
      _tableHeaderHeight +
      _rowDividerHeight +
      homeListMinHeight;

  /// Title block + top/bottom padding in [_HomeCardShell] (excludes list body).
  static const double _homeShellHeaderHeight =
      18 + _panelTitleFontSize * 1.2 + 4 + 12 + 12;

  /// Room at the bottom of the first screen for the People panel title.
  static const double _peopleTitlePeek = 76;

  /// Desktop height for each of the top two panel rows so People title is visible.
  static double desktopWorkPanelRowHeight(double viewportHeight) {
    if (!viewportHeight.isFinite || viewportHeight <= 0) return 280;
    final available = viewportHeight - _peopleTitlePeek - _gridGap * 2;
    return (available / 2).clamp(220.0, 420.0);
  }

  /// List viewport height inside the card body (shell chrome already excluded).
  static double listViewportHeight({
    required double maxHeight,
    required bool fillHeight,
    required double chromeAboveList,
  }) {
    if (!fillHeight || !maxHeight.isFinite || maxHeight <= 0) {
      return homeListMinHeight;
    }
    final listH = maxHeight - chromeAboveList;
    return listH.clamp(0, double.infinity);
  }
}

class _AsanaHomePanelState extends State<AsanaHomePanel> {
  final Map<String, bool> _expanded = {
    'created': true,
    'assigned': true,
    'projectsCreated': true,
    'projectsAssigned': true,
    'people': true,
  };
  Map<String, List<SingularSubtask>> _peopleSubtasksByTaskId = {};
  String _peopleSubtaskTaskIdsKey = '';
  int _peopleSubtaskLoadSerial = 0;
  final Map<String, int> _milestoneProgressByProject = {};
  String _milestoneProgressIdsKey = '';
  int _milestoneProgressLoadSerial = 0;

  void _toggleSection(String key) {
    setState(() => _expanded[key] = !(_expanded[key] ?? true));
  }

  AsanaLandingPalette get palette => widget.palette;

  static String _formatHeaderDate(DateTime today) {
    final main = DateFormat('MMM d, yyyy').format(today);
    final weekday = DateFormat('EEEE').format(today);
    return '$main ($weekday)';
  }

  static List<Task> _activeSingularTasks(AppState state) {
    return state.tasksForTeams({}).where((t) {
      if (!t.isSingularTableRow) return false;
      final ds = t.dbStatus?.trim().toLowerCase() ?? '';
      return ds != 'delete' && ds != 'deleted';
    }).toList();
  }

  static String _greetingDisplayName(AppState state) {
    final id = state.effectiveStaffAppId?.trim();
    if (id != null && id.isNotEmpty) {
      final name = state.assigneeById(id)?.name.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    final lookup = state.revampStaffLookup;
    final fromLookup = lookup?.staffName?.trim();
    if (fromLookup != null && fromLookup.isNotEmpty) return fromLookup;
    return 'there';
  }

  static String _greetingPhrase() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _picLine(AppState state, String? picKey) {
    final key = picKey?.trim();
    if (key == null || key.isEmpty) return '—';
    return state.assigneeById(key)?.name.trim() ?? key;
  }

  static bool _isSubmitted(String? raw) =>
      (raw?.trim().toLowerCase() ?? '') == 'submitted';

  static bool _isToBeCommenced(String? raw) =>
      normalizeCommencementStatus(raw) == commencementToBeCommenced;

  static bool _isToBeCommencedWorkStatus(String? raw) =>
      (raw?.trim().toLowerCase() ?? '') == 'to be commenced';

  /// Left Home panel: hide items that are not yet started or already submitted.
  static bool _hideFromLeftHomePanel({
    required String? commencementStatus,
    required String? submission,
    String? workStatus,
  }) {
    return _isSubmitted(submission) ||
        _isToBeCommenced(commencementStatus) ||
        _isToBeCommencedWorkStatus(workStatus);
  }

  static List<_HomeWorkItem> _adminIncompleteWorkItems(
    List<Task> tasks,
    Map<String, List<SingularSubtask>> subtasksByTaskId,
  ) {
    final out = <_HomeWorkItem>[];
    for (final t in tasks) {
      if (_isIncomplete(t) &&
          !_hideFromLeftHomePanel(
            commencementStatus: t.commencementStatus,
            submission: t.submission,
            workStatus: t.dbStatus,
          )) {
        out.add(_HomeWorkItem.task(t));
      }
      for (final s in subtasksByTaskId[t.id] ?? const <SingularSubtask>[]) {
        if (s.isDeleted || _subtaskCompleted(s)) continue;
        if (_hideFromLeftHomePanel(
          commencementStatus: s.commencementStatus,
          submission: s.submission,
          workStatus: s.status,
        )) {
          continue;
        }
        out.add(_HomeWorkItem.subtask(s, parent: t));
      }
    }
    out.sort(_sortWorkByDueAscending);
    return out;
  }

  static List<_HomeWorkItem> _adminCompletedWorkItems(
    List<Task> tasks,
    Map<String, List<SingularSubtask>> subtasksByTaskId,
  ) {
    final out = <_HomeWorkItem>[];
    for (final t in tasks) {
      if (_isCompleted(t)) out.add(_HomeWorkItem.task(t));
      for (final s in subtasksByTaskId[t.id] ?? const <SingularSubtask>[]) {
        if (s.isDeleted || !_subtaskCompleted(s)) continue;
        out.add(_HomeWorkItem.subtask(s, parent: t));
      }
    }
    out.sort(_sortWorkByDueAscending);
    return out;
  }

  static List<_HomeWorkItem> _userCreatedWorkItems(
    AppState state,
    List<Task> tasks,
    Map<String, List<SingularSubtask>> subtasksByTaskId,
  ) {
    final out = <_HomeWorkItem>[];
    for (final t in tasks) {
      if (state.taskIsCreatedByCurrentUser(t) &&
          _isIncomplete(t) &&
          !_hideFromLeftHomePanel(
            commencementStatus: t.commencementStatus,
            submission: t.submission,
            workStatus: t.dbStatus,
          )) {
        out.add(_HomeWorkItem.task(t));
      }
      for (final s in subtasksByTaskId[t.id] ?? const <SingularSubtask>[]) {
        if (s.isDeleted || _subtaskCompleted(s)) continue;
        if (_hideFromLeftHomePanel(
          commencementStatus: s.commencementStatus,
          submission: s.submission,
          workStatus: s.status,
        )) {
          continue;
        }
        if (_subtaskCreatedByCurrentUser(state, s)) {
          out.add(_HomeWorkItem.subtask(s, parent: t));
        }
      }
    }
    out.sort(_sortWorkByDueAscending);
    return out;
  }

  static List<_HomeWorkItem> _userAssignedWorkItems(
    AppState state,
    List<Task> tasks,
    Map<String, List<SingularSubtask>> subtasksByTaskId,
  ) {
    final out = <_HomeWorkItem>[];
    final appId = state.effectiveStaffAppId?.trim() ?? '';
    final staffUuid = state.effectiveStaffUuid?.trim();
    for (final t in tasks) {
      if (_taskMatchesStaff(state, t, appId, staffUuid) &&
          _isIncomplete(t) &&
          !_hideFromLeftHomePanel(
            commencementStatus: t.commencementStatus,
            submission: t.submission,
            workStatus: t.dbStatus,
          )) {
        out.add(_HomeWorkItem.task(t));
      }
      for (final s in subtasksByTaskId[t.id] ?? const <SingularSubtask>[]) {
        if (s.isDeleted || _subtaskCompleted(s)) continue;
        if (_hideFromLeftHomePanel(
          commencementStatus: s.commencementStatus,
          submission: s.submission,
          workStatus: s.status,
        )) {
          continue;
        }
        if (_subtaskMatchesStaff(state, s, appId, staffUuid)) {
          out.add(_HomeWorkItem.subtask(s, parent: t));
        }
      }
    }
    out.sort(_sortWorkByDueAscending);
    return out;
  }

  static bool _subtaskCreatedByCurrentUser(AppState state, SingularSubtask s) {
    final mine = state.effectiveStaffAppId?.trim();
    final sid = state.effectiveStaffUuid?.trim();
    final cb = s.createByStaffId?.trim();
    if (cb == null || cb.isEmpty) return false;
    if (mine != null && mine.isNotEmpty && cb == mine) return true;
    if (sid != null &&
        sid.isNotEmpty &&
        cb.toLowerCase() == sid.toLowerCase()) {
      return true;
    }
    return false;
  }

  static List<_HomeWorkItem> _filterWorkItemsBySearch(
    AppState state,
    List<_HomeWorkItem> items,
    List<String> tokens,
  ) {
    if (tokens.isEmpty) return items;
    return items.where((item) {
      if (item.isSubtask) {
        return AsanaTaskFilter.subtaskSearchMatches(
          state,
          item.subtask!,
          tokens,
        );
      }
      return AsanaTaskFilter.taskSearchMatches(state, item.task, tokens);
    }).toList();
  }

  static int _sortWorkByDueAscending(_HomeWorkItem a, _HomeWorkItem b) {
    final ae = a.dueDate;
    final be = b.dueDate;
    if (ae == null && be == null) return a.name.compareTo(b.name);
    if (ae == null) return 1;
    if (be == null) return -1;
    final c = ae.compareTo(be);
    return c != 0 ? c : a.name.compareTo(b.name);
  }

  static bool _projectActive(ProjectRecord p) {
    final s = p.status.trim().toLowerCase();
    return s != 'deleted' && s != 'delete';
  }

  static List<_HomeNestItem> _userCreatedNestItems(AppState state) {
    final out = <_HomeNestItem>[];
    for (final p in state.projects) {
      if (!_projectActive(p)) continue;
      if (AsanaProjectFilter.projectCreatedByCurrentUser(state, p)) {
        out.add(_HomeNestItem.project(p));
      }
    }
    for (final s in state.subprojects) {
      if (s.isDeleted) continue;
      if (AsanaProjectFilter.subprojectCreatedByCurrentUser(state, s)) {
        out.add(_HomeNestItem.subproject(s));
      }
    }
    out.sort(_sortNestItems);
    return out;
  }

  static List<_HomeNestItem> _userAssignedNestItems(AppState state) {
    final out = <_HomeNestItem>[];
    for (final p in state.projects) {
      if (!_projectActive(p)) continue;
      if (AsanaProjectFilter.projectAssignedToCurrentUser(state, p)) {
        out.add(_HomeNestItem.project(p));
      }
    }
    for (final s in state.subprojects) {
      if (s.isDeleted) continue;
      if (AsanaProjectFilter.subprojectAssignedToCurrentUser(state, s)) {
        out.add(_HomeNestItem.subproject(s));
      }
    }
    out.sort(_sortNestItems);
    return out;
  }

  static List<_HomeNestItem> _adminNestItems(AppState state) {
    final out = <_HomeNestItem>[
      for (final p in state.projects)
        if (_projectActive(p)) _HomeNestItem.project(p),
      for (final s in state.subprojects)
        if (!s.isDeleted) _HomeNestItem.subproject(s),
    ];
    out.sort(_sortNestItems);
    return out;
  }

  static int _sortNestItems(_HomeNestItem a, _HomeNestItem b) {
    if (a.isSubproject != b.isSubproject) {
      return a.isSubproject ? 1 : -1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  static List<_HomeNestItem> _filterNestItemsBySearch(
    AppState state,
    List<_HomeNestItem> items,
    List<String> tokens,
  ) {
    if (tokens.isEmpty) return items;
    return items.where((item) {
      if (item.isSubproject) {
        return AsanaProjectFilter.subprojectSearchMatches(
          state,
          item.subproject!,
          tokens,
        );
      }
      return AsanaProjectFilter.projectSearchMatches(
        state,
        item.project!,
        tokens,
      );
    }).toList();
  }

  static _HomeNestCounts _nestCountsFor(
    AppState state,
    _HomeNestItem item,
    List<Task> tasks,
    Map<String, List<SingularSubtask>> subtasksByTaskId,
  ) {
    if (item.isSubproject) {
      final sid = item.id;
      final linked = [
        for (final t in tasks)
          if ((t.subprojectId ?? '').trim() == sid) t,
      ];
      var subtaskN = 0;
      for (final t in linked) {
        for (final s in subtasksByTaskId[t.id] ?? const <SingularSubtask>[]) {
          if (!s.isDeleted) subtaskN++;
        }
      }
      return _HomeNestCounts(
        subprojects: 0,
        tasks: linked.length,
        subtasks: subtaskN,
      );
    }
    final pid = item.id;
    final sps = state.subprojectsForProject(pid);
    final linked = [
      for (final t in tasks)
        if ((t.projectId ?? '').trim() == pid) t,
    ];
    var subtaskN = 0;
    for (final t in linked) {
      for (final s in subtasksByTaskId[t.id] ?? const <SingularSubtask>[]) {
        if (!s.isDeleted) subtaskN++;
      }
    }
    return _HomeNestCounts(
      subprojects: sps.length,
      tasks: linked.length,
      subtasks: subtaskN,
    );
  }

  int _progressForProject(ProjectRecord project) {
    return asanaProjectListProgressPercent(
      hasMilestone: project.hasMilestone,
      status: project.status,
      milestoneAchievedPercent: _milestoneProgressByProject[project.id] ?? 0,
    );
  }

  void _ensureMilestoneProgressLoaded(List<_HomeNestItem> items) {
    final ids = [
      for (final item in items)
        if (!item.isSubproject && item.project!.hasMilestone) item.id,
    ]..sort();
    final key = ids.join('|');
    if (key == _milestoneProgressIdsKey) return;
    _milestoneProgressIdsKey = key;
    final serial = ++_milestoneProgressLoadSerial;
    if (ids.isEmpty) {
      if (_milestoneProgressByProject.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && serial == _milestoneProgressLoadSerial) {
            setState(_milestoneProgressByProject.clear);
          }
        });
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final map =
          await DatabaseService.fetchAchievedMilestonePercentByProject(ids);
      if (!mounted || serial != _milestoneProgressLoadSerial) return;
      setState(() {
        _milestoneProgressByProject
          ..clear()
          ..addAll(map);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final today = HkTime.todayDateOnlyHk();
    final dateLine = _formatHeaderDate(today);
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final searchTokens = AsanaProjectFilter.searchTokens(widget.searchQuery);
    final adminViewMode = state.showAllDataAsAdmin;
    final greetingName = adminViewMode
        ? 'Administrator'
        : _greetingDisplayName(state);
    final greeting = '${_greetingPhrase()}, $greetingName';

    final all = _activeSingularTasks(state);
    _ensurePeopleSubtasksLoaded(all);
    final leftItems = _filterWorkItemsBySearch(
      state,
      adminViewMode
          ? _adminIncompleteWorkItems(all, _peopleSubtasksByTaskId)
          : _userCreatedWorkItems(state, all, _peopleSubtasksByTaskId),
      searchTokens,
    );
    final rightItems = _filterWorkItemsBySearch(
      state,
      adminViewMode
          ? _adminCompletedWorkItems(all, _peopleSubtasksByTaskId)
          : _userAssignedWorkItems(state, all, _peopleSubtasksByTaskId),
      searchTokens,
    );

    final people = _peopleRows(state, all, _peopleSubtasksByTaskId, today);

    final nestCreated = _filterNestItemsBySearch(
      state,
      adminViewMode
          ? _adminNestItems(state)
          : _userCreatedNestItems(state),
      searchTokens,
    );
    final nestAssigned = _filterNestItemsBySearch(
      state,
      adminViewMode ? const <_HomeNestItem>[] : _userAssignedNestItems(state),
      searchTokens,
    );
    _ensureMilestoneProgressLoaded([...nestCreated, ...nestAssigned]);

    return ColoredBox(
      color: palette.panelBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateLine,
              style: asanaTextStyle(
                Theme.of(context).textTheme.bodyMedium,
                fontSize: 14,
                color: kAsanaTextSecondary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              greeting,
              style: asanaTextStyle(
                Theme.of(context).textTheme.headlineMedium,
                fontSize: isNarrow ? 22 : 32,
                fontWeight: FontWeight.w700,
                color: kAsanaTextPrimary,
                height: 1.15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 28),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useSingleColumn =
                      constraints.maxWidth <
                      AsanaHomePanel._twoColumnGridMinWidth;
                  final allowCollapse = useSingleColumn;
                  // Narrow: fixed min card height, stack may extend below viewport.
                  // Wide: top four panels use a tall row and the page scrolls;
                  // People keeps its natural height.
                  final fillTopPanels = !useSingleColumn;
                  final layoutKey = useSingleColumn ? 'stack' : 'grid';
                  final createdCard = _HomeTaskCard(
                    key: ValueKey('home-created-$layoutKey'),
                    palette: palette,
                    title: adminViewMode
                        ? 'Incomplete Tasks & Sub-tasks'
                        : "Tasks & Sub-tasks I've created",
                    items: leftItems,
                    onOpenItem: (item) {
                      if (item.isSubtask) {
                        widget.onOpenSubtask?.call(item.id);
                      } else {
                        widget.onOpenTask?.call(item.id);
                      }
                    },
                    expanded: allowCollapse
                        ? (_expanded['created'] ?? true)
                        : true,
                    onToggleExpanded: allowCollapse
                        ? () => _toggleSection('created')
                        : null,
                    fillHeight: fillTopPanels,
                  );
                  final assignedCard = _HomeTaskCard(
                    key: ValueKey('home-assigned-$layoutKey'),
                    palette: palette,
                    title: adminViewMode
                        ? 'Completed Tasks & Sub-tasks'
                        : 'Tasks & Sub-tasks assigned to me',
                    items: rightItems,
                    onOpenItem: (item) {
                      if (item.isSubtask) {
                        widget.onOpenSubtask?.call(item.id);
                      } else {
                        widget.onOpenTask?.call(item.id);
                      }
                    },
                    expanded: allowCollapse
                        ? (_expanded['assigned'] ?? true)
                        : true,
                    onToggleExpanded: allowCollapse
                        ? () => _toggleSection('assigned')
                        : null,
                    fillHeight: fillTopPanels,
                  );
                  final projectsCreatedCard = _HomeNestCard(
                    key: ValueKey('home-nest-created-$layoutKey'),
                    palette: palette,
                    title: adminViewMode
                        ? 'All Projects & Sub-projects'
                        : "Projects & Sub-projects I've created",
                    items: nestCreated,
                    countsFor: (item) => _nestCountsFor(
                      state,
                      item,
                      all,
                      _peopleSubtasksByTaskId,
                    ),
                    progressFor: (item) => item.isSubproject
                        ? null
                        : _progressForProject(item.project!),
                    onOpenItem: (item) {
                      if (item.isSubproject) {
                        widget.onOpenSubproject?.call(
                          item.id,
                          item.subproject!.projectId,
                        );
                      } else {
                        widget.onOpenProject?.call(item.id);
                      }
                    },
                    expanded: allowCollapse
                        ? (_expanded['projectsCreated'] ?? true)
                        : true,
                    onToggleExpanded: allowCollapse
                        ? () => _toggleSection('projectsCreated')
                        : null,
                    fillHeight: fillTopPanels,
                  );
                  final projectsAssignedCard = _HomeNestCard(
                    key: ValueKey('home-nest-assigned-$layoutKey'),
                    palette: palette,
                    title: 'Projects & sub-projects assigned to me',
                    items: nestAssigned,
                    countsFor: (item) => _nestCountsFor(
                      state,
                      item,
                      all,
                      _peopleSubtasksByTaskId,
                    ),
                    progressFor: (item) => item.isSubproject
                        ? null
                        : _progressForProject(item.project!),
                    onOpenItem: (item) {
                      if (item.isSubproject) {
                        widget.onOpenSubproject?.call(
                          item.id,
                          item.subproject!.projectId,
                        );
                      } else {
                        widget.onOpenProject?.call(item.id);
                      }
                    },
                    expanded: allowCollapse
                        ? (_expanded['projectsAssigned'] ?? true)
                        : true,
                    onToggleExpanded: allowCollapse
                        ? () => _toggleSection('projectsAssigned')
                        : null,
                    fillHeight: fillTopPanels,
                  );
                  final peopleCard = _HomePeopleCard(
                    key: ValueKey('home-people-$layoutKey'),
                    palette: palette,
                    rows: people,
                    expanded: allowCollapse
                        ? (_expanded['people'] ?? true)
                        : true,
                    onToggleExpanded: allowCollapse
                        ? () => _toggleSection('people')
                        : null,
                    fillHeight: false,
                  );
                  if (useSingleColumn) {
                    return KeyedSubtree(
                      key: const ValueKey('home-stacked'),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _stackedHomeSections(
                              cards: [
                                createdCard,
                                assignedCard,
                                projectsCreatedCard,
                                projectsAssignedCard,
                                peopleCard,
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final panelRowH = AsanaHomePanel.desktopWorkPanelRowHeight(
                    constraints.maxHeight,
                  );
                  return KeyedSubtree(
                    key: const ValueKey('home-grid'),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: panelRowH,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: createdCard),
                                  const SizedBox(
                                    width: AsanaHomePanel._gridGap,
                                  ),
                                  Expanded(child: assignedCard),
                                ],
                              ),
                            ),
                            const SizedBox(height: AsanaHomePanel._gridGap),
                            SizedBox(
                              height: panelRowH,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: projectsCreatedCard),
                                  const SizedBox(
                                    width: AsanaHomePanel._gridGap,
                                  ),
                                  Expanded(child: projectsAssignedCard),
                                ],
                              ),
                            ),
                            const SizedBox(height: AsanaHomePanel._gridGap),
                            peopleCard,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stackedHomeSections({required List<Widget> cards}) {
    final out = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      if (i > 0) out.add(const SizedBox(height: AsanaHomePanel._gridGap));
      out.add(cards[i]);
    }
    return out;
  }

  void _ensurePeopleSubtasksLoaded(List<Task> tasks) {
    final taskIds =
        tasks.map((t) => t.id.trim()).where((id) => id.isNotEmpty).toList()
          ..sort();
    final key = taskIds.join('|');
    if (key == _peopleSubtaskTaskIdsKey) return;
    _peopleSubtaskTaskIdsKey = key;
    final serial = ++_peopleSubtaskLoadSerial;
    if (taskIds.isEmpty) {
      if (_peopleSubtasksByTaskId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && serial == _peopleSubtaskLoadSerial) {
            setState(() => _peopleSubtasksByTaskId = {});
          }
        });
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final grouped =
          await DatabaseService.fetchSubtasksGroupedForLandingPrefetch(taskIds);
      if (!mounted || serial != _peopleSubtaskLoadSerial) return;
      setState(() => _peopleSubtasksByTaskId = grouped);
    });
  }

  static List<_PersonTaskSummary> _peopleRows(
    AppState state,
    List<Task> tasks,
    Map<String, List<SingularSubtask>> subtasksByTaskId,
    DateTime today,
  ) {
    final rows = <_PersonTaskSummary>[];
    final mine = state.effectiveStaffAppId?.trim();
    final myUuid = state.effectiveStaffUuid?.trim();
    if (state.showAllDataAsAdmin) {
      final staff = List.of(state.assignees)
        ..sort((a, b) => a.name.trim().compareTo(b.name.trim()));
      final seen = <String>{};
      for (final assignee in staff) {
        final appId = assignee.id.trim();
        if (appId.isEmpty || !seen.add(appId)) continue;
        rows.add(
          _PersonTaskSummary(
            name: assignee.name.trim().isNotEmpty
                ? assignee.name.trim()
                : appId,
            taskCounts: _taskCountsForStaff(
              state,
              tasks,
              today,
              appId,
              appId == mine ? myUuid : null,
            ),
            subtaskCounts: _subtaskCountsForStaff(
              state,
              subtasksByTaskId,
              today,
              appId,
              appId == mine ? myUuid : null,
            ),
            isSelf: appId == mine,
          ),
        );
      }
      return rows;
    }
    if (mine != null && mine.isNotEmpty) {
      final me = state.assigneeById(mine);
      rows.add(
        _PersonTaskSummary(
          name: me?.name.trim().isNotEmpty == true ? me!.name.trim() : mine,
          taskCounts: _taskCountsForStaff(state, tasks, today, mine, myUuid),
          subtaskCounts: _subtaskCountsForStaff(
            state,
            subtasksByTaskId,
            today,
            mine,
            myUuid,
          ),
          isSelf: true,
        ),
      );
    }
    final subs = List<String>.from(state.subordinateAppIds)
      ..sort((a, b) {
        final na = state.assigneeById(a)?.name.trim() ?? a;
        final nb = state.assigneeById(b)?.name.trim() ?? b;
        return na.compareTo(nb);
      });
    for (final appId in subs) {
      final a = state.assigneeById(appId);
      String? staffUuid;
      for (final u in state.subordinateStaffUuids) {
        final linked = state.assigneeById(u)?.id;
        if (linked == appId || u == appId) {
          staffUuid = u;
          break;
        }
      }
      rows.add(
        _PersonTaskSummary(
          name: a?.name.trim().isNotEmpty == true ? a!.name.trim() : appId,
          taskCounts: _taskCountsForStaff(
            state,
            tasks,
            today,
            appId,
            staffUuid,
          ),
          subtaskCounts: _subtaskCountsForStaff(
            state,
            subtasksByTaskId,
            today,
            appId,
            staffUuid,
          ),
        ),
      );
    }
    return rows;
  }

  static bool _taskMatchesStaff(
    AppState state,
    Task t,
    String appId,
    String? staffUuid,
  ) {
    final pic = t.pic?.trim();
    if (pic != null && pic.isNotEmpty) {
      if (pic == appId) return true;
      if (staffUuid != null && pic.toLowerCase() == staffUuid.toLowerCase()) {
        return true;
      }
    }
    for (final id in t.assigneeIds) {
      final x = id.trim();
      if (x == appId) return true;
      if (staffUuid != null && x.toLowerCase() == staffUuid.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  static _TaskCounts _taskCountsForStaff(
    AppState state,
    List<Task> tasks,
    DateTime today,
    String appId,
    String? staffUuid,
  ) {
    var overdue = 0;
    var incomplete = 0;
    var completed = 0;
    var upcoming = 0;
    for (final t in tasks) {
      if (!_taskMatchesStaff(state, t, appId, staffUuid)) continue;
      if (_isCompleted(t)) {
        completed++;
        continue;
      }
      final due = _dateOnly(t.endDate);
      final start = _dateOnly(t.startDate);
      if (due != null && due.isBefore(today)) {
        overdue++;
      } else if (start != null && start.isAfter(today)) {
        upcoming++;
      } else {
        incomplete++;
      }
    }
    return _TaskCounts(
      overdue: overdue,
      incomplete: incomplete,
      completed: completed,
      upcoming: upcoming,
    );
  }

  static _TaskCounts _subtaskCountsForStaff(
    AppState state,
    Map<String, List<SingularSubtask>> subtasksByTaskId,
    DateTime today,
    String appId,
    String? staffUuid,
  ) {
    var overdue = 0;
    var incomplete = 0;
    var completed = 0;
    var upcoming = 0;
    for (final subtasks in subtasksByTaskId.values) {
      for (final s in subtasks) {
        if (!_subtaskMatchesStaff(state, s, appId, staffUuid)) continue;
        if (_subtaskCompleted(s)) {
          completed++;
          continue;
        }
        final due = _dateOnly(s.dueDate);
        final start = _dateOnly(s.startDate);
        if (due != null && due.isBefore(today)) {
          overdue++;
        } else if (start != null && start.isAfter(today)) {
          upcoming++;
        } else {
          incomplete++;
        }
      }
    }
    return _TaskCounts(
      overdue: overdue,
      incomplete: incomplete,
      completed: completed,
      upcoming: upcoming,
    );
  }

  static bool _subtaskMatchesStaff(
    AppState state,
    SingularSubtask s,
    String appId,
    String? staffUuid,
  ) {
    final pic = s.pic?.trim();
    if (pic != null && pic.isNotEmpty) {
      if (pic == appId) return true;
      if (staffUuid != null && pic.toLowerCase() == staffUuid.toLowerCase()) {
        return true;
      }
    }
    for (final id in s.assigneeIds) {
      final x = id.trim();
      if (x == appId) return true;
      if (staffUuid != null && x.toLowerCase() == staffUuid.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  static bool _subtaskCompleted(SingularSubtask s) {
    final status = s.status.trim().toLowerCase();
    return status == 'completed' || status == 'complete';
  }

  static bool _isCompleted(Task t) {
    final s = t.dbStatus?.trim().toLowerCase() ?? '';
    return s == 'completed' || s == 'complete' || t.status == TaskStatus.done;
  }

  static bool _isIncomplete(Task t) {
    final s = t.dbStatus?.trim().toLowerCase() ?? '';
    return s == 'incomplete' || (s.isEmpty && t.status != TaskStatus.done);
  }

  static DateTime? _dateOnly(DateTime? d) {
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }
}

class _TaskCounts {
  const _TaskCounts({
    required this.overdue,
    required this.incomplete,
    required this.completed,
    required this.upcoming,
  });

  final int overdue;
  final int incomplete;
  final int completed;
  final int upcoming;
}

class _PersonTaskSummary {
  const _PersonTaskSummary({
    required this.name,
    required this.taskCounts,
    required this.subtaskCounts,
    this.isSelf = false,
  });

  final String name;
  final _TaskCounts taskCounts;
  final _TaskCounts subtaskCounts;
  final bool isSelf;
}

String _homeLabeledMetaLine({required String label, required String value}) {
  final v = value.trim().isEmpty ? '—' : value.trim();
  return '$label: $v';
}

String _homePeopleMetaLine({
  required String creator,
  required String pic,
  required String assignee,
}) {
  return [
    _homeLabeledMetaLine(label: 'Creator', value: creator),
    _homeLabeledMetaLine(label: 'PIC', value: pic),
    _homeLabeledMetaLine(label: 'Assignee', value: assignee),
  ].join(' · ');
}

String _homeAssigneeNames(AppState state, List<String> ids) {
  final parts = <String>[];
  for (final raw in ids) {
    final name = _AsanaHomePanelState._picLine(state, raw);
    if (name != '—') parts.add(name);
  }
  return parts.isEmpty ? '—' : parts.join(', ');
}

String _homeCreatorName({required String? storedName, required String? fallback}) {
  final n = storedName?.trim();
  if (n != null && n.isNotEmpty) return n;
  final f = fallback?.trim();
  if (f != null && f.isNotEmpty) return f;
  return '—';
}

String _homeCountPhrase(int n, String singular, String plural) {
  return '$n ${n == 1 ? singular : plural}';
}

String? _homeDueUrgencyLabel(BuildContext context, _HomeWorkItem item) {
  final state = context.read<AppState>();
  final status = item.isSubtask
      ? AsanaTaskFilter.subtaskDisplayStatus(state, item.task, item.subtask!)
      : AsanaTaskFilter.taskDisplayStatus(state, item.task);
  return asanaTaskViewDueLabel(
    due: item.dueDate,
    status: status,
    submission: item.submission,
  );
}

Widget _homeListViewport({required double height, required Widget child}) {
  return SizedBox(height: height, child: child);
}

class _HomeCardShell extends StatelessWidget {
  const _HomeCardShell({
    required this.palette,
    required this.title,
    required this.child,
    this.expanded = true,
    this.onToggleExpanded,
    this.fillHeight = false,
  });

  final AsanaLandingPalette palette;
  final String title;
  final Widget child;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final collapsible = onToggleExpanded != null;
    final titleStyle = asanaTextStyle(
      Theme.of(context).textTheme.titleLarge,
      fontSize: AsanaHomePanel._panelTitleFontSize,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
      height: 1.2,
    );

    if (!expanded) {
      return Material(
        color: palette.listSurface,
        borderRadius: BorderRadius.circular(AsanaHomePanel._cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: InkWell(
            onTap: collapsible ? onToggleExpanded : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: titleStyle)),
                  if (collapsible)
                    Icon(
                      Icons.expand_more,
                      size: 22,
                      color: kAsanaTextSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget buildShell(BoxConstraints outer) {
      Widget body = child;
      if (fillHeight && outer.maxHeight.isFinite) {
        final bodyHeight =
            (outer.maxHeight - AsanaHomePanel._homeShellHeaderHeight)
                .clamp(0, double.infinity)
                .toDouble();
        body = SizedBox(
          height: bodyHeight,
          width: double.infinity,
          child: child,
        );
      }
      return Material(
        color: palette.listSurface,
        borderRadius: BorderRadius.circular(AsanaHomePanel._cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: collapsible ? onToggleExpanded : null,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: Text(title, style: titleStyle)),
                      if (collapsible)
                        Icon(
                          Icons.expand_less,
                          size: 22,
                          color: kAsanaTextSecondary,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              body,
            ],
          ),
        ),
      );
    }

    final shell = fillHeight
        ? SizedBox.expand(
            child: LayoutBuilder(builder: (_, c) => buildShell(c)),
          )
        : LayoutBuilder(builder: (_, c) => buildShell(c));

    if (fillHeight) return shell;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AsanaHomePanel.homeCardMinHeight,
      ),
      child: shell,
    );
  }
}

class _HomeWorkItem {
  const _HomeWorkItem.task(this.task) : subtask = null;
  const _HomeWorkItem.subtask(this.subtask, {required Task parent})
    : task = parent;

  final Task task;
  final SingularSubtask? subtask;

  bool get isSubtask => subtask != null;
  String get id => isSubtask ? subtask!.id : task.id;
  String get name {
    if (isSubtask) {
      final n = subtask!.subtaskName.trim();
      return n.isEmpty ? '(Unnamed sub-task)' : n;
    }
    final n = task.name.trim();
    return n.isEmpty ? '(Unnamed task)' : n;
  }

  String? get pic => isSubtask ? subtask!.pic : task.pic;
  DateTime? get dueDate => isSubtask ? subtask!.dueDate : task.endDate;
  String? get submission => isSubtask ? subtask!.submission : task.submission;
  String? get creatorName =>
      isSubtask ? subtask!.createByStaffName : task.createByStaffName;
  List<String> get assigneeIds =>
      isSubtask ? subtask!.assigneeIds : task.assigneeIds;
}

class _HomeTaskCard extends StatelessWidget {
  const _HomeTaskCard({
    super.key,
    required this.palette,
    required this.title,
    required this.items,
    this.onOpenItem,
    this.expanded = true,
    this.onToggleExpanded,
    this.fillHeight = false,
  });

  final AsanaLandingPalette palette;
  final String title;
  final List<_HomeWorkItem> items;
  final void Function(_HomeWorkItem item)? onOpenItem;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return _HomeCardShell(
      palette: palette,
      title: title,
      expanded: expanded,
      onToggleExpanded: onToggleExpanded,
      fillHeight: fillHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final listH = AsanaHomePanel.listViewportHeight(
            maxHeight: constraints.maxHeight,
            fillHeight: fillHeight,
            chromeAboveList: 1,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(height: 1, color: Colors.grey.shade300),
              _homeListViewport(
                height: listH,
                child: _homeTaskListBody(
                  context: context,
                  items: items,
                  onOpenItem: onOpenItem,
                  palette: palette,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _homeTaskListBody({
  required BuildContext context,
  required List<_HomeWorkItem> items,
  required void Function(_HomeWorkItem item)? onOpenItem,
  required AsanaLandingPalette palette,
}) {
  if (items.isEmpty) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'No items to show.',
          style: asanaTableRowValueStyle(context),
        ),
      ),
    );
  }

  return ListView.separated(
    primary: false,
    itemCount: items.length,
    separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
    itemBuilder: (context, index) {
      final item = items[index];
      return _HomeTaskItemRow(
        item: item,
        rowBackground: item.isSubtask ? palette.tableColors.subtaskRow : null,
        onTap: onOpenItem == null ? null : () => onOpenItem(item),
      );
    },
  );
}

class _HomeTaskItemRow extends StatelessWidget {
  const _HomeTaskItemRow({
    required this.item,
    this.rowBackground,
    this.onTap,
  });

  final _HomeWorkItem item;
  final Color? rowBackground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final nameStyle = asanaTableRowNameStyle(context);
    final metaStyle = asanaTableRowValueStyle(context);
    final status = item.isSubtask
        ? AsanaTaskFilter.subtaskDisplayStatus(state, item.task, item.subtask!)
        : AsanaTaskFilter.taskDisplayStatus(state, item.task);
    final dueLabel = _homeDueUrgencyLabel(context, item);
    final peopleLine = _homePeopleMetaLine(
      creator: _homeCreatorName(storedName: item.creatorName, fallback: null),
      pic: _AsanaHomePanelState._picLine(state, item.pic),
      assignee: _homeAssigneeNames(state, item.assigneeIds),
    );

    return Material(
      color: rowBackground ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AsanaHomePanel._homeWorkNameInset,
            8,
            4,
            8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AsanaRowTypeLetter(
                    letter: item.isSubtask ? 'ST' : 'T',
                    completed: status.trim().toLowerCase() == 'completed',
                    status: status,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.name,
                      style: nameStyle,
                      maxLines: 3,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                peopleLine,
                style: metaStyle,
                maxLines: 4,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AsanaStatusChip(status: status, preserveFullLabel: true),
                  AsanaSubmissionChip(
                    submission: item.submission,
                    preserveFullLabel: true,
                  ),
                  Text(
                    _homeLabeledMetaLine(
                      label: 'Due',
                      value: _formatDueDate(item.dueDate),
                    ),
                    style: metaStyle,
                  ),
                  if (dueLabel != null) AsanaTaskViewDueLabel(label: dueLabel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePeopleCard extends StatelessWidget {
  const _HomePeopleCard({
    super.key,
    required this.palette,
    required this.rows,
    this.expanded = true,
    this.onToggleExpanded,
    this.fillHeight = false,
  });

  final AsanaLandingPalette palette;
  final List<_PersonTaskSummary> rows;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return _HomeCardShell(
      palette: palette,
      title: 'People',
      expanded: expanded,
      onToggleExpanded: onToggleExpanded,
      fillHeight: fillHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final list = rows.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    'No people to show.',
                    style: asanaTableRowValueStyle(context),
                  ),
                )
              : ListView.separated(
                  primary: false,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (context, index) {
                    return _HomePeopleRow(
                      palette: palette,
                      summary: rows[index],
                      useMetricAcronym: false,
                    );
                  },
                );
          final listH = AsanaHomePanel.listViewportHeight(
            maxHeight: constraints.maxHeight,
            fillHeight: fillHeight,
            chromeAboveList: 0,
          );
          return _homeListViewport(height: listH, child: list);
        },
      ),
    );
  }
}

class _HomePeopleRow extends StatelessWidget {
  const _HomePeopleRow({
    required this.palette,
    required this.summary,
    required this.useMetricAcronym,
  });

  final AsanaLandingPalette palette;
  final _PersonTaskSummary summary;
  final bool useMetricAcronym;

  @override
  Widget build(BuildContext context) {
    final nameStyle = asanaTableRowNameStyle(
      context,
    )?.copyWith(fontWeight: summary.isSelf ? FontWeight.w700 : FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              summary.name,
              style: nameStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _countBlock('Tasks', summary.taskCounts, forSubtasks: false),
                const SizedBox(width: 10),
                _countBlock(
                  'Sub-tasks',
                  summary.subtaskCounts,
                  forSubtasks: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countBlock(
    String heading,
    _TaskCounts c, {
    required bool forSubtasks,
  }) {
    Widget chip(int count, String label, String metric) {
      return _HomeMetricChip(
        palette: palette,
        count: count,
        label: label,
        metric: metric,
        useAcronym: useMetricAcronym,
        forSubtasks: forSubtasks,
      );
    }

    Widget pair(Widget left, Widget right) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [left, const SizedBox(width: 6), right],
      );
    }

    const headingColor = kAsanaTextSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          heading,
          style: asanaTextStyle(
            const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            color: headingColor,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        pair(
          chip(c.overdue, 'overdue', 'overdue'),
          chip(c.incomplete, 'ongoing', 'ongoing'),
        ),
        const SizedBox(height: 6),
        pair(
          chip(c.completed, 'completed', 'completed'),
          chip(c.upcoming, 'upcoming', 'upcoming'),
        ),
      ],
    );
  }
}

class _HomeMetricChip extends StatelessWidget {
  const _HomeMetricChip({
    required this.palette,
    required this.count,
    required this.label,
    required this.metric,
    this.useAcronym = false,
    this.forSubtasks = false,
  });

  final AsanaLandingPalette palette;
  final int count;
  final String label;
  final String metric;
  final bool useAcronym;
  final bool forSubtasks;

  static String _displayLabel(String label, bool acronym) {
    if (!acronym) return label;
    switch (label) {
      case 'overdue':
        return 'OVD';
      case 'ongoing':
        return 'ONG';
      case 'completed':
        return 'CMP';
      case 'upcoming':
        return 'UPC';
      default:
        return label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = palette.homeMetricStyle(metric, subtask: forSubtasks);
    final shown = _displayLabel(label, useAcronym);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count $shown',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: asanaTextStyle(
          Theme.of(context).textTheme.bodySmall,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.2,
        ),
      ),
    );
    if (!useAcronym) return chip;
    return Tooltip(
      message: '$count $label',
      waitDuration: const Duration(milliseconds: 400),
      child: chip,
    );
  }
}

class _HomeNestCounts {
  const _HomeNestCounts({
    required this.subprojects,
    required this.tasks,
    required this.subtasks,
  });

  final int subprojects;
  final int tasks;
  final int subtasks;

  String summary({required bool isSubproject}) {
    return [
      if (!isSubproject)
        _homeCountPhrase(subprojects, 'sub-project', 'sub-projects'),
      _homeCountPhrase(tasks, 'task', 'tasks'),
      _homeCountPhrase(subtasks, 'sub-task', 'sub-tasks'),
    ].join(' · ');
  }
}

class _HomeNestItem {
  const _HomeNestItem.project(this.project) : subproject = null;
  const _HomeNestItem.subproject(this.subproject) : project = null;

  final ProjectRecord? project;
  final SubprojectRecord? subproject;

  bool get isSubproject => subproject != null;
  String get id => isSubproject ? subproject!.id : project!.id;
  String get name {
    if (isSubproject) {
      final n = subproject!.name.trim();
      return n.isEmpty ? '(Unnamed sub-project)' : n;
    }
    final n = project!.name.trim();
    return n.isEmpty ? '(Unnamed project)' : n;
  }

  String get status =>
      isSubproject ? subproject!.status : project!.status;
  String get letter => isSubproject ? 'SP' : 'P';
}

class _HomeNestCard extends StatelessWidget {
  const _HomeNestCard({
    super.key,
    required this.palette,
    required this.title,
    required this.items,
    required this.countsFor,
    required this.progressFor,
    this.onOpenItem,
    this.expanded = true,
    this.onToggleExpanded,
    this.fillHeight = false,
  });

  final AsanaLandingPalette palette;
  final String title;
  final List<_HomeNestItem> items;
  final _HomeNestCounts Function(_HomeNestItem item) countsFor;
  final int? Function(_HomeNestItem item) progressFor;
  final void Function(_HomeNestItem item)? onOpenItem;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return _HomeCardShell(
      palette: palette,
      title: title,
      expanded: expanded,
      onToggleExpanded: onToggleExpanded,
      fillHeight: fillHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final listH = AsanaHomePanel.listViewportHeight(
            maxHeight: constraints.maxHeight,
            fillHeight: fillHeight,
            chromeAboveList: 1,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(height: 1, color: Colors.grey.shade300),
              _homeListViewport(
                height: listH,
                child: items.isEmpty
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'No items to show.',
                            style: asanaTableRowValueStyle(context),
                          ),
                        ),
                      )
                    : ListView.separated(
                        primary: false,
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _HomeNestItemRow(
                            item: item,
                            counts: countsFor(item),
                            progressPercent: progressFor(item),
                            rowBackground: item.isSubproject
                                ? palette.tableColors.subtaskRow
                                : null,
                            onTap: onOpenItem == null
                                ? null
                                : () => onOpenItem!(item),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HomeNestItemRow extends StatelessWidget {
  const _HomeNestItemRow({
    required this.item,
    required this.counts,
    this.progressPercent,
    this.rowBackground,
    this.onTap,
  });

  final _HomeNestItem item;
  final _HomeNestCounts counts;
  final int? progressPercent;
  final Color? rowBackground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final completed = item.status.trim().toLowerCase() == 'completed';
    final nameStyle = asanaTableRowNameStyle(context, completed: completed);
    final metaStyle = asanaTableRowValueStyle(context, completed: completed);
    final creator = item.isSubproject
        ? AsanaProjectFilter.subprojectCreatorLine(item.subproject!, state)
        : AsanaProjectFilter.creatorLine(item.project!, state);
    final pic = item.isSubproject
        ? AsanaProjectFilter.subprojectPicLine(item.subproject!, state)
        : AsanaProjectFilter.picLine(item.project!, state);
    final assignee = item.isSubproject
        ? AsanaProjectFilter.subprojectAssigneesLine(item.subproject!, state)
        : AsanaProjectFilter.assigneesLine(item.project!, state);
    final peopleLine = _homePeopleMetaLine(
      creator: creator,
      pic: pic,
      assignee: assignee,
    );

    return Material(
      color: rowBackground ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AsanaHomePanel._homeWorkNameInset,
            8,
            4,
            8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AsanaRowTypeLetter(
                    letter: item.letter,
                    completed: completed,
                    status: item.status,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.name,
                      style: nameStyle,
                      maxLines: 3,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (progressPercent != null) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 84,
                      child: _HomeProjectProgress(percent: progressPercent!),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                peopleLine,
                style: metaStyle,
                maxLines: 4,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AsanaStatusChip(
                    status: item.status,
                    preserveFullLabel: true,
                  ),
                  Text(
                    counts.summary(isSubproject: item.isSubproject),
                    style: metaStyle,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeProjectProgress extends StatelessWidget {
  const _HomeProjectProgress({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final color = percent >= 100
        ? const Color(0xFF1B7A4E)
        : percent <= 0
        ? kAsanaTextSecondary
        : Theme.of(context).colorScheme.primary;
    final fill = (percent.clamp(0, 100)) / 100;
    return Row(
      children: [
        Text(
          '$percent%',
          style: asanaTextStyle(
            Theme.of(context).textTheme.labelSmall,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
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
