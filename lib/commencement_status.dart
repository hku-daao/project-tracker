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

/// True when the prompt clearly asks for Commence = To be commenced.
bool asanaPromptImpliesToBeCommenced(String? prompt) {
  final v = (prompt ?? '').trim().toLowerCase();
  if (v.isEmpty) return false;
  return RegExp(
    r'not\s+yet\s+commenced|'
    r'not\s+commenced(\s+yet)?|'
    r'to\s+be\s+commenced|'
    r'yet\s+to\s+(be\s+)?commenced|'
    r'has\s+not(\s+yet)?\s+(been\s+)?(commenced|started)|'
    r'have\s+not(\s+yet)?\s+(been\s+)?(commenced|started)|'
    r'not\s+(yet\s+)?started(\s+yet)?|'
    r'hasn.?t\s+(been\s+)?(commenced|started)|'
    r'haven.?t\s+(been\s+)?(commenced|started)|'
    r'awaiting\s+commencement|'
    r'pending\s+commencement|'
    r'should\s+(wait|not\s+start)|'
    r'do\s+not\s+start(\s+yet)?|'
    r'don.?t\s+start(\s+yet)?',
  ).hasMatch(v);
}
