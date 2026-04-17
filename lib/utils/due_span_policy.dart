import 'hk_time.dart';
import '../priority.dart';

int allowedWorkingDaysAfterStartForPriority(int priority) =>
    priority == priorityUrgent ? 1 : 3;

/// True when [due] (date-only) is strictly after `start + N` working days, where
/// N follows the same rule as default due ([HkTime.addWorkingDaysAfter]).
bool dueDateExceedsPolicyForPriority(
  DateTime? start,
  DateTime? due,
  int priority,
) {
  if (start == null || due == null) return false;
  final n = allowedWorkingDaysAfterStartForPriority(priority);
  final maxDue = HkTime.addWorkingDaysAfter(start, n);
  final dDue = DateTime(due.year, due.month, due.day);
  final dMax = DateTime(maxDue.year, maxDue.month, maxDue.day);
  return dDue.isAfter(dMax);
}
