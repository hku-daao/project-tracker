import 'package:shared_preferences/shared_preferences.dart';

/// Persisted expand/collapse for Projects / Tasks sections on landing and Overview.
class LandingListSectionsStorage {
  LandingListSectionsStorage._();

  static String _k(String suffix, String uid) => 'list_sections_${suffix}_v1_$uid';

  static Future<bool> loadExpanded({
    required String uid,
    required LandingListSectionKey key,
    bool defaultExpanded = true,
  }) async {
    final p = await SharedPreferences.getInstance();
    final v = p.getBool(_k(key.storageSuffix, uid));
    return v ?? defaultExpanded;
  }

  static Future<void> saveExpanded({
    required String uid,
    required LandingListSectionKey key,
    required bool expanded,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_k(key.storageSuffix, uid), expanded);
  }
}

enum LandingListSectionKey {
  landingProjects('landing_projects'),
  landingTasks('landing_tasks'),
  overviewProjects('overview_projects'),
  overviewTasksSubtasks('overview_tasks_subtasks');

  const LandingListSectionKey(this.storageSuffix);
  final String storageSuffix;
}
