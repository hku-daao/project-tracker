import 'package:flutter/foundation.dart';
import 'models/assignee.dart';
import 'models/staff_team_lookup.dart';
import 'models/project_record.dart';
import 'models/subproject_record.dart';
import 'models/task.dart';
import 'models/team.dart';
import 'services/database_service.dart';
import 'services/task_fetch_visibility.dart';

/// Global app state for Asana-style projects, tasks, staff, and teams.
class AppState extends ChangeNotifier {
  static const Set<String> adminViewAllowedEmails = {
    'kenkylee@hku.hk',
    'jcltai@hku.hk',
    'ywang63@hku.hk',
    'icarusm@hku.hk',
  };
  static const String adminViewStorageKey = 'project_tracker_admin_view_mode';
  static const String superAdminToolsStorageKey =
      'project_tracker_super_admin_tools';

  /// Staff members loaded from database (via /api/staff).
  final List<Assignee> _assignees = [];

  /// Teams with hierarchy loaded from database (via /api/teams).
  List<Team> _teams = [];

  /// [staff.app_id] → [staff.team_id] for team filter (assignees may belong to a team when `task.team_id` is null).
  Map<String, String> _staffTeamIdByAssigneeAppId = {};

  List<Team> get teams => List.unmodifiable(_teams);

  final List<ProjectRecord> _projects = [];
  final List<SubprojectRecord> _subprojects = [];
  final List<Task> _tasks = [];

  /// Current user's `staff.app_id` (from the database lookup or backend).
  String? _userStaffAppId;

  /// Current user's `staff.id` (uuid), when revamp email lookup returned it.
  String? _userStaffId;

  /// `staff.app_id` values from `subordinate.subordinate_id` where `supervisor_id` = current user.
  List<String> _subordinateAppIds = [];
  List<String> _actualSubordinateAppIds = [];

  /// `staff.id` uuids for those subordinates (resolved at login for filters + visibility).
  List<String> _subordinateStaffUuids = [];
  List<String> _actualSubordinateStaffUuids = [];

  /// Revamp step 1: staff + team lookup by login email (Supabase).
  StaffTeamLookupResult? _revampStaffLookup;
  bool _adminViewMode = false;
  bool _superAdminToolsOpen = false;
  String? _adminViewAsStaffAppId;
  String? _adminViewAsStaffUuid;
  String? _adminViewAsStaffName;
  String? _adminViewAsRole;
  List<String> _adminViewAsOfficeIds = [];
  String? _staffAdminRole;

  StaffTeamLookupResult? get revampStaffLookup => _revampStaffLookup;

  bool get canUseAdminViewMode {
    final email =
        (_revampStaffLookup?.staffEmailFromDb?.trim().isNotEmpty == true
                ? _revampStaffLookup?.staffEmailFromDb
                : _revampStaffLookup?.loginEmail)
            ?.trim()
            .toLowerCase();
    return email != null && adminViewAllowedEmails.contains(email);
  }

  bool get adminViewMode => _adminViewMode && canUseAdminViewMode;

  bool get isSuperAdmin => _staffAdminRole == 'super_admin';

  /// Signed-in super admin may edit any project or task the way its PIC can.
  /// Viewing as another person keeps that person's own rights.
  bool get superAdminActsAsPic {
    if (adminDebugViewAsActive) return _adminViewAsRole == 'super_admin';
    return isSuperAdmin;
  }

  bool get isOfficeAdmin => _staffAdminRole == 'office_admin';

  bool get isPerformanceAdmin => _staffAdminRole == 'performance_admin';

  bool get canViewPerformance => isSuperAdmin || isPerformanceAdmin;

  /// Five clicks on the signed-in super admin's circle. Hides performance and
  /// the staff list until it is on.
  bool get superAdminToolsOpen => _superAdminToolsOpen && isSuperAdmin;

