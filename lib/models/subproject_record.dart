/// Row from `public.subproject`.
class SubprojectRecord {
  const SubprojectRecord({
    required this.id,
    required this.projectId,
    required this.name,
    this.description = '',
    required this.status,
    this.pauseStatus = 'Not Paused',
    this.startDate,
    this.endDate,
    this.sortOrder = 0,
    this.assigneeStaffUuids = const [],
    this.assigneeStaffDisplayNames = const [],
    this.picStaffUuids = const [],
    this.picStaffDisplayNames = const [],
    this.createByStaffUuid,
    this.createByDisplayName,
    this.createDate,
    this.updateByStaffUuid,
    this.updateDate,
  });

  final String id;
  final String projectId;
  final String name;
  final String description;
  final List<String> assigneeStaffUuids;
  final List<String> assigneeStaffDisplayNames;
  final List<String> picStaffUuids;
  final List<String> picStaffDisplayNames;

  /// Same vocabulary as project: `Not started` | `In progress` | `Completed` | `Deleted`.
  final String status;

  /// `Paused` | `Not Paused`.
  final String pauseStatus;
  final DateTime? startDate;
  final DateTime? endDate;
  final int sortOrder;
  final String? createByStaffUuid;
  final String? createByDisplayName;
  final DateTime? createDate;
  final String? updateByStaffUuid;
  final DateTime? updateDate;

  bool get isPaused => pauseStatus.trim().toLowerCase() == 'paused';

  bool get isDeleted {
    final s = status.trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  bool get isActive => !isDeleted;

  bool get isCompleted {
    final s = status.trim().toLowerCase();
    return s == 'completed' || s == 'complete';
  }

  /// Creator, assignee, or PIC — matches `staff.id` and/or `staff.app_id`.
  bool isInvolvedStaff({String? staffUuid, String? staffAppId}) {
    bool hit(String? raw) {
      final v = raw?.trim() ?? '';
      if (v.isEmpty) return false;
      final u = staffUuid?.trim() ?? '';
      final a = staffAppId?.trim() ?? '';
      return (u.isNotEmpty && v == u) || (a.isNotEmpty && v == a);
    }

    if (hit(createByStaffUuid)) return true;
    for (final id in assigneeStaffUuids) {
      if (hit(id)) return true;
    }
    for (final id in picStaffUuids) {
      if (hit(id)) return true;
    }
    return false;
  }
}
