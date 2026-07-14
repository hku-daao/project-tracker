import 'package:flutter/foundation.dart';
import 'models/assignee.dart';
import 'models/staff_team_lookup.dart';
import 'models/project_record.dart';
import 'models/task.dart';
import 'models/team.dart';
import 'services/database_service.dart';
import 'services/task_fetch_visibility.dart';

/// Global app state for Asana-style projects, tasks, staff, and teams.
class AppState extends ChangeNotifier {
  /// Staff members loaded from database (via /api/staff).
  final List<Assignee> _assignees = [];

  /// Teams with hierarchy loaded from database (via /api/teams).
  List<Team> _teams = [];

  /// [staff.app_id] → [staff.team_id] for team filter (assignees may belong to a team when `task.team_id` is null).
  Map<String, String> _staffTeamIdByAssigneeAppId = {};

  List<Team> get teams => List.unmodifiable(_teams);

  final List<ProjectRecord> _projects = [];
  final List<Task> _tasks = [];

  /// Current user's `staff.app_id` (from the database lookup or backend).
  String? _userStaffAppId;

  /// Current user's `staff.id` (uuid), when revamp email lookup returned it.
  String? _userStaffId;

  /// `staff.app_id` values from `subordinate.subordinate_id` where `supervisor_id` = current user.
  List<String> _subordinateAppIds = [];

  /// `staff.id` uuids for those subordinates (resolved at login for filters + visibility).
  List<String> _subordinateStaffUuids = [];

  /// Revamp step 1: staff + team lookup by login email (Supabase).
  StaffTeamLookupResult? _revampStaffLookup;

  StaffTeamLookupResult? get revampStaffLookup => _revampStaffLookup;

  void setRevampStaffLookup(StaffTeamLookupResult? v) {
    _revampStaffLookup = v;
    notifyListeners();
  }

  String? get userStaffAppId => _userStaffAppId;
  String? get userStaffId => _userStaffId;

  /// Resolved staff keys for UI (falls back to revamp email lookup).
  String? get effectiveStaffAppId {
    final direct = _userStaffAppId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    return _revampStaffLookup?.appId?.trim();
  }

  String? get effectiveStaffUuid {
    final direct = _userStaffId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    return _revampStaffLookup?.staffId?.trim();
  }

  /// Display name for sidebar avatar (assignee list, then staff lookup, then SSO name).
  String? get currentStaffDisplayName {
    final id = effectiveStaffAppId?.trim();
    if (id != null && id.isNotEmpty) {
      final fromAssignee = assigneeById(id)?.name.trim();
      if (fromAssignee != null && fromAssignee.isNotEmpty) return fromAssignee;
    }
    return _revampStaffLookup?.resolvedDisplayName;
  }

  List<String> get subordinateAppIds => List.unmodifiable(_subordinateAppIds);

  List<String> get subordinateStaffUuids =>
      List.unmodifiable(_subordinateStaffUuids);

  /// Logged-in user plus subordinates from `subordinate` (same `staff.app_id` keys).
  Set<String> get assigneeVisibilityAppIds {
    final mine = effectiveStaffAppId?.trim();
    if (mine == null || mine.isEmpty) return {};
    return {mine, ..._subordinateAppIds};
  }

  /// All staff keys for matching loaded tasks (app_id + uuid), aligned with Postgres fetch scope.
  Set<String> get taskVisibilityLookupKeys {
    final out = <String>{};
    void add(String? v) {
      final s = v?.trim();
      if (s != null && s.isNotEmpty) out.add(s);
    }

    add(effectiveStaffAppId);
    add(effectiveStaffUuid);
    for (final a in _subordinateAppIds) {
      add(a);
    }
    for (final u in _subordinateStaffUuids) {
      add(u);
    }
    return out;
  }

  /// Scope for Postgres task fetch (me + subordinates as creator or assignee).
  TaskFetchVisibility? buildTaskFetchVisibility() {
    final mine = effectiveStaffAppId?.trim();
    if (mine == null || mine.isEmpty) return null;
    return TaskFetchVisibility(
      supervisorStaffAppId: mine,
      supervisorStaffUuid: effectiveStaffUuid,
      subordinateStaffAppIds: _subordinateAppIds,
      subordinateStaffUuids: _subordinateStaffUuids,
    );
  }

  void setSubordinateAppIds(List<String> ids) {
    _subordinateAppIds = List<String>.from(ids);
    notifyListeners();
  }

  void setSubordinateStaffUuids(List<String> uuids) {
    _subordinateStaffUuids = List<String>.from(uuids);
    notifyListeners();
  }

  static bool _visibilityKeyMatches(String value, Set<String> keys) {
    final v = value.trim();
    if (v.isEmpty) return false;
    if (keys.contains(v)) return true;
    final lower = v.toLowerCase();
    for (final k in keys) {
      if (k.toLowerCase() == lower) return true;
    }
    return false;
  }

  /// Client-side visibility: assignee or creator is self or a subordinate (uuid or app_id).
  bool taskMatchesSupervisorScope(Task t) {
    final keys = taskVisibilityLookupKeys;
    if (keys.isEmpty) return false;
    for (final id in t.assigneeIds) {
      if (_visibilityKeyMatches(id, keys)) return true;
    }
    final cb = t.createByAssigneeKey?.trim();
    if (cb != null && cb.isNotEmpty && _visibilityKeyMatches(cb, keys)) {
      return true;
    }
    return false;
  }

