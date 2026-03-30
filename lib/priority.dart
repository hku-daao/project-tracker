/// Priority levels: 1 = Standard, 2 = Urgent (two levels only).
const Map<int, String> priorityDisplayNames = {
  1: 'Standard',
  2: 'URGENT',
};

/// Order for UI: Standard, then URGENT.
const List<int> priorityOptions = [1, 2];

String priorityToDisplayName(int priority) {
  return priorityDisplayNames[priority.clamp(1, 2)] ?? 'Standard';
}

/// Urgent = 2, Standard = 1.
int get priorityUrgent => 2;
int get priorityStandard => 1;
