import 'dart:async';
import 'dart:math' show min;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
import '../../models/initiative.dart';
import '../../models/singular_subtask.dart';
import '../../models/task.dart';
import '../../models/assignee.dart';
import '../../models/team.dart';
import '../../config/supabase_config.dart';
import '../../priority.dart';
import '../../services/landing_task_filters_storage.dart';
import '../../services/supabase_service.dart';
import '../../utils/hk_time.dart';
import '../../widgets/task_list_card.dart';
import '../../widgets/singular_subtask_row_card.dart';
import '../../utils/subtask_list_sort.dart';
import 'initiative_detail_screen.dart';
import 'subtask_detail_screen.dart';

/// Landing task list sort column (persisted as [storageKey]).
enum TaskListSortColumn {
  creator('creator'),
  assignee('assignee'),
  pic('pic'),
  startDate('startDate'),
  dueDate('dueDate'),
  status('status'),
  submission('submission');

  const TaskListSortColumn(this.storageKey);
  final String storageKey;

  static TaskListSortColumn? fromStorage(String? s) {
    if (s == null || s.isEmpty) return null;
    // Legacy persisted column removed from UI — treat as **Due date** (task + sub-task).
    if (s == 'subtaskDueDate') return TaskListSortColumn.dueDate;
    for (final v in TaskListSortColumn.values) {
      if (v.storageKey == s) return v;
    }
    return null;
  }

  String get label {
    switch (this) {
      case TaskListSortColumn.creator:
        return 'Creator';
      case TaskListSortColumn.assignee:
        return 'Assignee';
      case TaskListSortColumn.pic:
        return 'PIC';
      case TaskListSortColumn.startDate:
        return 'Start date';
      case TaskListSortColumn.dueDate:
        return 'Due date';
      case TaskListSortColumn.status:
        return 'Status';
      case TaskListSortColumn.submission:
        return 'Submission';
    }
  }
}

/// One row in the Customized flat list — either a task card or a sub-task card.
class _CustomizedFlatEntry {
  _CustomizedFlatEntry.task(this.task) : sub = null;
  _CustomizedFlatEntry.subtask(this.task, this.sub);

  final Task task;
  final SingularSubtask? sub;

  bool get isTaskRow => sub == null;
}

class InitiativeListScreen extends StatefulWidget {
  const InitiativeListScreen({
    super.key,
    /// Dashboards → Customized: same filters/sort as landing; sub-tasks always visible on each card.
    this.customizedFlat = false,
  });

  /// When true, initiatives are hidden and each [TaskListCard] shows sub-tasks without expand/collapse.
  final bool customizedFlat;

  @override
  State<InitiativeListScreen> createState() => _InitiativeListScreenState();
}

class _InitiativeListScreenState extends State<InitiativeListScreen> {
  /// Landing list column max width ([TaskListCard] + search below filter chips).
  static const double _kLandingTaskListMaxWidth = 1100;

  /// Max width for team / status filter fields (readable on wide layouts).
  static const double _filterFieldMaxWidth = 420;

  /// "Filter by assignee" submenu: roster team, then multi-select teammates (tasks/initiatives).
  String? _filterAssigneeMenuTeamId;
  final Set<String> _filterAssigneeMenuStaffIds = {};

  /// "Filter by creator" submenu: roster team, then multi-select teammates (tasks by creator).
  String? _filterCreatorMenuTeamId;
  final Set<String> _filterCreatorMenuStaffIds = {};

  late final ExpansibleController _filterAssigneeRootController;
  late final ExpansibleController _filterAssigneeTeamController;
  late final ExpansibleController _filterAssigneeTeammateTileController;
  late final ExpansibleController _filterCreatorRootController;
  late final ExpansibleController _filterCreatorTeamController;
  late final ExpansibleController _filterCreatorTeammateTileController;
  late final ExpansibleController _filterStatusTileController;
  late final ExpansibleController _filterOverdueTileController;
  late final ExpansibleController _filterSubmissionTileController;
  late final ExpansibleController _filterCreateDateTileController;

  /// Create-date range filter (task `createdAt` / sub-task `createDate` on Customized).
  DateTime? _filterCreateDateStart;
  DateTime? _filterCreateDateEnd;

  /// Scope: `all` | `assigned` | `created` (chips: All, Assigned to me, My created tasks).
  String _filterType = 'all';

  /// Subset of `incomplete` | `completed` | `deleted`. Empty = all statuses (label "All status").
  final Set<String> _selectedTaskStatuses = {};

  /// Subset of [_submissionPending]…[_submissionReturned]. Empty = all (label "All submission").
  final Set<String> _selectedSubmissionFilters = {};

  /// When true, only rows where [`Task.overdue`] or a sub-task's [`SingularSubtask.overdue`] is `Yes` (DB).
  bool _filterOverdueOnly = false;
  final TextEditingController _taskSearchController = TextEditingController();
  final MenuController _filterMenuController = MenuController();
  bool _remindersExpanded = false;

  /// Single-column sort for task lists on the landing page (null = default order).
  TaskListSortColumn? _taskSortColumn;
  bool _taskSortAscending = true;

  /// Client-side paging for [TaskListCard] lists (search/filter unchanged; slice after).
  static const List<int> _landingTaskPageSizes = [25, 50, 100, 200];
  int _tasksPageSize = 50;
  int _tasksPageIndex = 0;
  int _deletedTasksPageIndex = 0;

  /// Bumped after editing a sub-task on the Customized page so grouped fetch refreshes.
  int _customizedFlatListRefreshSeq = 0;

  /// Min / max sub-task `due_date` per parent task id (singular tasks only); used for [TaskListSortColumn.dueDate].
  final Map<String, DateTime?> _subtaskMinDueByTaskId = {};
  final Map<String, DateTime?> _subtaskMaxDueByTaskId = {};
  /// Singular tasks only: after fetch, true if any non-deleted, non-completed sub-task has calendar due before HK today.
  final Map<String, bool> _subtaskHasOverdueByTaskId = {};
  /// Lowercased sub-task names + descriptions per parent task id (singular only); used for landing search.
  final Map<String, String> _subtaskSearchBlobByTaskId = {};
  String _cachedSingularTaskIdsSig = '';

  /// Bumped when a new sub-task prefetch starts or caches clear; stale [Future]s skip [setState].
  int _subtaskFetchGeneration = 0;

  /// Last trimmed search string used for sub-task blob cache; when it changes, blobs are cleared
  /// so a new [fetchSubtasksForTask] pass runs (avoids stale empty maps blocking matches).
  String _lastSubtaskSearchQueryForBlob = '';

  /// Normalized landing search string that [_subtaskServerSetsByToken] belongs to (see [_landingSearchNormalized]).
  String _subtaskServerQueryNormalized = '';

  /// Per search token: parent task ids with a non-deleted subtask matching that token in name/description.
  /// Populated by debounced [SupabaseService.fetchTaskIdsHavingSubtaskToken] so landing search does not
  /// depend only on sequential client-side sub-task prefetch.
  Map<String, Set<String>>? _subtaskServerSetsByToken;

  int _landingSubtaskServerSearchSeq = 0;
  Timer? _landingSubtaskServerSearchDebounce;

  /// Per-user prefs: do not persist until first load finished (avoids clobbering saved teams).
  bool _landingFiltersPrefsReady = false;

  /// When saved team ids exist but [AppState.teams] is still empty, apply the rest first; then this.
  LandingTaskFilters? _deferredPrefsForTeams;

  AppState? _appStateListenerRef;
  Timer? _searchPersistDebounce;

  /// Skip debounced persist while restoring from disk (search [TextEditingController] updates).
  bool _suppressFilterPersist = false;

  static const _statusIncomplete = 'incomplete';
  static const _statusCompleted = 'completed';
  static const _statusDeleted = 'deleted';

  static const _submissionPending = 'pending';
  static const _submissionSubmitted = 'submitted';
  static const _submissionAccepted = 'accepted';
  static const _submissionReturned = 'returned';

  /// Normalizes task/sub-task `submission` to a landing filter key (defaults to pending).
  static String _submissionFilterKeyRaw(String? submission) {
    final raw = submission?.trim().toLowerCase() ?? '';
    if (raw.isEmpty || raw == 'pending') return _submissionPending;
    if (raw == 'submitted') return _submissionSubmitted;
    if (raw == 'accepted') return _submissionAccepted;
    if (raw == 'returned') return _submissionReturned;
    return _submissionPending;
  }

  /// Normalizes [Task.submission] to a landing filter key (defaults to pending when empty/unknown).
  static String _submissionFilterKey(Task t) => _submissionFilterKeyRaw(t.submission);

  static bool _singularSubtaskCompleted(SingularSubtask s) {
    final x = s.status.trim().toLowerCase();
    return x == 'completed' || x == 'complete';
  }

  /// Matches [singularIncomplete] closure used in build for singular [`task`] rows.
  bool _singularTaskIncomplete(Task t) {
    if (!t.isSingularTableRow) return false;
    final s = t.dbStatus?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return true;
    return s == 'incomplete';
  }

  /// Completed filter without Incomplete: flat list only Completed tasks / Completed sub-tasks.
  bool get _overviewCompletedOnlyWithoutIncomplete =>
      widget.customizedFlat &&
      _selectedTaskStatuses.contains(_statusCompleted) &&
      !_selectedTaskStatuses.contains(_statusIncomplete);

  /// Overview customized flat: omit sub-task row per status/submission conflict rules.
  bool _customizedFlatShouldOmitSubtaskRow(Task t, SingularSubtask s) {
    if (!t.isSingularTableRow || !widget.customizedFlat) return false;

    // Incomplete selected: never list Completed sub-tasks under an Incomplete parent (task row only).
    if (_selectedTaskStatuses.contains(_statusIncomplete) &&
        _singularTaskIncomplete(t) &&
        _singularSubtaskCompleted(s)) {
      return true;
    }

    // Completed only (vs Incomplete): hide non-Completed sub-tasks everywhere.
    if (_overviewCompletedOnlyWithoutIncomplete && !_singularSubtaskCompleted(s)) {
      return true;
    }

    if (_selectedSubmissionFilters.length == 1) {
      final tk = _submissionFilterKey(t);
      final sk = _submissionFilterKeyRaw(s.submission);
      if (_selectedSubmissionFilters.contains(_submissionPending) &&
          tk == _submissionPending &&
          (sk == _submissionSubmitted ||
              sk == _submissionAccepted ||
              sk == _submissionReturned)) {
        return true;
      }
      if (_selectedSubmissionFilters.contains(_submissionSubmitted) &&
          tk == _submissionSubmitted &&
          (sk == _submissionAccepted ||
              sk == _submissionReturned ||
              sk == _submissionPending)) {
        return true;
      }
      if (_selectedSubmissionFilters.contains(_submissionAccepted) &&
          tk == _submissionAccepted &&
          (sk == _submissionSubmitted ||
              sk == _submissionReturned ||
              sk == _submissionPending)) {
        return true;
      }
      if (_selectedSubmissionFilters.contains(_submissionReturned) &&
          tk == _submissionReturned &&
          (sk == _submissionSubmitted ||
              sk == _submissionAccepted ||
              sk == _submissionPending)) {
        return true;
      }
    }

    return false;
  }

