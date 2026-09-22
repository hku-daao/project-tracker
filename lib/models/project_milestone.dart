/// Active or deleted row from `public.project_milestone`.
class ProjectMilestone {
  const ProjectMilestone({
    required this.id,
    required this.projectId,
    required this.description,
    this.achieved = false,
    this.progressPercent = 0,
    this.sortOrder = 0,
    this.status = 'Active',
  });

  final String id;
  final String projectId;
  final String description;
  final bool achieved;

  /// 0–100 share of overall project progress.
  final int progressPercent;
  final int sortOrder;
  final String status;

  bool get isActive => status.trim().toLowerCase() != 'deleted';
}