  /// While viewing as someone, the left menu follows that person's role.
  bool get showPerformanceNav {
    if (adminDebugViewAsActive) {
      return _adminViewAsRole == 'super_admin' ||
          _adminViewAsRole == 'performance_admin';
    }
    return isPerformanceAdmin || superAdminToolsOpen;
  }

  bool get showPeopleNav {
    if (adminDebugViewAsActive) {
      return _adminViewAsRole == 'super_admin' ||
          _adminViewAsRole == 'office_admin';
    }
    return isSuperAdmin || isOfficeAdmin;
  }

  bool get showStaffViewAsMenu => superAdminToolsOpen;

  List<String> _staffAdminOfficeIds = [];

  List<String> get staffAdminOfficeIds {
    if (adminDebugViewAsActive &&
        _adminViewAsRole != null &&
        _adminViewAsRole != 'super_admin') {
      return List.unmodifiable(_adminViewAsOfficeIds);
    }
    return List.unmodifiable(_staffAdminOfficeIds);
  }

  bool get adminDebugViewAsActive =>
      superAdminToolsOpen &&
      (_adminViewAsStaffAppId?.trim().isNotEmpty == true);

  /// Every office when the signed-in super admin is on Super Admin, or when
  /// the person in the dropdown is themselves a super admin.
  bool get showAllDataAsAdmin {
    if (adminDebugViewAsActive) return _adminViewAsRole == 'super_admin';
    return isSuperAdmin;
  }

  String? get adminViewAsStaffAppId =>
      adminDebugViewAsActive ? _adminViewAsStaffAppId?.trim() : null;

  String? get adminViewAsStaffUuid =>
      adminDebugViewAsActive ? _adminViewAsStaffUuid?.trim() : null;

  String? get adminViewAsStaffName =>
      adminDebugViewAsActive ? _adminViewAsStaffName?.trim() : null;

  void setAdminViewMode(bool value) {
    final next = value && canUseAdminViewMode;
    if (_adminViewMode == next) return;
    _adminViewMode = next;
    if (!next) clearAdminDebugViewAs();
    notifyListeners();
  }

  void setSuperAdminToolsOpen(bool value) {
    if (_superAdminToolsOpen == value) return;
    _superAdminToolsOpen = value;
    if (!value) {
      _adminViewAsStaffAppId = null;
      _adminViewAsStaffUuid = null;
      _adminViewAsStaffName = null;
      _adminViewAsRole = null;
      _adminViewAsOfficeIds = [];
      _subordinateAppIds = List<String>.from(_actualSubordinateAppIds);
      _subordinateStaffUuids = List<String>.from(_actualSubordinateStaffUuids);
    }
    notifyListeners();
  }

