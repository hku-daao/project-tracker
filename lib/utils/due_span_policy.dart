import 'hk_time.dart';
import '../models/singular_subtask.dart';
import '../priority.dart';

int allowedWorkingDaysAfterStartForPriority(int priority) =>
    priority == priorityUrgent ? 1 : 3;

/// Working days required to finish, **including** the start date.
/// Standard = 4, Urgent = 2 (same as [allowedWorkingDaysAfterStartForPriority] + 1).
int workingDaysInclusiveForPriority(int priority) =>
    allowedWorkingDaysAfterStartForPriority(priority) + 1;

DateTime dueDateFromInclusiveWorkingDays(
  DateTime start,
  int workingDaysInclusive, {
  Set<String> calendarHolidayYmdSkip = const {},
}) {
  final extra = workingDaysInclusive < 1 ? 0 : workingDaysInclusive - 1;
  return HkTime.addBusinessDaysAfter(start, extra, calendarHolidayYmdSkip);
}

/// True when [due] (date-only) is strictly after `start + N` business days, where
/// N follows the same rule as default due ([HkTime.addBusinessDaysAfter]).
///
/// [calendarHolidayYmdSkip]: `yyyy-MM-dd` keys (see [HkTime.ymdKey]) for HK/HKU holidays
/// from [public.calendar_holiday]. Empty set counts only Mon–Fri (weekends skipped).
bool dueDateExceedsPolicyForPriority(
  DateTime? start,
  DateTime? due,
  int priority, {
  Set<String> calendarHolidayYmdSkip = const {},
}) {
  if (start == null || due == null) return false;
  final n = allowedWorkingDaysAfterStartForPriority(priority);
  final maxDue = HkTime.addBusinessDaysAfter(start, n, calendarHolidayYmdSkip);
  final dDue = DateTime(due.year, due.month, due.day);
  final dMax = DateTime(maxDue.year, maxDue.month, maxDue.day);
  return dDue.isAfter(dMax);
}

/// True when [subtasks] is non-empty and each has start+due dates that do not exceed
/// the allowed working-day span for its priority (Standard: 3, Urgent: 1).
///
/// Used to relax the **parent** task’s due-span “Reason” requirement: if all sub-tasks
/// comply, the parent is not restricted by its own due date span for that UI rule.
bool allSubtasksComplyWithDueSpanPolicy(List<SingularSubtask> subtasks) {
  if (subtasks.isEmpty) return false;
  for (final s in subtasks) {
    final a = s.startDate;
    final b = s.dueDate;
    if (a == null || b == null) return false;
    if (dueDateExceedsPolicyForPriority(a, b, s.priority)) return false;
  }
  return true;
}
