/// Result of revamp step 1: staff row + optional team (by email login).
class StaffTeamLookupResult {
  const StaffTeamLookupResult({
    required this.loginEmail,
    this.staffId,
    this.appId,
    this.staffDisplayName,
    this.staffName,
    this.staffTeamIdRaw,
    this.teamName,
    this.staffEmailFromDb,
    this.errorMessage,
  });

  final String loginEmail;

  /// `staff.id` (uuid) when the login email matched a row.
  final String? staffId;
  final String? appId;

  /// `staff.display_name` when the login email matches a staff row.
  final String? staffDisplayName;

  /// `staff.name` (fallback if display_name is empty).
  final String? staffName;

  /// Value from `staff.team_id` (may match `team.id` or `team.app_id`).
  final String? staffTeamIdRaw;
  final String? teamName;

  /// `staff.email` from the matched row (for verification vs login email).
  final String? staffEmailFromDb;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null && staffId != null;

  /// `staff.app_id` when set; otherwise derived from login email local-part.
  String? get resolvedAppId {
    final direct = appId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    if (staffId == null) return null;
    return _appIdGuessFromEmail(loginEmail);
  }

  String? get resolvedDisplayName {
    final dn = staffDisplayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    final sn = staffName?.trim();
    if (sn != null && sn.isNotEmpty) return sn;
    return null;
  }

  static String? _appIdGuessFromEmail(String normalized) {
    final email = normalized.trim().toLowerCase();
    if (email.isEmpty) return null;
    final at = email.indexOf('@');
    if (at <= 0) return email.replaceAll('.', '_');
    final local = email.substring(0, at).trim();
    if (local.isEmpty) return null;
    return local.replaceAll('.', '_');
  }

  /// Plain text for clipboard / selection.
  String get copyableSummary {
    final buf = StringBuffer()
      ..writeln('Login email: $loginEmail')
      ..writeln('staff.display_name: ${staffDisplayName ?? "(null)"}')
      ..writeln('staff.name: ${staffName ?? "(null)"}')
      ..writeln('staff.email (DB): ${staffEmailFromDb ?? "(null)"}')
      ..writeln('staff.id: ${staffId ?? "(null)"}')
      ..writeln('staff.app_id: ${appId ?? "(null)"}')
      ..writeln('staff.team_id: ${staffTeamIdRaw ?? "(null)"}')
      ..writeln('team name: ${teamName ?? "(null)"}');
    if (errorMessage != null) {
      buf.writeln('Lookup error: $errorMessage');
    }
    return buf.toString().trim();
  }
}
