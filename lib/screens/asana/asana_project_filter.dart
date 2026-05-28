import '../../app_state.dart';
import '../../models/project_record.dart';
class AsanaProjectFilterState {
  AsanaProjectFilterState();

  Set<String> scopes = {};
  /// Empty = all statuses (default).
  Set<String> statuses = {};

  DateTime? createDateStart;
  DateTime? createDateEnd;
  String sortKey = 'due';
  bool sortAscending = true;

  bool get createDateEngaged =>
      createDateStart != null || createDateEnd != null;

  void resetToDefaults() {
    scopes.clear();
    statuses.clear();
    sortKey = 'due';
    sortAscending = true;
    createDateStart = null;
    createDateEnd = null;
  }
}

class AsanaProjectFilter {
  AsanaProjectFilter._();

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _calendarDayInDueRange(DateTime day, AsanaProjectFilterState f) {
    if (!f.createDateEngaged) return true;
    final s = f.createDateStart != null ? _dateOnly(f.createDateStart!) : null;
    final e = f.createDateEnd != null ? _dateOnly(f.createDateEnd!) : null;
    if (s != null && day.isBefore(s)) return false;
    if (e != null && day.isAfter(e)) return false;
    return true;
  }

  static bool _projectPassesDueDate(
    ProjectRecord p,
    AsanaProjectFilterState filters,
  ) {
    if (!filters.createDateEngaged) return true;
    final due = p.endDate;
    if (due == null) return true;
    return _calendarDayInDueRange(_dateOnly(due), filters);
  }

  /// Mirrors [InitiativeListScreen._projectIsVisibleToCurrentUser].
  static bool _projectVisible(
    ProjectRecord p,
    AppState state,
    Set<String> scopes,
  ) {
    final mine = state.userStaffAppId?.trim();
    final myUuid = state.userStaffId?.trim();

    if (scopes.isNotEmpty && !scopes.contains('all')) {
      bool pass = false;
      if (scopes.contains('assigned')) {
        if (myUuid != null && myUuid.isNotEmpty) {
          if (p.assigneeStaffUuids.any((u) => u.trim() == myUuid) ||
              p.picStaffUuids.any((u) => u.trim() == myUuid)) {
            pass = true;
          }
        }
      }
      if (!pass && scopes.contains('created')) {
        if (myUuid != null && myUuid.isNotEmpty) {
          if (p.createByStaffUuid?.trim() == myUuid) {
            pass = true;
          }
        }
      }
      if (!pass) return false;
    }

    if (mine == null || mine.isEmpty) return false;
    if (myUuid != null &&
        myUuid.isNotEmpty &&
        p.createByStaffUuid?.trim() == myUuid) {
      return true;
    }
    for (final u in p.assigneeStaffUuids) {
      final uid = u.trim();
      if (myUuid != null && uid == myUuid) return true;
      final appId = state.assigneeById(uid)?.id ?? uid;
      if (appId == mine) return true;
    }
    if (myUuid != null &&
        myUuid.isNotEmpty &&
        p.picStaffUuids.any((u) => u.trim() == myUuid)) {
      return true;
    }
    final subs = state.subordinateAppIds;
    if (subs.isEmpty) return false;
    final cb = p.createByStaffUuid?.trim();
    if (cb != null && cb.isNotEmpty) {
      final creatorApp = state.assigneeById(cb)?.id ?? cb;
      if (subs.contains(creatorApp)) return true;
    }
    for (final u in p.assigneeStaffUuids) {
      final appId = state.assigneeById(u.trim())?.id ?? u.trim();
      if (subs.contains(appId)) return true;
    }
    for (final u in p.picStaffUuids) {
      final appId = state.assigneeById(u.trim())?.id ?? u.trim();
      if (subs.contains(appId)) return true;
    }
    return false;
  }

