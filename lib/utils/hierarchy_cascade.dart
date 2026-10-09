enum HierarchyCascadeAction { complete, delete, pause, resume, restore }

class HierarchyCascadeCounts {
  const HierarchyCascadeCounts({
    this.subprojects = 0,
    this.tasks = 0,
    this.subtasks = 0,
  });

  final int subprojects;
  final int tasks;
  final int subtasks;

  bool get hasChanges => subprojects > 0 || tasks > 0 || subtasks > 0;
}

String hierarchyCascadeTitle(
  HierarchyCascadeAction action,
  String parentKind,
) {
  switch (action) {
    case HierarchyCascadeAction.complete:
      return 'Mark $parentKind as completed?';
    case HierarchyCascadeAction.delete:
      return 'Delete $parentKind?';
    case HierarchyCascadeAction.pause:
      return 'Pause $parentKind?';
    case HierarchyCascadeAction.resume:
      return 'Resume $parentKind?';
    case HierarchyCascadeAction.restore:
      return 'Restore $parentKind?';
  }
}

String hierarchyCascadeConfirmText(HierarchyCascadeAction action) {
  switch (action) {
    case HierarchyCascadeAction.complete:
      return 'Completed';
    case HierarchyCascadeAction.delete:
      return 'Delete';
    case HierarchyCascadeAction.pause:
      return 'Pause';
    case HierarchyCascadeAction.resume:
      return 'Resume';
    case HierarchyCascadeAction.restore:
      return 'Restore';
  }
}

String hierarchyCascadeContent(
  HierarchyCascadeAction action,
  HierarchyCascadeCounts counts,
) {
  final verb = switch (action) {
    HierarchyCascadeAction.complete => 'marked as completed',
    HierarchyCascadeAction.delete => 'marked as deleted',
    HierarchyCascadeAction.pause => 'paused',
    HierarchyCascadeAction.resume => 'resumed',
    HierarchyCascadeAction.restore => 'restored',
  };
  final lines = <String>[
    'The following items below will also be $verb:',
    '',
  ];
  if (counts.subprojects > 0) {
    lines.add(
      '${counts.subprojects} ${counts.subprojects == 1 ? 'sub-project' : 'sub-projects'}',
    );
  }
  if (counts.tasks > 0) {
    lines.add('${counts.tasks} ${counts.tasks == 1 ? 'task' : 'tasks'}');
  }
  if (counts.subtasks > 0) {
    lines.add(
      '${counts.subtasks} ${counts.subtasks == 1 ? 'sub-task' : 'sub-tasks'}',
    );
  }
  return lines.join('\n');
}