  /// Completed without Incomplete: never show a task row for an Incomplete parent (only Completed task rows and Completed sub-task rows).
  bool _customizedFlatHideIncompleteParentTaskRowWhenCompletedOnly(Task t) {
    if (!t.isSingularTableRow || !widget.customizedFlat) return false;
    if (!_overviewCompletedOnlyWithoutIncomplete) return false;
    return _singularTaskIncomplete(t);
  }

  /// On my plate as assignee — dark blue chip when selected.
  Widget _assignedToMeFilterIcon(bool selected) {
    return Icon(
      Icons.assignment_ind,
      size: 18,
      color: selected ? Colors.white : const Color(0xFF0D47A1),
    );
  }

  /// Tasks I created — task icon on "My created tasks".
  Widget _myCreatedTasksFilterIcon(bool selected) {
    return Icon(
      Icons.task_alt,
      size: 18,
      color: selected ? Colors.black87 : Colors.lightBlue.shade800,
    );
  }

  /// Scrollable chips so labels stay on one line on narrow / mobile screens.
  Widget _buildTaskFilterChip({
    required String value,
    required String label,
    required bool selected,
    Color? selectedBg,
    Color? selectedLabelColor,
    Widget? leading,
  }) {
    final theme = Theme.of(context);
    final Color onLabel;
    if (!selected) {
      onLabel = theme.colorScheme.onSurface;
    } else if (selectedLabelColor != null) {
      onLabel = selectedLabelColor;
    } else if (selectedBg == null) {
      onLabel = theme.colorScheme.onPrimary;
    } else {
      onLabel = theme.colorScheme.onSecondaryContainer;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        showCheckmark: false,
        avatar: leading,
        label: Text(label, maxLines: 1, softWrap: false),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _filterType = value;
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        selectedColor: selectedBg,
        labelStyle: TextStyle(
          color: onLabel,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  /// Closed field preview: "Status" until user picks one or more statuses from the menu.
  String _statusFilterDisplayText() {
    if (_selectedTaskStatuses.isEmpty) return 'Status';
    const labels = {
      _statusIncomplete: 'Incomplete',
      _statusCompleted: 'Completed',
      _statusDeleted: 'Deleted',
    };
    const order = [_statusIncomplete, _statusCompleted, _statusDeleted];
    return order
        .where(_selectedTaskStatuses.contains)
        .map((k) => labels[k]!)
        .join(', ');
  }

  String _submissionFilterDisplayText() {
    if (_selectedSubmissionFilters.isEmpty) return 'All submission';
    const labels = {
      _submissionPending: 'Pending',
      _submissionSubmitted: 'Submitted',
      _submissionAccepted: 'Accepted',
      _submissionReturned: 'Returned',
    };
    const order = [
      _submissionPending,
      _submissionSubmitted,
      _submissionAccepted,
      _submissionReturned,
    ];
    return order
        .where(_selectedSubmissionFilters.contains)
        .map((k) => labels[k]!)
        .join(', ');
  }

  bool get _filterCreateDateEngaged =>
      _filterCreateDateStart != null || _filterCreateDateEnd != null;

  /// Rolling window matching [_dateWithinLastRollingMonth] (HK calendar; inclusive).
  (DateTime start, DateTime end) _defaultCreateDateRangeHk() {
    final end = HkTime.todayDateOnlyHk();
    final start = end.subtract(const Duration(days: 30));
    return (start, end);
  }

  String _defaultCreateDateRangeSummary(DateFormat fmt) {
    final r = _defaultCreateDateRangeHk();
    return '${fmt.format(r.$1)} – ${fmt.format(r.$2)}';
  }

  /// True when status / submission / assignee / creator / search are not at default (all).
  bool get _hasTeamOrStatusFilterSelections =>
      _selectedTaskStatuses.isNotEmpty ||
      _filterOverdueOnly ||
      _selectedSubmissionFilters.isNotEmpty ||
      _filterAssigneeMenuStaffIds.isNotEmpty ||
      _filterCreatorMenuStaffIds.isNotEmpty ||
      _filterCreateDateEngaged ||
      _taskSearchController.text.trim().isNotEmpty;

  void _clearTeamAndStatusFilters() {
    _landingSubtaskServerSearchDebounce?.cancel();
    setState(() {
      _selectedTaskStatuses.clear();
      _selectedSubmissionFilters.clear();
      _filterOverdueOnly = false;
      _filterAssigneeMenuTeamId = null;
      _filterAssigneeMenuStaffIds.clear();
      _filterCreatorMenuTeamId = null;
      _filterCreatorMenuStaffIds.clear();
      _filterCreateDateStart = null;
      _filterCreateDateEnd = null;
      _taskSearchController.clear();
      _lastSubtaskSearchQueryForBlob = '';
      _subtaskMinDueByTaskId.clear();
      _subtaskMaxDueByTaskId.clear();
      _subtaskHasOverdueByTaskId.clear();
      _subtaskSearchBlobByTaskId.clear();
      _subtaskFetchGeneration++;
      _landingSubtaskServerSearchSeq++;
      _subtaskServerSetsByToken = null;
      _subtaskServerQueryNormalized = '';
      _tasksPageIndex = 0;
      _deletedTasksPageIndex = 0;
    });
    _persistLandingFilters();
    _collapseAllFilterMenuExpansionTiles();
  }

  void _collapseAllFilterMenuExpansionTiles() {
    _filterAssigneeRootController.collapse();
    _filterAssigneeTeamController.collapse();
    _filterAssigneeTeammateTileController.collapse();
    _filterCreatorRootController.collapse();
    _filterCreatorTeamController.collapse();
    _filterCreatorTeammateTileController.collapse();
    _filterStatusTileController.collapse();
    _filterOverdueTileController.collapse();
    _filterSubmissionTileController.collapse();
    _filterCreateDateTileController.collapse();
  }

  /// When the filter [MenuAnchor] closes (e.g. tap outside), reset all expansion tiles.
  void _onFilterMenuAnchorClosed() {
    _collapseAllFilterMenuExpansionTiles();
  }

  bool get _filterAssigneeRosterEngaged =>
      (_filterAssigneeMenuTeamId != null &&
          _filterAssigneeMenuTeamId!.isNotEmpty) ||
      _filterAssigneeMenuStaffIds.isNotEmpty;

  bool get _filterCreatorRosterEngaged =>
      (_filterCreatorMenuTeamId != null &&
          _filterCreatorMenuTeamId!.isNotEmpty) ||
      _filterCreatorMenuStaffIds.isNotEmpty;

  void _collapseAssigneeFilterExpansionIfEngaged() {
    if (!_filterAssigneeRosterEngaged) return;
    _filterAssigneeRootController.collapse();
    _filterAssigneeTeamController.collapse();
    _filterAssigneeTeammateTileController.collapse();
  }

  void _collapseCreatorFilterExpansionIfEngaged() {
    if (!_filterCreatorRosterEngaged) return;
    _filterCreatorRootController.collapse();
    _filterCreatorTeamController.collapse();
    _filterCreatorTeammateTileController.collapse();
  }

  /// After changing Status or Submission from a checkbox, hide roster panels if used.
  void _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange() {
    _collapseAssigneeFilterExpansionIfEngaged();
    _collapseCreatorFilterExpansionIfEngaged();
  }

  /// Accordion: only one of Assignee / Creator / Status / Overdue / Submission stays expanded.
  void _onTopLevelFilterSectionExpanded(String openedId) {
    if (openedId != 'assignee') {
      _filterAssigneeRootController.collapse();
      _filterAssigneeTeamController.collapse();
      _filterAssigneeTeammateTileController.collapse();
    }
    if (openedId != 'creator') {
      _filterCreatorRootController.collapse();
      _filterCreatorTeamController.collapse();
      _filterCreatorTeammateTileController.collapse();
    }
    if (openedId != 'status') _filterStatusTileController.collapse();
    if (openedId != 'overdue') _filterOverdueTileController.collapse();
    if (openedId != 'submission') _filterSubmissionTileController.collapse();
    if (openedId != 'createDate') _filterCreateDateTileController.collapse();
  }

  /// Under Assignee or Creator: only Team or Teammate stays expanded.
  void _onTeamStaffNestedSectionExpanded({
    required String rootId,
    required String openedNestedId,
  }) {
    if (rootId == 'assignee') {
      if (openedNestedId != 'team') _filterAssigneeTeamController.collapse();
      if (openedNestedId != 'teammate') {
        _filterAssigneeTeammateTileController.collapse();
      }
    } else {
      if (openedNestedId != 'team') _filterCreatorTeamController.collapse();
      if (openedNestedId != 'teammate') {
        _filterCreatorTeammateTileController.collapse();
      }
    }
  }

  /// One-line summary inside the closed "Filter" control.
  String _filterMenuSummaryLine(AppState state) {
    final parts = <String>[];
    if (_filterAssigneeMenuStaffIds.isNotEmpty) {
      final names =
          _filterAssigneeMenuStaffIds
              .map((id) => state.assigneeById(id)?.name ?? id)
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      parts.add('Assignee: ${names.join(', ')}');
    }
    if (_filterCreatorMenuStaffIds.isNotEmpty) {
      final names =
          _filterCreatorMenuStaffIds
              .map((id) => state.assigneeById(id)?.name ?? id)
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      parts.add('Creator: ${names.join(', ')}');
    }
    {
      final fmt = DateFormat.yMMMd();
      if (_filterCreateDateEngaged) {
        final a = _filterCreateDateStart != null
            ? fmt.format(_filterCreateDateStart!)
            : '…';
        final b =
            _filterCreateDateEnd != null ? fmt.format(_filterCreateDateEnd!) : '…';
        parts.add('Create date: $a – $b');
      } else {
        parts.add(
          'Create date: ${_defaultCreateDateRangeSummary(fmt)} (default)',
        );
      }
    }
    if (_selectedTaskStatuses.isEmpty) {
      parts.add('All status');
    } else {
      parts.add(_statusFilterDisplayText());
    }
    if (_filterOverdueOnly) {
      parts.add('Overdue');
    }
    if (_selectedSubmissionFilters.isEmpty) {
      parts.add('All submission');
    } else {
      parts.add(_submissionFilterDisplayText());
    }
    return parts.join(' · ');
  }

  static String _landingSearchNormalized(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .join(' ');
  }

  static List<String> _landingSearchTokens(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Customized search: every token must appear in task name or description.
  static bool _taskTextMatchesAllTokens(Task t, List<String> tokens) {
    if (tokens.isEmpty) return false;
    final name = t.name.toLowerCase();
    final desc = t.description.toLowerCase();
    for (final tkn in tokens) {
      if (!name.contains(tkn) && !desc.contains(tkn)) return false;
    }
    return true;
  }

  /// Customized search: every token must appear in sub-task name or description.
  static bool _subtaskTextMatchesAllTokens(SingularSubtask s, List<String> tokens) {
    if (tokens.isEmpty) return false;
    final n = s.subtaskName.toLowerCase();
    final d = s.description.toLowerCase();
    for (final tkn in tokens) {
      if (!n.contains(tkn) && !d.contains(tkn)) return false;
    }
    return true;
  }

  void _scheduleLandingSubtaskServerSearch() {
    _landingSubtaskServerSearchDebounce?.cancel();
    final requestSeq = _landingSubtaskServerSearchSeq;
    _landingSubtaskServerSearchDebounce = Timer(
      const Duration(milliseconds: 320),
      () async {
        if (!mounted || requestSeq != _landingSubtaskServerSearchSeq) return;
        final raw = _taskSearchController.text;
        final norm = _landingSearchNormalized(raw);
        if (!SupabaseConfig.isConfigured || norm.isEmpty) {
          if (!mounted || requestSeq != _landingSubtaskServerSearchSeq) return;
          setState(() {
            _subtaskServerSetsByToken = null;
            _subtaskServerQueryNormalized = '';
          });
          return;
        }
        final tokens = _landingSearchTokens(raw);
        if (tokens.isEmpty) {
          if (!mounted || requestSeq != _landingSubtaskServerSearchSeq) return;
          setState(() {
            _subtaskServerSetsByToken = null;
            _subtaskServerQueryNormalized = '';
          });
          return;
        }
        final unique = tokens.toSet().toList();
        final map = <String, Set<String>>{};
        for (final tok in unique) {
          if (!mounted || requestSeq != _landingSubtaskServerSearchSeq) return;
          map[tok] = await SupabaseService.fetchTaskIdsHavingSubtaskToken(tok);
        }
        if (!mounted || requestSeq != _landingSubtaskServerSearchSeq) return;
        if (_landingSearchNormalized(_taskSearchController.text) != norm) return;
        setState(() {
          _subtaskServerSetsByToken = map;
          _subtaskServerQueryNormalized = norm;
        });
      },
    );
  }

  /// Each whitespace-separated keyword must appear in [Task.name], [Task.description],
  /// or any non-deleted sub-task’s `subtask_name` / `description` (case-insensitive).
  bool _taskMatchesLandingSearch(Task t, String query) {
    final tokens = _landingSearchTokens(query);
    if (tokens.isEmpty) return true;
    final norm = _landingSearchNormalized(query);
    final serverMap = _subtaskServerSetsByToken;
    final serverReady =
        serverMap != null && _subtaskServerQueryNormalized == norm;
    final name = t.name.toLowerCase();
    final desc = t.description.toLowerCase();
    final subBlob = t.isSingularTableRow
        ? (_subtaskSearchBlobByTaskId[t.id] ?? '')
        : '';
    for (final token in tokens) {
      final inTask = name.contains(token) || desc.contains(token);
      final inSub = subBlob.contains(token);
      final inSubServer =
          serverReady && (serverMap[token]?.contains(t.id) ?? false);
      if (!inTask && !inSub && !inSubServer) return false;
    }
    return true;
  }

  /// DB: `subtask.subtask_name`, `subtask.description` (via [SingularSubtask]).
  static String _subtaskSearchBlobFromList(List<SingularSubtask> list) {
    final parts = <String>[];
    for (final st in list) {
      if (st.isDeleted) continue;
      parts.add(st.subtaskName);
      parts.add(st.description);
    }
    return parts.join(' ').trim().toLowerCase();
  }

  List<Task> _applyTaskSearch(List<Task> tasks) {
    final raw = _taskSearchController.text;
    if (_landingSearchNormalized(raw).isEmpty) return tasks;
    return tasks.where((t) => _taskMatchesLandingSearch(t, raw)).toList();
  }

  String _assigneeSortKey(Task t, AppState state) {
    final names =
        t.assigneeIds
            .map((id) => state.assigneeById(id)?.name ?? id)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.join(', ');
  }

  String _picSortKey(Task t, AppState state) {
    final p = t.pic?.trim();
    if (p == null || p.isEmpty) return '';
    return state.assigneeById(p)?.name ?? p;
  }

  static int _cmpStrNullable(String? a, String? b, bool ascending) {
    final sa = a?.trim().toLowerCase() ?? '';
    final sb = b?.trim().toLowerCase() ?? '';
    if (sa.isEmpty && sb.isEmpty) return 0;
    if (sa.isEmpty) return 1;
    if (sb.isEmpty) return -1;
    final c = sa.compareTo(sb);
    return ascending ? c : -c;
  }

  static int _cmpDateForSort(DateTime? a, DateTime? b, bool ascending) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final c = a.compareTo(b);
    return ascending ? c : -c;
  }

  /// Normalizes to local calendar midnight for comparing task vs sub-task **due dates**.
  static DateTime? _landingCalendarDueDay(DateTime? d) {
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  /// Ascending **Due date**: earliest calendar day among [Task.endDate] and all loaded sub-task dues.
  DateTime? _effectiveDueSortMin(Task t) {
    final taskDay = _landingCalendarDueDay(t.endDate);
    if (!t.isSingularTableRow) return taskDay;
    if (!_subtaskMaxDueByTaskId.containsKey(t.id)) return taskDay;
    DateTime? best;
    void pick(DateTime? d) {
      final n = _landingCalendarDueDay(d);
      if (n == null) return;
      if (best == null || n.isBefore(best!)) best = n;
    }
    pick(t.endDate);
    pick(_subtaskMinDueByTaskId[t.id]);
    return best;
  }

  /// Descending **Due date**: latest calendar day among [Task.endDate] and all loaded sub-task dues.
  DateTime? _effectiveDueSortMax(Task t) {
    final taskDay = _landingCalendarDueDay(t.endDate);
    if (!t.isSingularTableRow) return taskDay;
    if (!_subtaskMaxDueByTaskId.containsKey(t.id)) return taskDay;
    DateTime? best;
    void pick(DateTime? d) {
      final n = _landingCalendarDueDay(d);
      if (n == null) return;
      if (best == null || n.isAfter(best!)) best = n;
    }
    pick(t.endDate);
    pick(_subtaskMaxDueByTaskId[t.id]);
    return best;
  }

  String _singularTaskIdsSignature(AppState state) {
    final ids = state.tasks
        .where((t) => t.isSingularTableRow)
        .map((t) => t.id)
        .toList()
      ..sort();
    return ids.join('|');
  }

  void _scheduleSubtaskRowDataPrefetch(
    List<Task> tasks,
    List<Task> deletedTasks,
  ) {
    if (!SupabaseConfig.isConfigured) return;
    final needDue = _taskSortColumn == TaskListSortColumn.dueDate;
    final needBlob = _taskSearchController.text.trim().isNotEmpty;
    final needOverdue = _filterOverdueOnly;
    if (!needDue && !needBlob && !needOverdue) return;
    final seen = <String>{};
    final combined = <Task>[];
    for (final t in [...tasks, ...deletedTasks]) {
      if (!t.isSingularTableRow || seen.contains(t.id)) continue;
      seen.add(t.id);
      combined.add(t);
    }
    final singularIds = combined.map((t) => t.id).toList()..sort();
    final idsToFetch = singularIds.where((id) {
      final missingDue = needDue && !_subtaskMaxDueByTaskId.containsKey(id);
      final missingBlob = needBlob && !_subtaskSearchBlobByTaskId.containsKey(id);
      final missingOverdue =
          needOverdue && !_subtaskHasOverdueByTaskId.containsKey(id);
      return missingDue || missingBlob || missingOverdue;
    }).toList();
    if (idsToFetch.isEmpty) return;
    unawaited(_loadSubtaskRowDataForTasks(idsToFetch));
  }

  /// Writes aggregated sub-task fields for one parent task id into landing caches.
  void _applySubtaskPrefetchFromList(String id, List<SingularSubtask> list) {
    final minDue = TaskListCard.minSubtaskDueForSort(list);
    final maxDue = TaskListCard.maxSubtaskDueForSort(list);
    final blob = _subtaskSearchBlobFromList(list);
    var hasOverdueSub = false;
    for (final st in list) {
      if (st.isDeleted) continue;
      if (st.overdue == 'Yes') {
        hasOverdueSub = true;
        break;
      }
    }
    _subtaskMinDueByTaskId[id] = minDue;
    _subtaskMaxDueByTaskId[id] = maxDue;
    _subtaskSearchBlobByTaskId[id] = blob;
    _subtaskHasOverdueByTaskId[id] = hasOverdueSub;
  }

  /// Loads sub-task rows per task; updates maps **per task** so search (e.g. sub-task name "HKU")
  /// can match as soon as that task’s rows are loaded, not only after all tasks finish.
  ///
  /// Uses batched Supabase queries + one [setState] when possible; falls back to per-task fetch.
  ///
  /// [_subtaskFetchGeneration] is bumped when the singular-task id set changes so in-flight
  /// work after a cache clear does not call [setState].
  Future<void> _loadSubtaskRowDataForTasks(List<String> taskIds) async {
    final startGen = _subtaskFetchGeneration;
    if (taskIds.isEmpty) return;
    try {
      final grouped =
          await SupabaseService.fetchSubtasksGroupedForLandingPrefetch(taskIds);
      if (!mounted || startGen != _subtaskFetchGeneration) return;
      setState(() {
        for (final id in taskIds) {
          _applySubtaskPrefetchFromList(id, grouped[id] ?? []);
        }
      });
    } catch (_) {
      await _loadSubtaskRowDataForTasksSequentialFallback(taskIds, startGen);
    }
  }

  Future<void> _loadSubtaskRowDataForTasksSequentialFallback(
    List<String> taskIds,
    int startGen,
  ) async {
    for (final id in taskIds) {
      if (!mounted || startGen != _subtaskFetchGeneration) return;
      try {
        final list = await SupabaseService.fetchSubtasksForTask(id);
        if (!mounted || startGen != _subtaskFetchGeneration) return;
        setState(() => _applySubtaskPrefetchFromList(id, list));
      } catch (_) {
        if (!mounted || startGen != _subtaskFetchGeneration) return;
        setState(() => _applySubtaskPrefetchFromList(id, []));
      }
    }
  }

  List<Task> _sortTasks(List<Task> tasks, AppState state) {
    if (_taskSortColumn == null) return tasks;
    final col = _taskSortColumn!;
    final asc = _taskSortAscending;
    final out = List<Task>.from(tasks);
    out.sort((a, b) {
      int c;
      switch (col) {
        case TaskListSortColumn.creator:
          c = _cmpStrNullable(a.createByStaffName, b.createByStaffName, asc);
          break;
        case TaskListSortColumn.assignee:
          c = _cmpStrNullable(
            _assigneeSortKey(a, state),
            _assigneeSortKey(b, state),
            asc,
          );
          break;
        case TaskListSortColumn.pic:
          c = _cmpStrNullable(
            _picSortKey(a, state),
            _picSortKey(b, state),
            asc,
          );
          break;
        case TaskListSortColumn.startDate:
          c = _cmpDateForSort(a.startDate, b.startDate, asc);
          break;
        case TaskListSortColumn.dueDate:
          final aKey = asc ? _effectiveDueSortMin(a) : _effectiveDueSortMax(a);
          final bKey = asc ? _effectiveDueSortMin(b) : _effectiveDueSortMax(b);
          c = _cmpDateForSort(aKey, bKey, asc);
          break;
        case TaskListSortColumn.status:
          c = _cmpStrNullable(
            TaskListCard.statusLabel(a),
            TaskListCard.statusLabel(b),
            asc,
          );
          break;
        case TaskListSortColumn.submission:
          c = _cmpStrNullable(a.submission, b.submission, asc);
          break;
      }
      if (c != 0) return c;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  List<Initiative> _applyInitiativeNameSearch(List<Initiative> list) {
    final raw = _taskSearchController.text.trim().toLowerCase();
    if (raw.isEmpty) return list;
    return list.where((i) => i.name.toLowerCase().contains(raw)).toList();
  }

  bool _dateWithinLastRollingMonth(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final today = HkTime.todayDateOnlyHk();
    final start = today.subtract(const Duration(days: 30));
    return !day.isBefore(start) && !day.isAfter(today);
  }

  bool _taskCreatedWithinLastMonth(Task t) =>
      _dateWithinLastRollingMonth(t.createdAt);

  bool _subtaskCreatedWithinLastMonth(SingularSubtask s) {
    final cd = s.createDate;
    if (cd == null) return false;
    return _dateWithinLastRollingMonth(cd);
  }

  static DateTime _dateOnlyCal(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  bool _calendarDayInCreateFilterRange(DateTime day) {
    if (!_filterCreateDateEngaged) return true;
    final s = _filterCreateDateStart != null
        ? _dateOnlyCal(_filterCreateDateStart!)
        : null;
    final e = _filterCreateDateEnd != null
        ? _dateOnlyCal(_filterCreateDateEnd!)
        : null;
    if (s != null && day.isBefore(s)) return false;
    if (e != null && day.isAfter(e)) return false;
    return true;
  }

  bool _rowPassesCreateDateForCustomized(Task t, SingularSubtask? sub) {
    final DateTime day;
    if (sub == null) {
      day = _dateOnlyCal(t.createdAt);
    } else {
      final cd = sub.createDate;
      day = cd == null ? _dateOnlyCal(t.createdAt) : _dateOnlyCal(cd);
    }
    if (_filterCreateDateEngaged) {
      return _calendarDayInCreateFilterRange(day);
    }
    if (sub == null) return _taskCreatedWithinLastMonth(t);
    return _subtaskCreatedWithinLastMonth(sub);
  }

  Future<Map<String, List<SingularSubtask>>> _futureGroupedForCustomized(
    List<Task> active,
    List<Task> deleted,
  ) async {
    final ids = <String>{};
    for (final t in active) {
      if (t.isSingularTableRow) ids.add(t.id);
    }
    for (final t in deleted) {
      if (t.isSingularTableRow) ids.add(t.id);
    }
    if (ids.isEmpty) return {};
    return SupabaseService.fetchSubtasksGroupedForLandingPrefetch(ids.toList());
  }

  List<_CustomizedFlatEntry> _buildCustomizedFlatEntries(
    List<Task> tasks,
    Map<String, List<SingularSubtask>> grouped,
    String searchRaw,
  ) {
    final tokens = _landingSearchTokens(searchRaw);
    final searchActive = tokens.isNotEmpty;
    final out = <_CustomizedFlatEntry>[];

    for (final t in tasks) {
      if (!t.isSingularTableRow) {
        if (_filterOverdueOnly) {
          if (t.overdue != 'Yes') continue;
          if (!searchActive) {
            if (_rowPassesCreateDateForCustomized(t, null)) {
              out.add(_CustomizedFlatEntry.task(t));
            }
          } else if (_taskTextMatchesAllTokens(t, tokens) &&
              _rowPassesCreateDateForCustomized(t, null)) {
            out.add(_CustomizedFlatEntry.task(t));
          }
          continue;
        }
        if (!searchActive) {
          if (_rowPassesCreateDateForCustomized(t, null)) {
            out.add(_CustomizedFlatEntry.task(t));
          }
        } else if (_taskTextMatchesAllTokens(t, tokens) &&
            _rowPassesCreateDateForCustomized(t, null)) {
          out.add(_CustomizedFlatEntry.task(t));
        }
        continue;
      }

      final subs = grouped[t.id] ?? [];
      final subsNonDeleted = subs.where((s) => !s.isDeleted).toList();

      if (_filterOverdueOnly) {
        if (t.overdue == 'Yes') {
          if (!searchActive) {
            if (_rowPassesCreateDateForCustomized(t, null)) {
              out.add(_CustomizedFlatEntry.task(t));
            }
          } else if (_taskTextMatchesAllTokens(t, tokens) &&
              _rowPassesCreateDateForCustomized(t, null)) {
            out.add(_CustomizedFlatEntry.task(t));
          }
        } else {
          for (final s in subsNonDeleted) {
            if (s.overdue != 'Yes') continue;
            if (_customizedFlatShouldOmitSubtaskRow(t, s)) continue;
            if (!searchActive) {
              if (_rowPassesCreateDateForCustomized(t, s)) {
                out.add(_CustomizedFlatEntry.subtask(t, s));
              }
            } else {
              if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
              if (!_rowPassesCreateDateForCustomized(t, s)) continue;
              out.add(_CustomizedFlatEntry.subtask(t, s));
            }
          }
        }
        continue;
      }

      if (!searchActive) {
        final subsInRange = subsNonDeleted
            .where((s) => _rowPassesCreateDateForCustomized(t, s))
            .where((s) => !_customizedFlatShouldOmitSubtaskRow(t, s))
            .toList();
        final taskInRange = _rowPassesCreateDateForCustomized(t, null);
        if (!taskInRange && subsInRange.isEmpty) continue;
        if (taskInRange &&
            !_customizedFlatHideIncompleteParentTaskRowWhenCompletedOnly(t)) {
          out.add(_CustomizedFlatEntry.task(t));
        }
        for (final s in subsInRange) {
          out.add(_CustomizedFlatEntry.subtask(t, s));
        }
        continue;
      }

      final taskTextMatch = _taskTextMatchesAllTokens(t, tokens);
      final taskRowAllowed = taskTextMatch &&
          _rowPassesCreateDateForCustomized(t, null);

      if (taskRowAllowed) {
        if (!_customizedFlatHideIncompleteParentTaskRowWhenCompletedOnly(t)) {
          out.add(_CustomizedFlatEntry.task(t));
        }
        continue;
      }

      for (final s in subsNonDeleted) {
        if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
        if (!_rowPassesCreateDateForCustomized(t, s)) continue;
        if (_customizedFlatShouldOmitSubtaskRow(t, s)) continue;
        out.add(_CustomizedFlatEntry.subtask(t, s));
      }
    }
    return out;
  }

  DateTime _customizedCreateInstant(_CustomizedFlatEntry e) {
    if (e.isTaskRow) return e.task.createdAt;
    final cd = e.sub!.createDate;
    return cd ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String? _customizedCreatorKey(_CustomizedFlatEntry e) {
    if (e.isTaskRow) return e.task.createByStaffName;
    return e.sub!.createByStaffName;
  }

  String _customizedAssigneeKey(_CustomizedFlatEntry e, AppState state) {
    if (e.isTaskRow) return _assigneeSortKey(e.task, state);
    return SubtaskListSort.assigneeSortKey(
      e.sub!,
      (id) => state.assigneeById(id)?.name ?? id,
    );
  }

  String _customizedPicKey(_CustomizedFlatEntry e, AppState state) {
    if (e.isTaskRow) return _picSortKey(e.task, state);
    return SubtaskListSort.picSortKey(
      e.sub!,
      (id) => state.assigneeById(id)?.name ?? id,
    );
  }

  DateTime? _customizedStartKey(_CustomizedFlatEntry e) {
    if (e.isTaskRow) return e.task.startDate;
    return e.sub!.startDate;
  }

  DateTime? _customizedDueKey(_CustomizedFlatEntry e) {
    if (e.isTaskRow) {
      return _landingCalendarDueDay(e.task.endDate);
    }
    return _landingCalendarDueDay(e.sub!.dueDate);
  }

  String _customizedStatusKey(_CustomizedFlatEntry e) {
    if (e.isTaskRow) return TaskListCard.statusLabel(e.task);
    return e.sub!.status;
  }

  String _customizedSubmissionKey(_CustomizedFlatEntry e) {
    if (e.isTaskRow) return e.task.submission ?? '';
    return e.sub!.submission ?? '';
  }

  int _tieBreakCustomizedFlat(_CustomizedFlatEntry a, _CustomizedFlatEntry b) {
    final ta = a.isTaskRow ? a.task.name : a.sub!.subtaskName;
    final tb = b.isTaskRow ? b.task.name : b.sub!.subtaskName;
    return ta.toLowerCase().compareTo(tb.toLowerCase());
  }

  List<_CustomizedFlatEntry> _sortCustomizedFlatEntries(
    List<_CustomizedFlatEntry> rows,
    AppState state,
  ) {
    if (rows.isEmpty) return rows;
    final col = _taskSortColumn;
    final asc = _taskSortAscending;
    final out = List<_CustomizedFlatEntry>.from(rows);
    out.sort((a, b) {
      int c;
      if (col == null) {
        c = _customizedCreateInstant(b).compareTo(_customizedCreateInstant(a));
      } else {
        switch (col) {
          case TaskListSortColumn.creator:
            c = _cmpStrNullable(
              _customizedCreatorKey(a),
              _customizedCreatorKey(b),
              asc,
            );
            break;
          case TaskListSortColumn.assignee:
            c = _cmpStrNullable(
              _customizedAssigneeKey(a, state),
              _customizedAssigneeKey(b, state),
              asc,
            );
            break;
          case TaskListSortColumn.pic:
            c = _cmpStrNullable(
              _customizedPicKey(a, state),
              _customizedPicKey(b, state),
              asc,
            );
            break;
          case TaskListSortColumn.startDate:
            c = _cmpDateForSort(
              _customizedStartKey(a),
              _customizedStartKey(b),
              asc,
            );
            break;
          case TaskListSortColumn.dueDate:
            c = _cmpDateForSort(
              _customizedDueKey(a),
              _customizedDueKey(b),
              asc,
            );
            break;
          case TaskListSortColumn.status:
            c = _cmpStrNullable(
              _customizedStatusKey(a),
              _customizedStatusKey(b),
              asc,
            );
            break;
          case TaskListSortColumn.submission:
            c = _cmpStrNullable(
              _customizedSubmissionKey(a),
              _customizedSubmissionKey(b),
              asc,
            );
            break;
        }
      }
      if (c != 0) return c;
      return _tieBreakCustomizedFlat(a, b);
    });
    return out;
  }

  Widget _customizedEntryTile(
    BuildContext context,
    AppState state,
    _CustomizedFlatEntry e,
  ) {
    if (e.isTaskRow) {
      return TaskListCard(
        task: e.task,
        taskOnly: true,
        showCustomizedTaskTitle: true,
        openedFromOverview: true,
      );
    }
    final s = e.sub!;
    final resolveName = (String id) => state.assigneeById(id)?.name ?? id;
    final picKey = s.pic?.trim();
    return FutureBuilder<String?>(
      future: (picKey == null || picKey.isEmpty)
          ? Future<String?>.value(null)
          : SupabaseService.fetchStaffTeamBusinessIdForAssigneeKey(picKey),
      builder: (context, snap) {
        final tint = TaskListCard.cardColorForPicTeam(snap.data);
        return SingularSubtaskRowCard(
          subtask: s,
          resolveName: resolveName,
          cardMargin: const EdgeInsets.only(bottom: 12),
          cardBackgroundColor: tint,
          showCustomizedLayout: true,
          parentTaskName: e.task.name,
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => SubtaskDetailScreen(
                  subtaskId: s.id,
                  replaceWithParentTaskOnBack: true,
                  openedFromOverview: true,
                ),
              ),
            );
            if (changed == true && mounted) {
              SupabaseService.clearSubtaskListMemoryCache();
              setState(() => _customizedFlatListRefreshSeq++);
            }
          },
        );
      },
    );
  }

  Widget _buildCustomizedFlatFullColumn(
    BuildContext context,
    AppState state,
    List<Task> filteredTasks,
    List<Task> filteredDeletedTasks,
  ) {
    return FutureBuilder<Map<String, List<SingularSubtask>>>(
      key: ValueKey(
        '${filteredTasks.map((t) => t.id).join('|')}'
        '_${filteredDeletedTasks.map((t) => t.id).join('|')}'
        '_$_tasksPageIndex$_tasksPageSize$_deletedTasksPageIndex'
        '_$_customizedFlatListRefreshSeq'
        '_${_taskSearchController.text}'
        '_$_filterCreateDateStart$_filterCreateDateEnd'
        '_$_filterOverdueOnly',
      ),
      future: _futureGroupedForCustomized(filteredTasks, filteredDeletedTasks),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final grouped = snapshot.data ?? {};
        var activeEntries = _buildCustomizedFlatEntries(
          filteredTasks,
          grouped,
          _taskSearchController.text,
        );
        activeEntries = _sortCustomizedFlatEntries(activeEntries, state);
        var delEntries = _buildCustomizedFlatEntries(
          filteredDeletedTasks,
          grouped,
          _taskSearchController.text,
        );
        delEntries = _sortCustomizedFlatEntries(delEntries, state);

        if (activeEntries.isEmpty && delEntries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No tasks or sub-tasks match your filters '
                '(search, create date, and other filters).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }

        final pagedActive = _landingPageSlice(
          activeEntries,
          _tasksPageIndex,
          _tasksPageSize,
        );
        final pagedDel = _landingPageSlice(
          delEntries,
          _deletedTasksPageIndex,
          _tasksPageSize,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kLandingTaskListMaxWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    children: [
                      if (filteredTasks.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Text(
                            'Tasks & sub-tasks (${activeEntries.length})',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: PicTeamColorLegend(),
                        ),
                      ],
                      ...pagedActive.map(
                        (e) => _customizedEntryTile(context, state, e),
                      ),
                      if (filteredDeletedTasks.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 24, bottom: 8),
                          child: Text(
                            'Deleted tasks',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                          ),
                        ),
                        if (filteredTasks.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: PicTeamColorLegend(),
                          ),
                      ],
                      ...pagedDel.map(
                        (e) => _customizedEntryTile(context, state, e),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (activeEntries.isNotEmpty || delEntries.isNotEmpty)
              Material(
                elevation: 6,
                shadowColor: Colors.black26,
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _kLandingTaskListMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (activeEntries.isNotEmpty)
                              _buildLandingTaskPaginationBar(
                                context: context,
                                totalCount: activeEntries.length,
                                pageIndex: _tasksPageIndex,
                                onPageChanged: (i) {
                                  setState(() => _tasksPageIndex = i);
                                },
                                showPageSizeDropdown: true,
                              ),
                            if (activeEntries.isNotEmpty &&
                                delEntries.isNotEmpty)
                              const Divider(height: 12),
                            if (delEntries.isNotEmpty)
                              _buildLandingTaskPaginationBar(
                                context: context,
                                totalCount: delEntries.length,
                                pageIndex: _deletedTasksPageIndex,
                                onPageChanged: (i) {
                                  setState(() => _deletedTasksPageIndex = i);
                                },
                                showPageSizeDropdown: false,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _emptyListMessage() {
    if (_taskSearchController.text.trim().isNotEmpty) {
      return 'No tasks match your search.';
    }
    if (_hasTeamOrStatusFilterSelections) {
      return 'No tasks for this filter.';
    }
    return 'No tasks yet. Create one in the "Create task" tab.';
  }

  @override
  void initState() {
    super.initState();
    _filterAssigneeRootController = ExpansibleController();
    _filterAssigneeTeamController = ExpansibleController();
    _filterAssigneeTeammateTileController = ExpansibleController();
    _filterCreatorRootController = ExpansibleController();
    _filterCreatorTeamController = ExpansibleController();
    _filterCreatorTeammateTileController = ExpansibleController();
    _filterStatusTileController = ExpansibleController();
    _filterOverdueTileController = ExpansibleController();
    _filterSubmissionTileController = ExpansibleController();
    _filterCreateDateTileController = ExpansibleController();
    _taskSearchController.addListener(_onSearchTextChangedForPersist);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _appStateListenerRef = context.read<AppState>();
      _appStateListenerRef!.addListener(_onAppStateForDeferredTeamRestore);
      _loadLandingFilters();
    });
  }

  void _onSearchTextChangedForPersist() {
    if (!_landingFiltersPrefsReady || _suppressFilterPersist) return;
    _searchPersistDebounce?.cancel();
    _searchPersistDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _persistLandingFilters();
    });
  }

  void _onAppStateForDeferredTeamRestore() {
    if (_deferredPrefsForTeams == null) return;
    final state = context.read<AppState>();
    if (state.teams.isEmpty) return;
    final data = _deferredPrefsForTeams!;
    _deferredPrefsForTeams = null;
    if (!mounted) return;
    setState(() => _applyTeamsAndAssigneesFromSaved(data, state));
    _landingFiltersPrefsReady = true;
  }

  Future<void> _loadLandingFilters() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _landingFiltersPrefsReady = true;
      return;
    }
    final data = await LandingTaskFiltersStorage.load(uid);
    if (!mounted) return;
    final state = context.read<AppState>();
    if (data == null) {
      _landingFiltersPrefsReady = true;
      return;
    }
    final needsDefer = data.teamIds.isNotEmpty && state.teams.isEmpty;
    if (needsDefer) {
      _deferredPrefsForTeams = data;
      setState(() => _applySavedFiltersPartial(data, state));
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (!mounted || _landingFiltersPrefsReady) return;
        if (_deferredPrefsForTeams != null &&
            context.read<AppState>().teams.isEmpty) {
          _deferredPrefsForTeams = null;
          _landingFiltersPrefsReady = true;
        }
      });
      return;
    }
    setState(() => _applySavedFiltersFull(data, state));
    _landingFiltersPrefsReady = true;
  }

  void _applySavedFiltersPartial(LandingTaskFilters data, AppState state) {
    var ft = data.filterType;
    if (ft == 'my') ft = 'all';
    if (ft != 'all' && ft != 'assigned' && ft != 'created') ft = 'all';
    _filterType = ft;
    _selectedTaskStatuses.clear();
    for (final s in data.statuses) {
      if (s == _statusIncomplete ||
          s == _statusCompleted ||
          s == _statusDeleted) {
        _selectedTaskStatuses.add(s);
      }
    }
    _selectedSubmissionFilters.clear();
    for (final s in data.submissionFilters) {
      if (s == _submissionPending ||
          s == _submissionSubmitted ||
          s == _submissionAccepted ||
          s == _submissionReturned) {
        _selectedSubmissionFilters.add(s);
      }
    }
    _suppressFilterPersist = true;
    try {
      _taskSearchController.text = data.search;
      _lastSubtaskSearchQueryForBlob = data.search.trim();
      _subtaskSearchBlobByTaskId.clear();
      _subtaskFetchGeneration++;
      _landingSubtaskServerSearchSeq++;
      _subtaskServerSetsByToken = null;
      _subtaskServerQueryNormalized = '';
    } finally {
      _suppressFilterPersist = false;
    }
    _landingSubtaskServerSearchDebounce?.cancel();
    _scheduleLandingSubtaskServerSearch();
    _taskSortColumn = TaskListSortColumn.fromStorage(data.sortColumn);
    _taskSortAscending = data.sortAscending;
    _filterOverdueOnly = data.filterOverdueOnly;
    _filterCreateDateStart = data.filterCreateDateStartMs != null
        ? DateTime.fromMillisecondsSinceEpoch(data.filterCreateDateStartMs!)
        : null;
    _filterCreateDateEnd = data.filterCreateDateEndMs != null
        ? DateTime.fromMillisecondsSinceEpoch(data.filterCreateDateEndMs!)
        : null;
  }

  void _applyTeamsAndAssigneesFromSaved(LandingTaskFilters data, AppState state) {
    _restoreMenuRoleFiltersFromSaved(data, state);
  }

  void _restoreMenuRoleFiltersFromSaved(
    LandingTaskFilters data,
    AppState state,
  ) {
    final validTeamIds = state.teams.map((t) => t.id).toSet();
    final at = data.filterAssigneeTeamId?.trim();
    if (at != null && at.isNotEmpty && validTeamIds.contains(at)) {
      _filterAssigneeMenuTeamId = at;
      _filterAssigneeMenuStaffIds.clear();
      final assigneeMembers =
          _getTeamMembers(state, at).map((e) => e.id).toSet();
      for (final id in data.filterAssigneeStaffIds) {
        if (assigneeMembers.contains(id)) _filterAssigneeMenuStaffIds.add(id);
      }
    } else {
      _filterAssigneeMenuTeamId = null;
      _filterAssigneeMenuStaffIds.clear();
    }
    final ct = data.filterCreatorTeamId?.trim();
    if (ct != null && ct.isNotEmpty && validTeamIds.contains(ct)) {
      _filterCreatorMenuTeamId = ct;
      _filterCreatorMenuStaffIds.clear();
      final creatorMembers = _getTeamMembers(state, ct).map((e) => e.id).toSet();
      for (final id in data.filterCreatorStaffIds) {
        if (creatorMembers.contains(id)) _filterCreatorMenuStaffIds.add(id);
      }
    } else {
      _filterCreatorMenuTeamId = null;
      _filterCreatorMenuStaffIds.clear();
    }
  }

  void _applySavedFiltersFull(LandingTaskFilters data, AppState state) {
    _applySavedFiltersPartial(data, state);
    _applyTeamsAndAssigneesFromSaved(data, state);
  }

  void _persistLandingFilters() {
    if (!_landingFiltersPrefsReady || _suppressFilterPersist) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    LandingTaskFiltersStorage.save(
      uid,
      LandingTaskFilters(
        filterType: _filterType,
        teamIds: const [],
        assigneeIds: const [],
        statuses: _selectedTaskStatuses.toList(),
        submissionFilters: _selectedSubmissionFilters.toList(),
        filterOverdueOnly: _filterOverdueOnly,
        search: _taskSearchController.text,
        sortColumn: _taskSortColumn?.storageKey,
        sortAscending: _taskSortAscending,
        filterAssigneeTeamId: _filterAssigneeMenuTeamId,
        filterAssigneeStaffIds: _filterAssigneeMenuStaffIds.toList(),
        filterCreatorTeamId: _filterCreatorMenuTeamId,
        filterCreatorStaffIds: _filterCreatorMenuStaffIds.toList(),
        filterCreateDateStartMs: _filterCreateDateStart?.millisecondsSinceEpoch,
        filterCreateDateEndMs: _filterCreateDateEnd?.millisecondsSinceEpoch,
      ),
    );
  }

  @override
  void dispose() {
    _landingSubtaskServerSearchDebounce?.cancel();
    _searchPersistDebounce?.cancel();
    _taskSearchController.removeListener(_onSearchTextChangedForPersist);
    _appStateListenerRef?.removeListener(_onAppStateForDeferredTeamRestore);
    _filterAssigneeRootController.dispose();
    _filterAssigneeTeamController.dispose();
    _filterAssigneeTeammateTileController.dispose();
    _filterCreatorRootController.dispose();
    _filterCreatorTeamController.dispose();
    _filterCreatorTeammateTileController.dispose();
    _filterStatusTileController.dispose();
    _filterOverdueTileController.dispose();
    _filterSubmissionTileController.dispose();
    _filterCreateDateTileController.dispose();
    _taskSearchController.dispose();
    super.dispose();
  }

  Widget _buildSortColumnControl(TaskListSortColumn column) {
    final active = _taskSortColumn == column;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'Sort by ${column.label}',
        onSelected: (v) {
          setState(() {
            if (v == 'clear') {
              if (_taskSortColumn == column) {
                _taskSortColumn = null;
                _taskSortAscending = true;
              }
            } else if (v == 'asc') {
              _taskSortColumn = column;
              _taskSortAscending = true;
            } else if (v == 'desc') {
              _taskSortColumn = column;
              _taskSortAscending = false;
            }
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'asc', child: Text('Ascending')),
          const PopupMenuItem(value: 'desc', child: Text('Descending')),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'clear',
            enabled: active,
            child: const Text('Clear sort'),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                column.label,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  _taskSortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static int _landingLastPageIndex(int itemCount, int pageSize) {
    if (itemCount <= 0 || pageSize <= 0) return 0;
    return (itemCount - 1) ~/ pageSize;
  }

  static List<T> _landingPageSlice<T>(
    List<T> items,
    int pageIndex,
    int pageSize,
  ) {
    if (items.isEmpty || pageSize <= 0) return const [];
    final last = _landingLastPageIndex(items.length, pageSize);
    final p = pageIndex.clamp(0, last);
    final start = p * pageSize;
    final end = min(start + pageSize, items.length);
    return items.sublist(start, end);
  }

  Widget _buildLandingTaskPaginationBar({
    required BuildContext context,
    required int totalCount,
    required int pageIndex,
    required void Function(int newPageIndex) onPageChanged,
    required bool showPageSizeDropdown,
  }) {
    if (totalCount <= 0) return const SizedBox.shrink();
    final lastPage = _landingLastPageIndex(totalCount, _tasksPageSize);
    final cur = pageIndex.clamp(0, lastPage);
    final from = cur * _tasksPageSize + 1;
    final to = min((cur + 1) * _tasksPageSize, totalCount);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.zero,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (showPageSizeDropdown)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Per page',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _tasksPageSize,
                  items: _landingTaskPageSizes
                      .map(
                        (n) => DropdownMenuItem<int>(
                          value: n,
                          child: Text('$n'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _tasksPageSize = v;
                      _tasksPageIndex = 0;
                      _deletedTasksPageIndex = 0;
                    });
                  },
                ),
              ],
            ),
          Text(
            'Page ${cur + 1} of ${lastPage + 1} · $from–$to of $totalCount',
            style: theme.textTheme.bodySmall,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: cur > 0
                    ? () => onPageChanged(cur - 1)
                    : null,
                child: const Text('Previous'),
              ),
              TextButton(
                onPressed: cur < lastPage
                    ? () => onPageChanged(cur + 1)
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Landing Tasks tab — same width as the task list column below.
  Widget _buildLandingTaskSearchField() {
    return TextField(
      controller: _taskSearchController,
      onChanged: (value) {
        final q = value.trim();
        if (q != _lastSubtaskSearchQueryForBlob) {
          _lastSubtaskSearchQueryForBlob = q;
          _subtaskSearchBlobByTaskId.clear();
          _subtaskFetchGeneration++;
        }
        _landingSubtaskServerSearchSeq++;
        _scheduleLandingSubtaskServerSearch();
        setState(() {
          _tasksPageIndex = 0;
          _deletedTasksPageIndex = 0;
        });
      },
      decoration: InputDecoration(
        labelText: 'Search',
        hintText:
            'Search task, description, sub-task, sub-task description',
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _taskSearchController.text.isNotEmpty
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _landingSubtaskServerSearchDebounce?.cancel();
                  _landingSubtaskServerSearchSeq++;
                  setState(() {
                    _taskSearchController.clear();
                    _lastSubtaskSearchQueryForBlob = '';
                    _subtaskSearchBlobByTaskId.clear();
                    _subtaskFetchGeneration++;
                    _subtaskServerSetsByToken = null;
                    _subtaskServerQueryNormalized = '';
                    _tasksPageIndex = 0;
                    _deletedTasksPageIndex = 0;
                  });
                },
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_filterType == 'my') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _filterType = 'all');
          _persistLandingFilters();
        }
      });
    }
    final state = context.watch<AppState>();
    final teamsSorted = [...state.teams]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    const allTeams = <String>{};
    var initiatives = state.initiativesForTeams(allTeams);
    var tasks = state.tasksForTeams(allTeams);

    final singularSig = _singularTaskIdsSignature(state);
    if (singularSig != _cachedSingularTaskIdsSig) {
      _cachedSingularTaskIdsSig = singularSig;
      _subtaskFetchGeneration++;
      _subtaskMinDueByTaskId.clear();
      _subtaskMaxDueByTaskId.clear();
      _subtaskHasOverdueByTaskId.clear();
      _subtaskSearchBlobByTaskId.clear();
      SupabaseService.clearSubtaskListMemoryCache();
      _landingSubtaskServerSearchSeq++;
      _landingSubtaskServerSearchDebounce?.cancel();
      _subtaskServerSetsByToken = null;
      _subtaskServerQueryNormalized = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scheduleLandingSubtaskServerSearch();
      });
    }

