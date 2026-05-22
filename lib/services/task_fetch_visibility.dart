/// Scope for loading tasks from Supabase at login (supervisor + subordinates).
class TaskFetchVisibility {
  const TaskFetchVisibility({
    this.supervisorStaffAppId,
    this.supervisorStaffUuid,
    this.subordinateStaffAppIds = const [],
    this.subordinateStaffUuids = const [],
  });

  final String? supervisorStaffAppId;
  final String? supervisorStaffUuid;
  final List<String> subordinateStaffAppIds;
  final List<String> subordinateStaffUuids;

  /// All keys used in `task.create_by` and `assignee_01`…`assignee_10` (uuid + app_id).
  Set<String> get lookupKeys {
    final out = <String>{};
    void add(String? v) {
      final s = v?.trim();
      if (s != null && s.isNotEmpty) out.add(s);
    }

    add(supervisorStaffAppId);
    add(supervisorStaffUuid);
    for (final a in subordinateStaffAppIds) {
      add(a);
    }
    for (final u in subordinateStaffUuids) {
      add(u);
    }
    return out;
  }

  bool get isConfigured => lookupKeys.isNotEmpty;

  /// `staff.id` values for `assignee_01`…`assignee_10` (uuid columns).
  Set<String> get staffUuidsForAssigneeFilter {
    final out = <String>{};
    void add(String? v) {
      final s = v?.trim();
      if (s != null && s.isNotEmpty) out.add(s);
    }

    add(supervisorStaffUuid);
    for (final u in subordinateStaffUuids) {
      add(u);
    }
    return out;
  }

  /// Keys for `create_by` (text: may be `staff.id` or `staff.app_id`).
  Set<String> get staffKeysForCreateByFilter => lookupKeys;
}
