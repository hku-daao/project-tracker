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
    this.staffActive,
    this.errorMessage,
  });

  final String loginEmail;

  /// `staff.id` (uuid) when the login email matched a row.
  final String? staffId;
  final String? appId;

  /// Display label for compatibility; now sourced from `staff.name`.
  final String? staffDisplayName;

  /// `staff.name` from the matched staff row.
  final String? staffName;

  /// Value from `staff.team_id` (may match `team.id` or `team.app_id`).
  final String? staffTeamIdRaw;
  final String? teamName;

  /// `staff.email` from the matched row (for verification vs login email).
  final String? staffEmailFromDb;
  final bool? staffActive;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null && staffId != null;
  bool get isActive => staffActive != false;

  /// `staff.app_id` when set; otherwise derived from login email local-part.
  String? get resolvedAppId {
    final direct = appId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    if (staffId == null) return null;
    return _appIdGuessFromEmail(loginEmail);
  }

  String? get resolvedDisplayName {
    final sn = staffName?.trim();
    if (sn != null && sn.isNotEmpty) return sn;
    final dn = staffDisplayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
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
      ..writeln('staff.name: ${staffName ?? "(null)"}')
      ..writeln('staff.email (DB): ${staffEmailFromDb ?? "(null)"}')
      ..writeln('staff.active: ${staffActive ?? "(null)"}')
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