    if (_filterAssigneeMenuStaffIds.isNotEmpty) {
      initiatives = initiatives
          .where((i) => i.directorIds.any(_filterAssigneeMenuStaffIds.contains))
          .toList();
      tasks = tasks
          .where((t) => t.assigneeIds.any(_filterAssigneeMenuStaffIds.contains))
          .toList();
    }
    if (_filterCreatorMenuStaffIds.isNotEmpty) {
      tasks = tasks
          .where((t) {
            final k = t.createByAssigneeKey?.trim();
            return k != null &&
                k.isNotEmpty &&
                _filterCreatorMenuStaffIds.contains(k);
          })
          .toList();
    }

    bool singularDeleted(Task t) {
      if (!t.isSingularTableRow) return false;
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      return s == 'delete' || s == 'deleted';
    }

    bool singularCompleted(Task t) {
      if (!t.isSingularTableRow) return false;
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      return s == 'completed' || s == 'complete';
    }

    bool singularIncomplete(Task t) {
      if (!t.isSingularTableRow) return false;
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      if (s.isEmpty) return true;
      return s == 'incomplete';
    }

    final tasksNonDeleted = tasks.where((t) => !singularDeleted(t)).toList();
    final tasksDeletedSingular = tasks.where(singularDeleted).toList();
    final mine = state.userStaffAppId?.trim();
    bool hasMine() => mine != null && mine.isNotEmpty;
    bool isAssignedToMe(Task t) => hasMine() && t.assigneeIds.contains(mine!);
    bool isCreatedByMe(Task t) => state.taskIsCreatedByCurrentUser(t);

