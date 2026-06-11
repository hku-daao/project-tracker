import '../models/task.dart';

/// Status label helper used by Asana task tables.
class TaskListCard {
  const TaskListCard._();

  static String statusLabel(Task t) {
    if (t.isSingularTableRow) {
      final raw = t.dbStatus?.trim();
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return taskStatusDisplayNames[t.status] ?? '';
  }
}