  void setStaffAdminRole(String? role, {List<String> officeIds = const []}) {
    final trimmed = role?.trim();
    final next = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    final nextOffices = [
      for (final id in officeIds)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    if (_staffAdminRole == next &&
        _sameOfficeIds(_staffAdminOfficeIds, nextOffices)) {
      return;
    }
    _staffAdminRole = next;
    _staffAdminOfficeIds = nextOffices;
    notifyListeners();
  }

  bool _sameOfficeIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toLowerCase() != b[i].toLowerCase()) return false;
    }
    return true;
  }

  void setAdminDebugViewAs({
    required String staffAppId,
    String? staffUuid,
    String? staffName,
    String? staffAdminRole,
    List<String> staffAdminOfficeIds = const [],
    List<String> subordinateAppIds = const [],
    List<String> subordinateStaffUuids = const [],
  }) {
    if (!superAdminToolsOpen) return;
    _adminViewAsStaffAppId = staffAppId.trim();
    _adminViewAsStaffUuid = staffUuid?.trim();
    _adminViewAsStaffName = staffName?.trim();
    final role = staffAdminRole?.trim();
    _adminViewAsRole = (role == null || role.isEmpty) ? null : role;
    _adminViewAsOfficeIds = [
      for (final id in staffAdminOfficeIds)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    _subordinateAppIds = List<String>.from(subordinateAppIds);
    _subordinateStaffUuids = List<String>.from(subordinateStaffUuids);
    notifyListeners();
  }

  void clearAdminDebugViewAs() {
    final changed =
        _adminViewAsStaffAppId != null ||
        _adminViewAsStaffUuid != null ||
        _adminViewAsStaffName != null ||
        _adminViewAsRole != null ||
        _adminViewAsOfficeIds.isNotEmpty;
    _adminViewAsStaffAppId = null;
    _adminViewAsStaffUuid = null;
    _adminViewAsStaffName = null;
    _adminViewAsRole = null;
    _adminViewAsOfficeIds = [];
    _subordinateAppIds = List<String>.from(_actualSubordinateAppIds);
    _subordinateStaffUuids = List<String>.from(_actualSubordinateStaffUuids);
    if (!changed) return;
    notifyListeners();
  }

  void setRevampStaffLookup(StaffTeamLookupResult? v) {
    _revampStaffLookup = v;
    if (!canUseAdminViewMode) {
      _adminViewMode = false;
    }
    notifyListeners();
  }

  /// While a super admin is viewing as someone, writes and access checks use
  /// that person. The signed-in account stays the one that opened the tools.
  String? get userStaffAppId {
    final viewAs = adminViewAsStaffAppId;
    if (viewAs != null && viewAs.isNotEmpty) return viewAs;
    return _userStaffAppId;
  }

  String? get userStaffId {
    final viewAs = adminViewAsStaffUuid;
    if (viewAs != null && viewAs.isNotEmpty) return viewAs;
    return _userStaffId;
  }

  /// Resolved staff keys for UI (falls back to revamp email lookup).
  String? get effectiveStaffAppId {
    final viewAs = adminViewAsStaffAppId;
    if (viewAs != null && viewAs.isNotEmpty) return viewAs;
    final direct = _userStaffAppId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    return _revampStaffLookup?.appId?.trim();
  }

  String? get effectiveStaffUuid {
    if (adminDebugViewAsActive) {
      final viewAs = _adminViewAsStaffUuid?.trim();
      if (viewAs != null && viewAs.isNotEmpty) return viewAs;
    }
    final direct = _userStaffId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    return _revampStaffLookup?.staffId?.trim();
  }

  /// Display name for sidebar avatar (assignee list, then staff lookup, then SSO name).
  String? get currentStaffDisplayName {
    final viewAsName = adminViewAsStaffName;
    if (viewAsName != null && viewAsName.isNotEmpty) return viewAsName;
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
    if (!adminDebugViewAsActive) {
      _actualSubordinateAppIds = List<String>.from(ids);
    }
    notifyListeners();
  }

  void setSubordinateStaffUuids(List<String> uuids) {
    _subordinateStaffUuids = List<String>.from(uuids);
    if (!adminDebugViewAsActive) {
      _actualSubordinateStaffUuids = List<String>.from(uuids);
    }
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

  /// Client-side visibility: assignee or creator is self or a subordinate
  /// (uuid or app_id), or this task was loaded because that person is PIC
  /// or an assignee on one of its sub-tasks.
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
    return _taskIdsVisibleViaSubtask.contains(t.id);
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

  String? teamIdForStaffKey(String? staffKey) {
    final key = staffKey?.trim();
    if (key == null || key.isEmpty) return null;
    final direct = _staffTeamIdByAssigneeAppId[key];
    if (direct != null && direct.trim().isNotEmpty) return direct;
    final appId = assigneeById(key)?.id.trim();
    if (appId != null && appId.isNotEmpty) {
      final byAppId = _staffTeamIdByAssigneeAppId[appId];
      if (byAppId != null && byAppId.trim().isNotEmpty) return byAppId;
    }
    return null;
  }

  String teamNameById(String teamId) {
    final id = teamId.trim();
    if (id.isEmpty) return '';
    for (final team in _teams) {
      if (team.id == id) return team.name;
    }
    return id;
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

  ProjectRecord? projectById(String? id) {
    final pid = id?.trim();
    if (pid == null || pid.isEmpty) return null;
    for (final row in _projects) {
      if (row.id == pid) return row;
    }
    return null;
  }

  List<SubprojectRecord> get subprojects => List.unmodifiable(_subprojects);

  /// Replace projects from the database after fetch or create.
  void applyProjects(List<ProjectRecord> list) {
    _projects
      ..clear()
      ..addAll(list);
    notifyListeners();
  }

  void applySubprojects(List<SubprojectRecord> list) {
    _subprojects
      ..clear()
      ..addAll(list);
    notifyListeners();
  }

  List<SubprojectRecord> subprojectsForProject(
    String? projectId, {
    bool includeDeleted = false,
  }) {
    final pid = projectId?.trim();
    if (pid == null || pid.isEmpty) return const [];
    final out = <SubprojectRecord>[
      for (final row in _subprojects)
        if (row.projectId == pid && (includeDeleted || row.isActive)) row,
    ];
    out.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return (a.createDate ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        b.createDate ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    return out;
  }

  SubprojectRecord? subprojectById(String? id) {
    final sid = id?.trim();
    if (sid == null || sid.isEmpty) return null;
    for (final row in _subprojects) {
      if (row.id == sid) return row;
    }
    return null;
  }

  /// True when login fetch used [TaskFetchVisibility] (rows already scoped in Postgres).
  bool _tasksLoadedWithVisibilityScope = false;

  bool get tasksLoadedWithVisibilityScope => _tasksLoadedWithVisibilityScope;

  /// Parent tasks loaded because the user (or a subordinate) is on a child sub-task.
  final Set<String> _taskIdsVisibleViaSubtask = {};

  Set<String> get taskIdsVisibleViaSubtask =>
      Set.unmodifiable(_taskIdsVisibleViaSubtask);

  /// Replace tasks from the database after fetch.
  void applyTasks(TasksLoadResult result, {bool visibilityScoped = false}) {
    _tasksLoadedWithVisibilityScope = visibilityScoped;
    final previous = {for (final task in _tasks) task.id: task};
    _tasks
      ..clear()
      ..addAll(
        result.tasks.map(
          (incoming) => _keepFresherCompletion(previous[incoming.id], incoming),
        ),
      );
    _taskIdsVisibleViaSubtask
      ..clear()
      ..addAll(result.taskIdsVisibleViaSubtask);
    notifyListeners();
  }

  /// A list reload that started before Mark as Completed can return the old
  /// incomplete row. Keep the completed slide until a newer row arrives.
  Task _keepFresherCompletion(Task? current, Task incoming) {
    if (current == null) return incoming;
    final currentStatus = (current.dbStatus ?? '').trim().toLowerCase();
    final incomingStatus = (incoming.dbStatus ?? '').trim().toLowerCase();
    final currentCompleted =
        currentStatus == 'completed' ||
        currentStatus == 'complete' ||
        current.status == TaskStatus.done;
    final incomingCompleted =
        incomingStatus == 'completed' || incomingStatus == 'complete';
    if (!currentCompleted || incomingCompleted) return incoming;
    final currentAt = current.updateDate ?? current.lastUpdated;
    final incomingAt = incoming.updateDate ?? incoming.lastUpdated;
    if (currentAt != null &&
        (incomingAt == null || !incomingAt.isAfter(currentAt))) {
      return current;
    }
    return incoming;
  }

  /// True when [key] is the current user or a subordinate (`staff.app_id` or uuid).
  bool visibilityKeysInclude(String? key) {
    final k = key?.trim();
    if (k == null || k.isEmpty) return false;
    return _visibilityKeyMatches(k, taskVisibilityLookupKeys);
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
    if (!_tasksLoadedWithVisibilityScope && !showAllDataAsAdmin) {
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