    final filterKey = _filterType == 'my' ? 'all' : _filterType;

    bool taskMatchesSubmissionSelection(Task t) {
      if (_selectedSubmissionFilters.isEmpty) return true;
      return _selectedSubmissionFilters.contains(_submissionFilterKey(t));
    }

    bool nonDeletedMatchesTaskStatus(Task t) {
      if (_selectedTaskStatuses.isEmpty) {
        return taskMatchesSubmissionSelection(t);
      }
      if (singularDeleted(t)) return false;
      if (t.isSingularTableRow) {
        if (_selectedTaskStatuses.contains(_statusIncomplete) &&
            singularIncomplete(t)) {
          return taskMatchesSubmissionSelection(t);
        }
        if (_selectedTaskStatuses.contains(_statusCompleted) &&
            singularCompleted(t)) {
          return taskMatchesSubmissionSelection(t);
        }
        return false;
      }
      if (_selectedTaskStatuses.contains(_statusIncomplete) &&
          t.status != TaskStatus.done) {
        return taskMatchesSubmissionSelection(t);
      }
      if (_selectedTaskStatuses.contains(_statusCompleted) &&
          t.status == TaskStatus.done) {
        return taskMatchesSubmissionSelection(t);
      }
      return false;
    }

    bool deletedMatchesTaskStatus(Task t) {
      if (!singularDeleted(t)) return false;
      if (_selectedTaskStatuses.isEmpty) return false;
      if (!_selectedTaskStatuses.contains(_statusDeleted)) return false;
      return taskMatchesSubmissionSelection(t);
    }

