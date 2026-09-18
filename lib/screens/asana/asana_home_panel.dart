import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../commencement_status.dart';
import '../../models/project_record.dart';
import '../../models/singular_subtask.dart';
import '../../models/task.dart';
import '../../services/database_service.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_project_filter.dart';
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
  });

  final AsanaLandingPalette palette;
  final String searchQuery;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;
  final void Function(String projectId)? onOpenProject;

  @override
  State<AsanaHomePanel> createState() => _AsanaHomePanelState();

  static const double _cardRadius = 16;
  static const double _gridGap = 12;
  static const double _panelTitleFontSize = 22;

  /// Home content width at or above this keeps the 2×2 card grid.
  static const double _twoColumnGridMinWidth = 1000;

  /// Below this card width, task/project lists use two-line labeled rows.
  static const double _homeCompactMaxWidth = 540;
  static const int _minVisibleTaskRows = 5;
  static const double _taskRowHeight = 44;
  static const double _taskRowCompactHeight = 64;
  static const double _homeWorkNameInset = 10;
  static const double _homeDueColWidth = 76;
  static const double _homePicColWidth = 118;
  static const double _homePeopleNameMinWidth = _homePicColWidth;
  static const double _homeSubmissionColWidth = 92;
  static const double _homeStatusColWidth = 100;
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
  static const double _homeTaskTableChromeAboveList =
      _taskRowHeight + 8 + _rowDividerHeight;

  static bool homeUseCompact(double cardWidth) =>
      cardWidth > 0 && cardWidth < _homeCompactMaxWidth;

  /// Title block + top/bottom padding in [_HomeCardShell] (excludes list body).
  static const double _homeShellHeaderHeight =
      18 + _panelTitleFontSize * 1.2 + 4 + 12 + 12;

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
    'people': true,
    'projects': true,
  };
  Map<String, List<SingularSubtask>> _peopleSubtasksByTaskId = {};
  String _peopleSubtaskTaskIdsKey = '';
  int _peopleSubtaskLoadSerial = 0;

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
    out.sort(_sortWorkByDueDescending);
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
    out.sort(_sortWorkByDueDescending);
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
          !_hideFromLeftHomePanel(
            commencementStatus: t.commencementStatus,
            submission: t.submission,
            workStatus: t.dbStatus,
          )) {
        out.add(_HomeWorkItem.task(t));
      }
      for (final s in subtasksByTaskId[t.id] ?? const <SingularSubtask>[]) {
        if (s.isDeleted) continue;
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
    out.sort(_sortWorkByDueDescending);
    return out;
  }

  static List<_HomeWorkItem> _userAssignedWorkItems(
    AppState state,
    List<Task> tasks,
    Map<String, List<SingularSubtask>> subtasksByTaskId,
  ) {
    final out = <_HomeWorkItem>[];
    for (final t in tasks) {
      if (AsanaTaskFilter.taskAssignedToCurrentUser(state, t)) {
        out.add(_HomeWorkItem.task(t));
      }
      for (final s in subtasksByTaskId[t.id] ?? const <SingularSubtask>[]) {
        if (s.isDeleted) continue;
        if (_subtaskMatchesStaff(
          state,
          s,
          state.effectiveStaffAppId?.trim() ?? '',
          state.effectiveStaffUuid?.trim(),
        )) {
          out.add(_HomeWorkItem.subtask(s, parent: t));
        }
      }
    }
    out.sort(_sortWorkByDueDescending);
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

  static int _sortWorkByDueDescending(_HomeWorkItem a, _HomeWorkItem b) {
    final ae = a.dueDate;
    final be = b.dueDate;
    if (ae == null && be == null) return a.name.compareTo(b.name);
    if (ae == null) return 1;
    if (be == null) return -1;
    final c = be.compareTo(ae);
    return c != 0 ? c : a.name.compareTo(b.name);
  }

  static List<ProjectRecord> _filterProjectsBySearch(
    AppState state,
    List<ProjectRecord> projects,
    List<String> tokens,
  ) {
    if (tokens.isEmpty) return projects;
    return projects
        .where((p) => AsanaProjectFilter.projectSearchMatches(state, p, tokens))
        .toList();
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

    final projects = state.projects;
    final projectsCreated = adminViewMode
        ? (projects.toList()..sort(_sortProjectsByDue))
        : (projects
              .where(
                (p) => AsanaProjectFilter.projectCreatedByCurrentUser(state, p),
              )
              .toList()
            ..sort(_sortProjectsByDue));
    final projectsAssigned = adminViewMode
        ? <ProjectRecord>[]
        : (projects
              .where(
                (p) =>
                    AsanaProjectFilter.projectAssignedToCurrentUser(state, p),
              )
              .toList()
            ..sort(_sortProjectsByDue));
    final visibleProjectsCreated = _filterProjectsBySearch(
      state,
      projectsCreated,
      searchTokens,
    );
    final visibleProjectsAssigned = _filterProjectsBySearch(
      state,
      projectsAssigned,
      searchTokens,
    );

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
                  // Wide: cards fill grid cells (min height still enforced).
                  final fillHeight = !useSingleColumn;
                  final layoutKey = useSingleColumn ? 'stack' : 'grid';
                  final createdCard = _HomeTaskCard(
                    key: ValueKey('home-created-$layoutKey'),
                    palette: palette,
                    title: adminViewMode
                        ? 'Incomplete Tasks & Sub-tasks'
                        : "Tasks & Sub-tasks I've created",
                    items: leftItems,
                    nameHeader: 'Name',
                    middleHeader: 'PIC',
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
                    fillHeight: fillHeight,
                  );
                  final assignedCard = _HomeTaskCard(
                    key: ValueKey('home-assigned-$layoutKey'),
                    palette: palette,
                    title: adminViewMode
                        ? 'Completed Tasks & Sub-tasks'
                        : 'Tasks & Sub-tasks assigned to me',
                    items: rightItems,
                    nameHeader: 'Name',
                    middleHeader: adminViewMode ? 'PIC' : 'Creator',
                    middleOverride: adminViewMode
                        ? null
                        : (item) {
                            final name = item.isSubtask
                                ? item.subtask?.createByStaffName
                                : item.task.createByStaffName;
                            final t = name?.trim();
                            return (t != null && t.isNotEmpty) ? t : '—';
                          },
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
                    fillHeight: fillHeight,
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
                    fillHeight: fillHeight,
                  );
                  final projectsCard = _HomeProjectsCard(
                    key: ValueKey('home-projects-$layoutKey'),
                    palette: palette,
                    created: visibleProjectsCreated,
                    assigned: visibleProjectsAssigned,
                    adminViewMode: adminViewMode,
                    onOpenProject: widget.onOpenProject,
                    expanded: allowCollapse
                        ? (_expanded['projects'] ?? true)
                        : true,
                    onToggleExpanded: allowCollapse
                        ? () => _toggleSection('projects')
                        : null,
                    fillHeight: fillHeight,
                  );

                  if (useSingleColumn) {
                    // Cards keep min height; stack may extend below viewport (clip, no page scroll).
                    return KeyedSubtree(
                      key: const ValueKey('home-stacked'),
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _stackedHomeSections(
                                  cards: [
                                    createdCard,
                                    assignedCard,
                                    peopleCard,
                                    projectsCard,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return KeyedSubtree(
                    key: const ValueKey('home-grid'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: createdCard),
                              const SizedBox(width: AsanaHomePanel._gridGap),
                              Expanded(child: assignedCard),
                            ],
                          ),
                        ),
                        const SizedBox(height: AsanaHomePanel._gridGap),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: peopleCard),
                              const SizedBox(width: AsanaHomePanel._gridGap),
                              Expanded(child: projectsCard),
                            ],
                          ),
                        ),
                      ],
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

  static int _sortProjectsByDue(ProjectRecord a, ProjectRecord b) {
    final ae = a.endDate;
    final be = b.endDate;
    if (ae == null && be == null) return a.name.compareTo(b.name);
    if (ae == null) return 1;
    if (be == null) return -1;
    final c = ae.compareTo(be);
    return c != 0 ? c : a.name.compareTo(b.name);
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

/// Single-line table cell with fixed width (headers and values align).
Widget _homeFixedCell({
  required double width,
  required Widget child,
  double height = AsanaHomePanel._taskRowHeight,
}) {
  return SizedBox(
    width: width,
    height: height,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );
}

String _homeLabeledMetaLine({required String label, required String value}) {
  final v = value.trim().isEmpty ? '—' : value.trim();
  return '$label: $v';
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
}

class _HomeTaskCard extends StatelessWidget {
  const _HomeTaskCard({
    super.key,
    required this.palette,
    required this.title,
    required this.items,
    required this.middleHeader,
    this.nameHeader = 'Task Name',
    this.middleOverride,
    this.onOpenItem,
    this.expanded = true,
    this.onToggleExpanded,
    this.fillHeight = false,
  });

  final AsanaLandingPalette palette;
  final String title;
  final List<_HomeWorkItem> items;
  final String nameHeader;
  final String middleHeader;
  final String Function(_HomeWorkItem item)? middleOverride;
  final void Function(_HomeWorkItem item)? onOpenItem;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final bool fillHeight;

  String _middleFor(BuildContext context, _HomeWorkItem item) {
    if (middleOverride != null) return middleOverride!(item);
    return _AsanaHomePanelState._picLine(context.read<AppState>(), item.pic);
  }

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
          final cardWidth = constraints.maxWidth;
          final compact = AsanaHomePanel.homeUseCompact(cardWidth);
          final listH = AsanaHomePanel.listViewportHeight(
            maxHeight: constraints.maxHeight,
            fillHeight: fillHeight,
            chromeAboveList: compact
                ? 1
                : AsanaHomePanel._homeTaskTableChromeAboveList,
          );
          if (compact) {
            return _HomeTaskCompactList(
              items: items,
              middleHeader: middleHeader,
              middleValue: _middleFor,
              onOpenItem: onOpenItem,
              listHeight: listH,
              palette: palette,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _HomeTaskTableHeader(
                nameHeader: nameHeader,
                middleHeader: middleHeader,
              ),
              Divider(height: 1, color: Colors.grey.shade300),
              _homeListViewport(
                height: listH,
                child: _homeTaskListBody(
                  context: context,
                  items: items,
                  middleHeader: middleHeader,
                  middleValue: _middleFor,
                  onOpenItem: onOpenItem,
                  compact: false,
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
  required String Function(BuildContext context, _HomeWorkItem item)
  middleValue,
  required void Function(_HomeWorkItem item)? onOpenItem,
  required bool compact,
  required String middleHeader,
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

  Widget rowAt(int index) {
    final item = items[index];
    final rowBg = item.isSubtask ? palette.tableColors.subtaskRow : null;
    if (compact) {
      return _HomeTaskCompactRow(
        item: item,
        middleHeader: middleHeader,
        middle: middleValue(context, item),
        rowBackground: rowBg,
        onTap: onOpenItem == null ? null : () => onOpenItem(item),
      );
    }
    return _HomeTaskRow(
      item: item,
      middle: middleValue(context, item),
      rowBackground: rowBg,
      onTap: onOpenItem == null ? null : () => onOpenItem(item),
    );
  }

  return ListView.separated(
    primary: false,
    itemCount: items.length,
    separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
    itemBuilder: (context, index) => rowAt(index),
  );
}

class _HomeTaskCompactList extends StatelessWidget {
  const _HomeTaskCompactList({
    required this.items,
    required this.middleHeader,
    required this.middleValue,
    required this.listHeight,
    required this.palette,
    this.onOpenItem,
  });

  final List<_HomeWorkItem> items;
  final String middleHeader;
  final String Function(BuildContext context, _HomeWorkItem item) middleValue;
  final double listHeight;
  final AsanaLandingPalette palette;
  final void Function(_HomeWorkItem item)? onOpenItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: Colors.grey.shade300),
        _homeListViewport(
          height: listHeight,
          child: _homeTaskListBody(
            context: context,
            items: items,
            middleHeader: middleHeader,
            middleValue: middleValue,
            onOpenItem: onOpenItem,
            compact: true,
            palette: palette,
          ),
        ),
      ],
    );
  }
}

class _HomeTaskTableHeader extends StatelessWidget {
  const _HomeTaskTableHeader({
    required this.middleHeader,
    this.nameHeader = 'Task Name',
  });

  final String nameHeader;
  final String middleHeader;

  @override
  Widget build(BuildContext context) {
    final style = asanaTableHeaderStyle(context);
    const headerH = AsanaHomePanel._taskRowHeight;
    return Padding(
      padding: const EdgeInsets.only(
        left: AsanaHomePanel._homeWorkNameInset,
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SizedBox(
              height: headerH,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(nameHeader, style: style),
              ),
            ),
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homePicColWidth,
            label: middleHeader,
            style: style,
            rowHeight: headerH,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homeDueColWidth,
            label: 'Due Date',
            style: style,
            rowHeight: headerH,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homeSubmissionColWidth,
            label: 'Submission',
            style: style,
            rowHeight: headerH,
          ),
        ],
      ),
    );
  }
}

