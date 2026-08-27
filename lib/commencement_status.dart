const String commencementCommenced = 'Commenced';
const String commencementToBeCommenced = 'To be commenced';

const List<String> commencementStatusOptions = [
  commencementCommenced,
  commencementToBeCommenced,
];

String normalizeCommencementStatus(String? value) {
  final raw = value?.trim().toLowerCase() ?? '';
  if (raw == commencementToBeCommenced.toLowerCase()) {
    return commencementToBeCommenced;
  }
  return commencementCommenced;
}