    bool shouldShowDeletedSection() {
      if (_selectedTaskStatuses.isEmpty) return false;
      return _selectedTaskStatuses.contains(_statusDeleted);
    }

    List<Task> filterTasksWithScopeAndStatus(
      List<Task> source,
      bool Function(Task) statusMatch,
    ) {
      Iterable<Task> it = source;
      if (filterKey == 'assigned') {
        it = it.where(isAssignedToMe);
      } else if (filterKey == 'created') {
        it = it.where(isCreatedByMe);
      }
      return it.where(statusMatch).toList();
    }

    List<Initiative> filteredInitiatives = [];
    List<Task> filteredTasks = [];
    List<Task> filteredDeletedTasks = [];

    if (filterKey == 'all') {
      filteredInitiatives = initiatives;
      filteredTasks = filterTasksWithScopeAndStatus(
        tasksNonDeleted,
        nonDeletedMatchesTaskStatus,
      );
      filteredDeletedTasks = shouldShowDeletedSection()
          ? filterTasksWithScopeAndStatus(
              tasksDeletedSingular,
              deletedMatchesTaskStatus,
            )
          : [];
    } else if (filterKey == 'assigned') {
      filteredInitiatives = [];
      filteredTasks = filterTasksWithScopeAndStatus(
        tasksNonDeleted,
        nonDeletedMatchesTaskStatus,
      );
      filteredDeletedTasks = shouldShowDeletedSection()
          ? filterTasksWithScopeAndStatus(
              tasksDeletedSingular,
              deletedMatchesTaskStatus,
            )
          : [];
    } else if (filterKey == 'created') {
      filteredInitiatives = [];
      filteredTasks = filterTasksWithScopeAndStatus(
        tasksNonDeleted,
        nonDeletedMatchesTaskStatus,
      );
      filteredDeletedTasks = shouldShowDeletedSection()
          ? filterTasksWithScopeAndStatus(
              tasksDeletedSingular,
              deletedMatchesTaskStatus,
            )
          : [];
    }

