const String commencementInProgress = 'In progress';
const String commencementToBeCommenced = 'To be commenced';

const List<String> commencementStatusOptions = [
  commencementInProgress,
  commencementToBeCommenced,
];

String normalizeCommencementStatus(String? value) {
  final raw = value?.trim().toLowerCase() ?? '';
  if (raw == commencementToBeCommenced.toLowerCase()) {
    return commencementToBeCommenced;
  }
  return commencementInProgress;
}