class _HomeTaskRow extends StatelessWidget {
  const _HomeTaskRow({
    required this.item,
    required this.middle,
    this.rowBackground,
    this.onTap,
  });

  final _HomeWorkItem item;
  final String middle;
  final Color? rowBackground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final valueStyle = asanaTableRowValueStyle(context);
    final nameStyle = asanaTableRowNameStyle(context);

    return Material(
      color: rowBackground ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: AsanaHomePanel._taskRowHeight,
          child: Padding(
            padding: const EdgeInsets.only(
              left: AsanaHomePanel._homeWorkNameInset,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: nameStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                _homeFixedCell(
                  width: AsanaHomePanel._homePicColWidth,
                  child: Text(
                    middle,
                    style: valueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                _homeFixedCell(
                  width: AsanaHomePanel._homeDueColWidth,
                  child: Text(
                    _formatDueDate(item.dueDate),
                    style: valueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                _homeFixedCell(
                  width: AsanaHomePanel._homeSubmissionColWidth,
                  child: AsanaSubmissionChip(
                    submission: item.submission,
                    preserveFullLabel: true,
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

/// Two-line row: task name, then `PIC: … · Due Date: …` + submission chip.
class _HomeTaskCompactRow extends StatelessWidget {
  const _HomeTaskCompactRow({
    required this.item,
    required this.middleHeader,
    required this.middle,
    this.rowBackground,
    this.onTap,
  });

  final _HomeWorkItem item;
  final String middleHeader;
  final String middle;
  final Color? rowBackground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final nameStyle = asanaTableRowNameStyle(context);
    final metaStyle = asanaTableRowValueStyle(context);
    final metaLine = [
      _homeLabeledMetaLine(label: middleHeader, value: middle),
      _homeLabeledMetaLine(label: 'Due', value: _formatDueDate(item.dueDate)),
    ].join(' · ');

    return Material(
      color: rowBackground ?? Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: AsanaHomePanel._taskRowCompactHeight,
          child: Padding(
            padding: const EdgeInsets.only(
              left: AsanaHomePanel._homeWorkNameInset,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.name,
                  style: nameStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        metaLine,
                        style: metaStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AsanaSubmissionChip(
                      submission: item.submission,
                      preserveFullLabel: true,
                    ),
                  ],
                ),
              ],
            ),
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

class _HomeProjectsCard extends StatelessWidget {
  const _HomeProjectsCard({
    super.key,
    required this.palette,
    required this.created,
    required this.assigned,
    this.adminViewMode = false,
    this.onOpenProject,
    this.expanded = true,
    this.onToggleExpanded,
    this.fillHeight = false,
  });

  final AsanaLandingPalette palette;
  final List<ProjectRecord> created;
  final List<ProjectRecord> assigned;
  final bool adminViewMode;
  final void Function(String projectId)? onOpenProject;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final bool fillHeight;

  List<Widget> _projectSection({
    required BuildContext context,
    required AppState state,
    required bool compact,
    required String bannerTitle,
    required List<ProjectRecord> projects,
  }) {
    if (projects.isEmpty) return [];
    return [
      _HomeSectionBanner(palette: palette, title: bannerTitle),
      if (!compact) const _HomeProjectTableHeader(),
      ...projects.map(
        (p) => compact
            ? _HomeProjectCompactRow(
                project: p,
                appState: state,
                onTap: onOpenProject == null
                    ? null
                    : () => onOpenProject!(p.id),
              )
            : _HomeProjectRow(
                project: p,
                appState: state,
                onTap: onOpenProject == null
                    ? null
                    : () => onOpenProject!(p.id),
              ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return _HomeCardShell(
      palette: palette,
      title: 'Projects',
      expanded: expanded,
      onToggleExpanded: onToggleExpanded,
      fillHeight: fillHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final listH = AsanaHomePanel.listViewportHeight(
            maxHeight: constraints.maxHeight,
            fillHeight: fillHeight,
            chromeAboveList: 0,
          );
          if (created.isEmpty && assigned.isEmpty) {
            return _homeListViewport(
              height: listH,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  'No projects to show.',
                  style: asanaTableRowValueStyle(context),
                ),
              ),
            );
          }
          final compact = AsanaHomePanel.homeUseCompact(constraints.maxWidth);
          final children = <Widget>[
            ..._projectSection(
              context: context,
              state: state,
              compact: compact,
              bannerTitle: adminViewMode
                  ? 'All active projects'
                  : "Projects I've created",
              projects: created,
            ),
            if (created.isNotEmpty && assigned.isNotEmpty)
              const SizedBox(height: 12),
            ..._projectSection(
              context: context,
              state: state,
              compact: compact,
              bannerTitle: 'Projects assigned to me',
              projects: assigned,
            ),
          ];

          return _homeListViewport(
            height: listH,
            child: ListView(primary: false, children: children),
          );
        },
      ),
    );
  }
}

class _HomeSectionBanner extends StatelessWidget {
  const _HomeSectionBanner({required this.palette, required this.title});

  final AsanaLandingPalette palette;
  final String title;

  @override
  Widget build(BuildContext context) {
    final bg = palette.darkChrome
        ? palette.selectedNav
        : Color.alphaBlend(
            palette.accent.withValues(alpha: 0.14),
            palette.listSurface,
          );
    final fg = palette.darkChrome ? palette.onSidebar : palette.accent;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        style: asanaTextStyle(
          Theme.of(context).textTheme.labelLarge,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _HomeProjectTableHeader extends StatelessWidget {
  const _HomeProjectTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = asanaTableHeaderStyle(context);
    const headerH = AsanaHomePanel._taskRowHeight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SizedBox(
              height: headerH,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Project Name', style: style),
              ),
            ),
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homePicColWidth,
            label: 'PIC',
            style: style,
            rowHeight: headerH,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homeDueColWidth,
            label: 'Due Date',
            style: style,
            rowHeight: headerH,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homeStatusColWidth,
            label: 'Status',
            style: style,
            rowHeight: headerH,
          ),
        ],
      ),
    );
  }
}

class _HomeProjectRow extends StatelessWidget {
  const _HomeProjectRow({
    required this.project,
    required this.appState,
    this.onTap,
  });

  final ProjectRecord project;
  final AppState appState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = project.name.trim().isEmpty
        ? '(Unnamed project)'
        : project.name.trim();
    final completed = project.status.trim() == 'Completed';
    final nameStyle = asanaTableRowNameStyle(context, completed: completed);
    final valueStyle = asanaTableRowValueStyle(context, completed: completed);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: Colors.grey.shade200),
        InkWell(
          onTap: onTap,
          child: SizedBox(
            height: AsanaHomePanel._taskRowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: nameStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                _homeFixedCell(
                  width: AsanaHomePanel._homePicColWidth,
                  child: Text(
                    AsanaProjectFilter.picLine(project, appState),
                    style: valueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                _homeFixedCell(
                  width: AsanaHomePanel._homeDueColWidth,
                  child: Text(
                    _formatDueDate(project.endDate),
                    style: valueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                _homeFixedCell(
                  width: AsanaHomePanel._homeStatusColWidth,
                  child: AsanaStatusChip(
                    status: project.status,
                    preserveFullLabel: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Two-line project row: name, then `PIC: … · Due Date: …` + status chip.
class _HomeProjectCompactRow extends StatelessWidget {
  const _HomeProjectCompactRow({
    required this.project,
    required this.appState,
    this.onTap,
  });

  final ProjectRecord project;
  final AppState appState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = project.name.trim().isEmpty
        ? '(Unnamed project)'
        : project.name.trim();
    final completed = project.status.trim() == 'Completed';
    final nameStyle = asanaTableRowNameStyle(context, completed: completed);
    final metaStyle = asanaTableRowValueStyle(context, completed: completed);
    final metaLine = [
      _homeLabeledMetaLine(
        label: 'PIC',
        value: AsanaProjectFilter.picLine(project, appState),
      ),
      _homeLabeledMetaLine(
        label: 'Due',
        value: _formatDueDate(project.endDate),
      ),
    ].join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: Colors.grey.shade200),
        InkWell(
          onTap: onTap,
          child: SizedBox(
            height: AsanaHomePanel._taskRowCompactHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: nameStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        metaLine,
                        style: metaStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AsanaStatusChip(
                      status: project.status,
                      preserveFullLabel: true,
                    ),
                  ],
                ),
              ],
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