    bool taskMatchesOverdueFilter(Task t) {
      if (!_filterOverdueOnly) return true;
      if (t.isSingularTableRow) {
        if (t.overdue == 'Yes') return true;
        if (!_subtaskHasOverdueByTaskId.containsKey(t.id)) return false;
        return _subtaskHasOverdueByTaskId[t.id] == true;
      }
      return t.overdue == 'Yes';
    }

    final tasksForSubtaskPrefetch = List<Task>.from(filteredTasks);
    final deletedForSubtaskPrefetch = List<Task>.from(filteredDeletedTasks);
    if (_filterOverdueOnly) {
      filteredInitiatives = [];
      filteredTasks = filteredTasks.where(taskMatchesOverdueFilter).toList();
      filteredDeletedTasks =
          filteredDeletedTasks.where(taskMatchesOverdueFilter).toList();
    }

    filteredInitiatives = _applyInitiativeNameSearch(filteredInitiatives);
    // Run after this frame so [onChanged] blob invalidation (clear + generation bump) is applied
    // before we decide which task ids still need [fetchSubtasksForTask].
    final prefetchTasks = List<Task>.from(tasksForSubtaskPrefetch);
    final prefetchDeleted = List<Task>.from(deletedForSubtaskPrefetch);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleSubtaskRowDataPrefetch(prefetchTasks, prefetchDeleted);
    });
    filteredTasks = _applyTaskSearch(filteredTasks);
    filteredDeletedTasks = _applyTaskSearch(filteredDeletedTasks);
    if (_filterCreateDateEngaged && !widget.customizedFlat) {
      bool taskCreateDayOk(Task t) {
        final day =
            DateTime(t.createdAt.year, t.createdAt.month, t.createdAt.day);
        return _calendarDayInCreateFilterRange(day);
      }
      filteredTasks = filteredTasks.where(taskCreateDayOk).toList();
      filteredDeletedTasks =
          filteredDeletedTasks.where(taskCreateDayOk).toList();
    }
    if (!widget.customizedFlat) {
      filteredTasks = _sortTasks(filteredTasks, state);
      filteredDeletedTasks = _sortTasks(filteredDeletedTasks, state);
    }

    List<Task> customizedFlatActiveTasks = filteredTasks;
    if (widget.customizedFlat &&
        _selectedTaskStatuses.contains(_statusCompleted) &&
        !_selectedTaskStatuses.contains(_statusIncomplete)) {
      final byId = {for (final t in filteredTasks) t.id: t};
      Iterable<Task> scopeIt = tasksNonDeleted;
      if (filterKey == 'assigned') {
        scopeIt = scopeIt.where(isAssignedToMe);
      } else if (filterKey == 'created') {
        scopeIt = scopeIt.where(isCreatedByMe);
      }
      for (final t in scopeIt) {
        if (!t.isSingularTableRow || byId.containsKey(t.id)) continue;
        if (!_singularTaskIncomplete(t)) continue;
        if (_selectedSubmissionFilters.isNotEmpty &&
            !taskMatchesSubmissionSelection(t)) {
          continue;
        }
        byId[t.id] = t;
      }
      customizedFlatActiveTasks = byId.values.toList();
    }

    final pagedTasks = widget.customizedFlat
        ? const <Task>[]
        : _landingPageSlice(
            filteredTasks,
            _tasksPageIndex,
            _tasksPageSize,
          );
    final pagedDeletedTasks = widget.customizedFlat
        ? const <Task>[]
        : _landingPageSlice(
            filteredDeletedTasks,
            _deletedTasksPageIndex,
            _tasksPageSize,
          );

    final reminders = state.getPendingRemindersForTeams(allTeams);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reminders.isNotEmpty && !widget.customizedFlat)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ExpansionTile(
              title: const Text('Reminders (would send to Directors)'),
              initiallyExpanded: _remindersExpanded,
              onExpansionChanged: (v) => setState(() => _remindersExpanded = v),
              children: reminders
                  .map(
                    (r) => ListTile(
                      title: Text(r.itemName),
                      subtitle: Text(
                        '${r.reminderType} → ${r.recipientNames.join(", ")}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final menuMaxHeight = MediaQuery.sizeOf(context).height * 0.65;

              final wideFilterWidth = min(
                280.0,
                constraints.maxWidth * 0.38,
              ).clamp(120.0, _filterFieldMaxWidth);

              final filterMenu = MenuAnchor(
                controller: _filterMenuController,
                onClose: _onFilterMenuAnchorClosed,
                menuChildren: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: SizedBox(
                      width: 320,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: menuMaxHeight),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ..._landingFilterMenuSections(
                                context,
                                state,
                                teamsSorted,
                              ),
                              ..._landingCreateDateSection(context),
                              ..._landingStatusSubmissionSections(context),
                              const Divider(height: 16),
                              MenuItemButton(
                                closeOnActivate: false,
                                onPressed: _clearTeamAndStatusFilters,
                                leadingIcon: const Icon(
                                  Icons.clear_all,
                                  size: 20,
                                ),
                                child: const Text('Clear all'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                builder: (context, controller, child) {
                  final summaryLine = _filterMenuSummaryLine(state);
                  return Tooltip(
                    message: summaryLine,
                    child: InkWell(
                      onTap: () {
                        if (controller.isOpen) {
                          controller.close();
                        } else {
                          controller.open();
                        }
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Filters',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.arrow_drop_down),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        child: Text(
                          summaryLine,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  );
                },
              );

              final filterWidth = constraints.maxWidth < 600
                  ? min(_filterFieldMaxWidth, constraints.maxWidth)
                  : wideFilterWidth;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: filterWidth),
                      child: filterMenu,
                ),
              ),
            ],
              );
            },
          ),
        ),
        if (_hasTeamOrStatusFilterSelections)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _clearTeamAndStatusFilters,
                child: const Text('Clear all'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                  _buildTaskFilterChip(
                    value: 'all',
                    label: 'All',
                    selected: filterKey == 'all',
                    selectedBg: null,
                    selectedLabelColor: null,
                    leading: null,
                  ),
                  _buildTaskFilterChip(
                    value: 'assigned',
                    label: 'Assigned to me',
                    selected: filterKey == 'assigned',
                    selectedBg: const Color(0xFF0D47A1),
                    selectedLabelColor: Colors.white,
                    leading: _assignedToMeFilterIcon(filterKey == 'assigned'),
                  ),
                  _buildTaskFilterChip(
                    value: 'created',
                    label: 'My created tasks',
                    selected: filterKey == 'created',
                    selectedBg: Colors.lightBlue.shade200,
                    selectedLabelColor: Colors.black87,
                    leading: _myCreatedTasksFilterIcon(filterKey == 'created'),
                  ),
                      Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      height: 32,
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                        child: Text(
                      'Sort',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  for (final col in TaskListSortColumn.values)
                    _buildSortColumnControl(col),
                ],
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final listColumnMaxWidth = min(
              _kLandingTaskListMaxWidth,
              constraints.maxWidth,
            );
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: listColumnMaxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _buildLandingTaskSearchField(),
                ),
              ),
            );
          },
        ),
        Expanded(
          child: filteredInitiatives.isEmpty &&
                  filteredTasks.isEmpty &&
                  filteredDeletedTasks.isEmpty
              ? Center(child: Text(_emptyListMessage()))
              : widget.customizedFlat
                  ? _buildCustomizedFlatFullColumn(
                      context,
                      state,
                      customizedFlatActiveTasks,
                      filteredDeletedTasks,
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: _kLandingTaskListMaxWidth,
                              ),
                              child: ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                children: [
                                  if (filteredInitiatives.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 8,
                                        bottom: 8,
                                      ),
                                      child: Text(
                                        'Initiatives',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    ...filteredInitiatives.map(
                                      (init) => _buildInitiativeCard(
                                        context,
                                        state,
                                        init,
                                      ),
                                    ),
                                  ],
                                  if (filteredTasks.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 16,
                                        bottom: 8,
                                      ),
                                      child: Text(
                                        'Tasks (${filteredTasks.length})',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: PicTeamColorLegend(),
                                    ),
                                    ...pagedTasks.map(
                                      (t) => TaskListCard(task: t),
                                    ),
                                  ],
                                  if (filteredDeletedTasks.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 24,
                                        bottom: 8,
                                      ),
                                      child: Text(
                                        'Deleted tasks',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                            ),
                                      ),
                                    ),
                                    if (filteredTasks.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.only(bottom: 12),
                                        child: PicTeamColorLegend(),
                                      ),
                                    ...pagedDeletedTasks.map(
                                      (t) => TaskListCard(task: t),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (filteredTasks.isNotEmpty ||
                            filteredDeletedTasks.isNotEmpty)
                          Material(
                        elevation: 6,
                        shadowColor: Colors.black26,
                        color: Theme.of(context).colorScheme.surface,
                        child: SafeArea(
                          top: false,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: _kLandingTaskListMaxWidth,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  6,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (filteredTasks.isNotEmpty)
                                      _buildLandingTaskPaginationBar(
                                        context: context,
                                        totalCount: filteredTasks.length,
                                        pageIndex: _tasksPageIndex,
                                        onPageChanged: (i) {
                                          setState(() => _tasksPageIndex = i);
                                        },
                                        showPageSizeDropdown: true,
                                      ),
                                    if (filteredTasks.isNotEmpty &&
                                        filteredDeletedTasks.isNotEmpty)
                                      const Divider(height: 12),
                                    if (filteredDeletedTasks.isNotEmpty)
                                      _buildLandingTaskPaginationBar(
                                        context: context,
                                        totalCount:
                                            filteredDeletedTasks.length,
                                        pageIndex: _deletedTasksPageIndex,
                                        onPageChanged: (i) {
                                          setState(
                                            () => _deletedTasksPageIndex = i,
                                          );
                                        },
                                        showPageSizeDropdown: false,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Assignee or Creator: root [ExpansionTile] → **Team** → **Teammate** (checkboxes).
  Widget _landingTeamStaffFilterExpansion(
    BuildContext context, {
    required String sectionTitle,
    required String topSectionId,
    required ExpansibleController rootController,
    required ExpansibleController teamController,
    required List<Team> teamsSorted,
    required String? rosterTeamId,
    required List<Assignee> teammates,
    required Set<String> staffIds,
    required void Function(String teamId) onSelectTeam,
    required VoidCallback onClearAllStaff,
    required void Function(String staffId, bool selected) onStaffSelectionChanged,
    required ExpansibleController teammateExpansionController,
  }) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
    const innerTilePadding = EdgeInsets.fromLTRB(12, 0, 4, 0);

    return ExpansionTile(
      controller: rootController,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(sectionTitle, style: titleStyle),
      onExpansionChanged: (expanded) {
        if (expanded) _onTopLevelFilterSectionExpanded(topSectionId);
      },
      children: [
        ExpansionTile(
          controller: teamController,
          tilePadding: innerTilePadding,
          title: const Text('Team'),
          onExpansionChanged: (expanded) {
            if (expanded) {
              _onTeamStaffNestedSectionExpanded(
                rootId: topSectionId,
                openedNestedId: 'team',
              );
            }
          },
          children: teamsSorted.isEmpty
              ? const [
                  ListTile(
                    dense: true,
                    enabled: false,
                    title: Text('No teams loaded'),
                  ),
                ]
              : teamsSorted
                  .map(
                    (t) => MenuItemButton(
                      closeOnActivate: false,
                      onPressed: () {
                        onSelectTeam(t.id);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (context.mounted) {
                            teammateExpansionController.expand();
                          }
                        });
                      },
                      child: Row(
                        children: [
                          Expanded(child: Text(t.name)),
                          if (rosterTeamId == t.id)
                            Icon(
                              Icons.check,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
        ),
        ExpansionTile(
          controller: teammateExpansionController,
          tilePadding: innerTilePadding,
          title: const Text('Teammate'),
          onExpansionChanged: (expanded) {
            if (expanded) {
              _onTeamStaffNestedSectionExpanded(
                rootId: topSectionId,
                openedNestedId: 'teammate',
              );
            }
          },
          children: rosterTeamId == null
              ? const [
                  ListTile(
                    dense: true,
                    enabled: false,
                    title: Text('Select a team first'),
                  ),
                ]
              : [
                  CheckboxMenuButton(
                    closeOnActivate: false,
                    value: staffIds.isEmpty,
                    onChanged: (bool? v) {
                      if (v != true) return;
                      onClearAllStaff();
                    },
                    child: const Text('All teammates'),
                  ),
                  ...teammates.map(
                    (a) => CheckboxMenuButton(
                      closeOnActivate: false,
                      value: staffIds.contains(a.id),
                      onChanged: (bool? v) {
                        if (v == null) return;
                        onStaffSelectionChanged(a.id, v);
                      },
                      child: Text(a.name),
                    ),
                  ),
                ],
        ),
      ],
    );
  }

  /// Create date range — below Creator; applies to task/sub-task create dates on Customized,
  /// and to task `createdAt` on the landing list.
  List<Widget> _landingCreateDateSection(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
    final fmt = DateFormat.yMMMd();
    final def = _defaultCreateDateRangeHk();

    Future<void> pickStart() async {
      final now = DateTime.now();
      final initial = _filterCreateDateStart ?? now;
      final d = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 5),
      );
      if (d == null || !mounted) return;
      setState(() {
        _filterCreateDateStart = d;
        _tasksPageIndex = 0;
        _deletedTasksPageIndex = 0;
      });
      _persistLandingFilters();
    }

    Future<void> pickEnd() async {
      final now = DateTime.now();
      final initial = _filterCreateDateEnd ?? _filterCreateDateStart ?? now;
      final d = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 5),
      );
      if (d == null || !mounted) return;
      setState(() {
        _filterCreateDateEnd = d;
        _tasksPageIndex = 0;
        _deletedTasksPageIndex = 0;
      });
      _persistLandingFilters();
    }

    void clearCreateDate() {
      setState(() {
        _filterCreateDateStart = null;
        _filterCreateDateEnd = null;
        _tasksPageIndex = 0;
        _deletedTasksPageIndex = 0;
      });
      _persistLandingFilters();
    }

    return [
      ExpansionTile(
        controller: _filterCreateDateTileController,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Create date', style: titleStyle),
        onExpansionChanged: (expanded) {
          if (expanded) _onTopLevelFilterSectionExpanded('createDate');
        },
        children: [
          ListTile(
            dense: true,
            title: const Text('From'),
            subtitle: Text(
              _filterCreateDateStart == null
                  ? 'Default: ${fmt.format(def.$1)}'
                  : fmt.format(_filterCreateDateStart!),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_calendar_outlined, size: 22),
              onPressed: pickStart,
              tooltip: 'Set start date',
            ),
            onTap: pickStart,
          ),
          ListTile(
            dense: true,
            title: const Text('To'),
            subtitle: Text(
              _filterCreateDateEnd == null
                  ? 'Default: ${fmt.format(def.$2)}'
                  : fmt.format(_filterCreateDateEnd!),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_calendar_outlined, size: 22),
              onPressed: pickEnd,
              tooltip: 'Set end date',
            ),
            onTap: pickEnd,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: TextButton(
              onPressed: _filterCreateDateEngaged ? clearCreateDate : null,
              child: const Text('Clear create date range'),
            ),
          ),
        ],
      ),
    ];
  }

  /// Status / Submission: expandable sections with [CheckboxMenuButton].
  List<Widget> _landingStatusSubmissionSections(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
    return [
      ExpansionTile(
        controller: _filterStatusTileController,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Status', style: titleStyle),
        onExpansionChanged: (expanded) {
          if (expanded) _onTopLevelFilterSectionExpanded('status');
        },
        children: [
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedTaskStatuses.contains(_statusIncomplete),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedTaskStatuses.add(_statusIncomplete);
                } else {
                  _selectedTaskStatuses.remove(_statusIncomplete);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Incomplete'),
          ),
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedTaskStatuses.contains(_statusCompleted),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedTaskStatuses.add(_statusCompleted);
                } else {
                  _selectedTaskStatuses.remove(_statusCompleted);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Completed'),
          ),
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedTaskStatuses.contains(_statusDeleted),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedTaskStatuses.add(_statusDeleted);
                } else {
                  _selectedTaskStatuses.remove(_statusDeleted);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Deleted'),
          ),
        ],
      ),
      ExpansionTile(
        controller: _filterOverdueTileController,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Overdue', style: titleStyle),
        onExpansionChanged: (expanded) {
          if (expanded) _onTopLevelFilterSectionExpanded('overdue');
        },
        children: [
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _filterOverdueOnly,
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                _filterOverdueOnly = v;
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Show only overdue tasks/ sub-tasks'),
          ),
        ],
      ),
      ExpansionTile(
        controller: _filterSubmissionTileController,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Submission', style: titleStyle),
        onExpansionChanged: (expanded) {
          if (expanded) _onTopLevelFilterSectionExpanded('submission');
        },
        children: [
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedSubmissionFilters.contains(_submissionPending),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedSubmissionFilters.add(_submissionPending);
                } else {
                  _selectedSubmissionFilters.remove(_submissionPending);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Pending'),
          ),
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedSubmissionFilters.contains(_submissionSubmitted),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedSubmissionFilters.add(_submissionSubmitted);
                } else {
                  _selectedSubmissionFilters.remove(_submissionSubmitted);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Submitted'),
          ),
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedSubmissionFilters.contains(_submissionAccepted),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedSubmissionFilters.add(_submissionAccepted);
                } else {
                  _selectedSubmissionFilters.remove(_submissionAccepted);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Accepted'),
          ),
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedSubmissionFilters.contains(_submissionReturned),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedSubmissionFilters.add(_submissionReturned);
                } else {
                  _selectedSubmissionFilters.remove(_submissionReturned);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Returned'),
          ),
        ],
      ),
    ];
  }

  /// Filter [MenuAnchor] body: expandable Assignee / Creator → Team → Teammate.
  List<Widget> _landingFilterMenuSections(
    BuildContext context,
    AppState state,
    List<Team> teamsSorted,
  ) {
    String? rosterTeamIdOrNull(String? stored) {
      if (stored == null || stored.isEmpty) return null;
      return teamsSorted.any((t) => t.id == stored) ? stored : null;
    }

    final assigneeTeamField = rosterTeamIdOrNull(_filterAssigneeMenuTeamId);
    final creatorTeamField = rosterTeamIdOrNull(_filterCreatorMenuTeamId);
    final assigneeMembers = assigneeTeamField == null
        ? <Assignee>[]
        : _getTeamMembers(state, assigneeTeamField);
    final creatorMembers = creatorTeamField == null
        ? <Assignee>[]
        : _getTeamMembers(state, creatorTeamField);

    return [
      _landingTeamStaffFilterExpansion(
        context,
        sectionTitle: 'Assignee',
        topSectionId: 'assignee',
        rootController: _filterAssigneeRootController,
        teamController: _filterAssigneeTeamController,
        teamsSorted: teamsSorted,
        rosterTeamId: assigneeTeamField,
        teammates: assigneeMembers,
        staffIds: _filterAssigneeMenuStaffIds,
        teammateExpansionController: _filterAssigneeTeammateTileController,
        onSelectTeam: (teamId) {
          setState(() {
            _filterAssigneeMenuTeamId = teamId;
            _filterAssigneeMenuStaffIds.clear();
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        onClearAllStaff: () {
          setState(() {
            _filterAssigneeMenuStaffIds.clear();
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        onStaffSelectionChanged: (id, selected) {
          setState(() {
            if (selected) {
              _filterAssigneeMenuStaffIds.add(id);
            } else {
              _filterAssigneeMenuStaffIds.remove(id);
            }
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
      ),
      _landingTeamStaffFilterExpansion(
        context,
        sectionTitle: 'Creator',
        topSectionId: 'creator',
        rootController: _filterCreatorRootController,
        teamController: _filterCreatorTeamController,
        teamsSorted: teamsSorted,
        rosterTeamId: creatorTeamField,
        teammates: creatorMembers,
        staffIds: _filterCreatorMenuStaffIds,
        teammateExpansionController: _filterCreatorTeammateTileController,
        onSelectTeam: (teamId) {
          setState(() {
            _filterCreatorMenuTeamId = teamId;
            _filterCreatorMenuStaffIds.clear();
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        onClearAllStaff: () {
          setState(() {
            _filterCreatorMenuStaffIds.clear();
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        onStaffSelectionChanged: (id, selected) {
          setState(() {
            if (selected) {
              _filterCreatorMenuStaffIds.add(id);
            } else {
              _filterCreatorMenuStaffIds.remove(id);
            }
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
      ),
    ];
  }

  List<Assignee> _getTeamMembers(AppState state, String teamId) {
    try {
      final team = state.teams.firstWhere((t) => t.id == teamId);
      final allMemberIds = [...team.directorIds, ...team.officerIds];
      return allMemberIds
          .map((id) => state.assigneeById(id))
          .whereType<Assignee>()
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return [];
    }
  }

  static Color _progressColor(int percent) {
    if (percent >= 100) return Colors.green;
    if (percent >= 50) {
      return Color.lerp(Colors.yellow, Colors.green, (percent - 50) / 50)!;
    }
    return Color.lerp(Colors.red, Colors.yellow, percent / 50)!;
  }

  Widget _buildInitiativeCard(
    BuildContext context,
    AppState state,
    Initiative init,
  ) {
    final progress = state.initiativeProgressPercent(init.id);
    final progressColor = _progressColor(progress);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(init.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${priorityToDisplayName(init.priority)} · $progress%'
              '${init.startDate != null ? ' · Start ${DateFormat.yMMMd().format(init.startDate!)}' : ''}'
              '${init.endDate != null ? ' · Due ${DateFormat.yMMMd().format(init.endDate!)}' : ''}',
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              backgroundColor: progressColor.withValues(alpha: 0.3),
            ),
            if (init.directorIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: init.directorIds.map((id) {
                  final a = state.assigneeById(id);
                  final isDirector = state.isDirector(id);
                  return Chip(
                    label: Text(
                      a?.name ?? id,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: isDirector
                        ? Colors.lightBlue.shade100
                        : Colors.purple.shade100,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InitiativeDetailScreen(initiativeId: init.id),
          ),
        ),
      ),
    );
  }
}
