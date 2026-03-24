/// Row from `public."comment"` with resolved staff display name for UI.
class SingularCommentRowDisplay {
  final String id;
  final String description;
  final String status;
  final String displayStaffName;
  final DateTime? displayTimestampUtc;

  const SingularCommentRowDisplay({
    required this.id,
    required this.description,
    required this.status,
    required this.displayStaffName,
    this.displayTimestampUtc,
  });
}