  static String _staffName(
    AppState state,
    String staffUuid, {
    String? resolvedName,
  }) {
    final stored = resolvedName?.trim();
    if (stored != null && stored.isNotEmpty && stored != staffUuid.trim()) {
      return stored;
    }
    final u = staffUuid.trim();
    if (u.isEmpty) return '';
    final byApp = state.assigneeById(u);
    if (byApp != null && byApp.name.trim().isNotEmpty) {
      return byApp.name.trim();
    }
    return u;
  }

  static bool projectCreatedByCurrentUser(AppState state, ProjectRecord p) {
    final myUuid = state.userStaffId?.trim();
    if (myUuid == null || myUuid.isEmpty) return false;
    return p.createByStaffUuid?.trim() == myUuid;
  }

  static bool projectAssignedToCurrentUser(AppState state, ProjectRecord p) {
    final myUuid = state.userStaffId?.trim();
    if (myUuid == null || myUuid.isEmpty) return false;
    return p.assigneeStaffUuids.any((u) => u.trim() == myUuid);
  }

  static List<ProjectRecord> apply(
    AppState state,
    AsanaProjectFilterState filters, {
    required String searchQuery,
  }) {
    var list = state.projects
        .where((p) => _projectVisible(p, state, filters.scopes))
        .toList();

    final statuses = filters.statuses.difference({'all', '__all__'});
    if (statuses.isNotEmpty) {
      list = list.where((p) => statuses.contains(p.status)).toList();
    }

    list = list.where((p) => _projectPassesDueDate(p, filters)).toList();

    final q = searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                p.description.toLowerCase().contains(q),
          )
          .toList();
    }

    list.sort((a, b) {
      int cmp;
      switch (filters.sortKey) {
        case 'name':
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'created':
          final ac = a.createDate;
          final bc = b.createDate;
          if (ac == null && bc == null) {
            cmp = 0;
          } else if (ac == null) {
            cmp = 1;
          } else if (bc == null) {
            cmp = -1;
          } else {
            cmp = ac.compareTo(bc);
          }
        case 'due':
        default:
          final ad = a.endDate;
          final bd = b.endDate;
          if (ad == null && bd == null) {
            cmp = 0;
          } else if (ad == null) {
            cmp = 1;
          } else if (bd == null) {
            cmp = -1;
          } else {
            cmp = ad.compareTo(bd);
          }
      }
      if (cmp == 0) {
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return filters.sortAscending ? cmp : -cmp;
    });

    return list;
  }

  static String assigneesLine(ProjectRecord p, AppState state) {
    if (p.assigneeStaffUuids.isEmpty) return '—';
    final parts = <String>[];
    for (var i = 0; i < p.assigneeStaffUuids.length; i++) {
      final uuid = p.assigneeStaffUuids[i];
      final stored = i < p.assigneeStaffDisplayNames.length
          ? p.assigneeStaffDisplayNames[i]
          : null;
      parts.add(_staffName(state, uuid, resolvedName: stored));
    }
    return parts.join(', ');
  }

  static String creatorLine(ProjectRecord p, AppState state) {
    final stored = p.createByDisplayName?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final id = p.createByStaffUuid?.trim();
    if (id == null || id.isEmpty) return '—';
    return _staffName(state, id);
  }

  static String picLine(ProjectRecord p, AppState state) {
    if (p.picStaffUuids.isEmpty) return '—';
    final parts = <String>[];
    for (var i = 0; i < p.picStaffUuids.length; i++) {
      final uuid = p.picStaffUuids[i].trim();
      if (uuid.isEmpty) continue;

      String? name;
      if (i < p.picStaffDisplayNames.length) {
        final stored = p.picStaffDisplayNames[i].trim();
        if (stored.isNotEmpty && stored != uuid) {
          name = state.assigneeById(stored)?.name ?? stored;
        }
      }
      name ??= state.assigneeById(uuid)?.name;
      if (name == null || name.isEmpty) {
        for (final a in state.assignees) {
          if (a.id == uuid) {
            name = a.name;
            break;
          }
        }
      }
      parts.add((name != null && name.isNotEmpty) ? name : uuid);
    }
    return parts.isEmpty ? '—' : parts.join(', ');
  }
}