  void setUserStaffContext({String? staffAppId, String? staffUuid}) {
    _userStaffAppId = staffAppId;
    _userStaffId = staffUuid;
    notifyListeners();
  }

  /// Matches singular `task.create_by` resolved to [Task.createByAssigneeKey] (`staff.app_id` or uuid).
  bool taskIsCreatedByCurrentUser(Task t) {
    final mine = effectiveStaffAppId?.trim();
    final sid = effectiveStaffUuid?.trim();
    final cb = t.createByAssigneeKey?.trim();
    if (cb == null || cb.isEmpty) return false;
    if (mine != null && mine.isNotEmpty && cb == mine) return true;
    if (sid != null &&
        sid.isNotEmpty &&
        cb.toLowerCase() == sid.toLowerCase()) {
      return true;
    }
    return false;
  }

  /// Replace teams used for filters (ids must match [Task.teamId] from the database singular `task`).
  void setTeamsForFilter(List<Team> teams) {
    _teams = List<Team>.from(teams);
    notifyListeners();
  }

  /// Merge/replace assignees from the database `staff` (for filter labels when backend staff is not loaded).
  void mergeAssignees(List<Assignee> incoming) {
    final map = <String, Assignee>{for (final a in _assignees) a.id: a};
    for (final a in incoming) {
      map[a.id] = a;
    }
    _assignees
      ..clear()
      ..addAll(map.values);
    notifyListeners();
  }

  void setStaffAppIdToTeamIdMap(Map<String, String> map) {
    _staffTeamIdByAssigneeAppId = Map<String, String>.from(map);
    notifyListeners();
  }

  bool _taskMatchesTeamFilter(Task t, String teamId) {
    final rowTeam = t.teamId?.trim();
    if (rowTeam != null && rowTeam.isNotEmpty && rowTeam == teamId) {
      return true;
    }
    for (final assigneeKey in t.assigneeIds) {
      if (_staffTeamIdByAssigneeAppId[assigneeKey] == teamId) return true;
    }
    return false;
  }

  List<Assignee> get assignees => List.unmodifiable(_assignees);

  List<ProjectRecord> get projects => List.unmodifiable(_projects);

  /// Replace projects from the database after fetch or create.
  void applyProjects(List<ProjectRecord> list) {
    _projects
      ..clear()
      ..addAll(list);
    notifyListeners();
  }

  /// True when login fetch used [TaskFetchVisibility] (rows already scoped in Postgres).
  bool _tasksLoadedWithVisibilityScope = false;

  bool get tasksLoadedWithVisibilityScope => _tasksLoadedWithVisibilityScope;

  /// Replace tasks from the database after fetch.
  void applyTasks(
    TasksLoadResult result, {
    bool visibilityScoped = false,
  }) {
    _tasksLoadedWithVisibilityScope = visibilityScoped;
    _tasks.clear();
    _tasks.addAll(result.tasks);
    notifyListeners();
  }

  List<Task> get tasks {
    return List<Task>.from(_tasks);
  }

  Assignee? assigneeById(String id) {
    try {
      return _assignees.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  Task? taskById(String id) {
    try {
      final t = _tasks.firstWhere((x) => x.id == id);
      return t;
    } catch (_) {
      return null;
    }
  }

  /// Low-level tasks for a team: `task.team_id` matches **or** any assignee's `staff.team_id` matches
  /// (same id as filter dropdown: Postgres `team.team_id`).
  /// Tasks visible to the current user: any assignee slot is the user’s `staff.app_id` or a
  /// `subordinate.subordinate_id` whose `supervisor_id` is the user ([assigneeVisibilityAppIds]),
  /// **or** the task was created by this user ([taskIsCreatedByCurrentUser]) (assignees may be outside that set).
  List<Task> tasksForTeam(String? teamId) {
    var all = tasks;
    if (!_tasksLoadedWithVisibilityScope) {
      if (taskVisibilityLookupKeys.isEmpty) {
        all = [];
      } else {
        all = all.where(taskMatchesSupervisorScope).toList();
      }
    }
    if (teamId == null || teamId.isEmpty) return all;
    return all.where((t) => _taskMatchesTeamFilter(t, teamId)).toList();
  }

  /// Empty [teamIds] = all teams (same as `null` for [tasksForTeam]).
  List<Task> tasksForTeams(Set<String> teamIds) {
    if (teamIds.isEmpty) return tasksForTeam(null);
    final byId = <String, Task>{};
    for (final tid in teamIds) {
      for (final t in tasksForTeam(tid)) {
        byId[t.id] = t;
      }
    }
    return byId.values.toList();
  }

  void replaceTask(Task t) {
    final i = _tasks.indexWhere((x) => x.id == t.id);
    if (i < 0) return;
    _tasks[i] = t;
    notifyListeners();
  }

  /// Insert or replace a task row (e.g. after Postgres create).
  void upsertTask(Task t) {
    final i = _tasks.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      _tasks[i] = t;
    } else {
      _tasks.add(t);
    }
    notifyListeners();
  }

  /// Insert or replace a project row (e.g. after Postgres create).
  void upsertProject(ProjectRecord p) {
    final i = _projects.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      _projects[i] = p;
    } else {
      _projects.add(p);
    }
    notifyListeners();
  }
}
