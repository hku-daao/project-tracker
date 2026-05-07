/// Row from `public.project` (assignee slots store `staff.id` uuid strings).
class ProjectRecord {
  const ProjectRecord({
    required this.id,
    required this.name,
    required this.assigneeStaffUuids,
    this.picStaffUuids = const [],
    required this.description,
    this.startDate,
    this.endDate,
    required this.status,
    this.createByStaffUuid,
    this.createByDisplayName,
    this.createDate,
    this.updateByStaffUuid,
    this.updateByDisplayName,
    this.updateDate,
  });

  final String id;
  final String name;

  /// Ordered non-empty `staff.id` values from assignee_01…assignee_10.
  final List<String> assigneeStaffUuids;

  /// Non-empty `staff.id` values from [`project.pic`] JSON array (PICs ⊆ assignees).
  final List<String> picStaffUuids;

  final String description;
  final DateTime? startDate;
  final DateTime? endDate;

  /// `Not started` | `In progress` | `Completed`
  final String status;

  final String? createByStaffUuid;
  final String? createByDisplayName;
  final DateTime? createDate;

  final String? updateByStaffUuid;
  final String? updateByDisplayName;
  final DateTime? updateDate;

  /// True if [staffRowUuid] is project creator, assignee slot, or PIC.
  bool staffMayLinkTasks(String staffRowUuid) {
    final m = staffRowUuid.trim();
    if (m.isEmpty) return false;
    final cb = createByStaffUuid?.trim();
    if (cb != null && cb.isNotEmpty && cb == m) return true;
    for (final u in assigneeStaffUuids) {
      if (u.trim() == m) return true;
    }
    for (final u in picStaffUuids) {
      if (u.trim() == m) return true;
    }
    return false;
  }

  /// Resolved assignee keys (`staff.app_id`) aligned with [assigneeStaffUuids].
  List<String> assigneeKeys(Map<String, String> staffUuidToAppId) {
    final out = <String>[];
    for (final u in assigneeStaffUuids) {
      final k = staffUuidToAppId[u] ?? u;
      if (k.isNotEmpty) out.add(k);
    }
    return out;
  }
}
