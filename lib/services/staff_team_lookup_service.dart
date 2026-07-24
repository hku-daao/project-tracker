import 'postgrest_client.dart';

import '../config/postgrest_config.dart';
import '../models/staff_team_lookup.dart';

/// Revamp step 1: match logged-in email to [staff], then resolve [team] by
/// **staff.team_id = team.team_id** (same as `LEFT JOIN team ON …`).
class StaffTeamLookupService {
  StaffTeamLookupService._();

  static String? _localPart(String normalized) {
    final email = normalized.trim().toLowerCase();
    final at = email.indexOf('@');
    if (at <= 0) return null;
    final local = email.substring(0, at).trim();
    return local.isEmpty ? null : local;
  }

  static String? _appIdGuessFromEmail(String normalized) {
    final local = _localPart(normalized);
    if (local == null) return null;
    return local.replaceAll('.', '_');
  }

  /// HKU SSO may return `@hku.hk` while staff rows use `@connect.hku.hk` (or vice versa).
  static List<String> _emailLookupCandidates(String normalized) {
    final seen = <String>{};
    void add(String? value) {
      final v = value?.trim().toLowerCase();
      if (v != null && v.isNotEmpty) seen.add(v);
    }

    add(normalized);
    final local = _localPart(normalized);
    if (local == null) return seen.toList();

    add('$local@hku.hk');
    add('$local@connect.hku.hk');
    return seen.toList();
  }

  static Future<Map<String, dynamic>?> _findStaffRow(
    PostgrestClient db,
    String normalized,
  ) async {
    for (final candidate in _emailLookupCandidates(normalized)) {
      final row = await db
          .from('staff')
          .select('id, app_id, team_id, email, name, active')
          .ilike('email', candidate)
          .limit(1)
          .maybeSingle();
      if (row != null) return row;
    }

    final local = _localPart(normalized);
    if (local != null) {
      final prefixRows = await db
          .from('staff')
          .select('id, app_id, team_id, email, name, active')
          .ilike('email', '$local@%')
          .limit(5);
      if (prefixRows is List && prefixRows.isNotEmpty) {
        Map<String, dynamic>? preferred;
        for (final raw in prefixRows) {
          final row = Map<String, dynamic>.from(raw as Map);
          final email = row['email']?.toString().trim().toLowerCase() ?? '';
          if (email == '$local@hku.hk') return row;
          preferred ??= row;
        }
        if (preferred != null) return preferred;
      }
    }

    final appGuess = _appIdGuessFromEmail(normalized);
    if (appGuess != null && appGuess.isNotEmpty) {
      return db
          .from('staff')
          .select('id, app_id, team_id, email, name, active')
          .eq('app_id', appGuess)
          .limit(1)
          .maybeSingle();
    }
    return null;
  }

  static Future<StaffTeamLookupResult> lookupByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) {
      return StaffTeamLookupResult(
        loginEmail: email,
        errorMessage: 'Empty email',
      );
    }
    if (!PostgrestConfig.isConfigured) {
      return StaffTeamLookupResult(
        loginEmail: normalized,
        errorMessage: 'Database not configured',
      );
    }

    try {
      final db = PostgrestClient.instance;
      final staffRes = await _findStaffRow(db, normalized);

      if (staffRes == null) {
        return StaffTeamLookupResult(
          loginEmail: normalized,
          errorMessage:
              'No staff row for SSO email "$normalized" (check staff.email matches HKU login)',
        );
      }

      final staffId = staffRes['id']?.toString().trim();
      final appId = staffRes['app_id'] as String?;
      final teamIdRaw = staffRes['team_id'];
      final staffEmailFromDb = staffRes['email'] as String?;
      final staffActive = staffRes['active'] is bool
          ? staffRes['active'] as bool
          : true;
      final staffNameRaw = staffRes['name'] as String?;
      final staffName = staffNameRaw?.trim().isNotEmpty == true
          ? staffNameRaw!.trim()
          : null;
      String? teamName;
      if (teamIdRaw != null && teamIdRaw.toString().isNotEmpty) {
        final tid = teamIdRaw.toString().trim();
        final teamRow = await db
            .from('team')
            .select('team_name')
            .eq('team_id', tid)
            .maybeSingle();
        if (teamRow != null) {
          teamName = teamRow['team_name'] as String?;
        }
      }

      return StaffTeamLookupResult(
        loginEmail: normalized,
        staffId: staffId?.isNotEmpty == true ? staffId : null,
        appId: appId,
        staffDisplayName: staffName,
        staffName: staffName,
        staffTeamIdRaw: teamIdRaw?.toString(),
        teamName: teamName,
        staffEmailFromDb: staffEmailFromDb,
        staffActive: staffActive,
      );
    } catch (e) {
      return StaffTeamLookupResult(
        loginEmail: normalized,
        errorMessage: e.toString(),
      );
    }
  }
}
