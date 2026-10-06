import '../models/singular_subtask.dart';

/// Non-deleted sub-task not yet Completed blocks PIC submitting the parent task.
bool subtaskPreventsParentTaskSubmission(SingularSubtask s) {
  if (s.isDeleted) return false;
  final st = s.status.trim().toLowerCase();
  if (st == 'completed' || st == 'complete') return false;
  return true;
}
