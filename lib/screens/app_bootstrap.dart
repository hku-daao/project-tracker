import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../config/dev_auth_context.dart';
import '../config/postgrest_config.dart';
import '../models/assignee.dart';
import '../services/sso_auth_service.dart';
import '../services/staff_team_lookup_service.dart';
import '../services/database_service.dart';
import '../services/task_fetch_visibility.dart';
import '../widgets/project_tracker_logo.dart';
import 'asana_landing_screen.dart';

/// All platforms use the Asana shell; legacy Home / Overview routes are removed in phase 2.
Widget _bootstrapShellChild() => const AsanaLandingScreen();

/// On startup: revamp step 1 loads staff/team by email; tasks + deleted-task audit load from the database.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.suppressLoadingUi = false, this.onReady});

  /// When true, data still loads but [StartupLoadingView] is not shown (parent owns startup UI).
  final bool suppressLoadingUi;
  final VoidCallback? onReady;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // Never block the UI longer than 5s even if data fetches hang.
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_ready) {
        debugPrint('AppBootstrap: forcing ready after 5s');
        _markReady();
      }
    });
  }

  void _markReady() {
    if (!mounted || _ready) return;
    setState(() => _ready = true);
    widget.onReady?.call();
  }

  Future<void> _load() async {
    debugPrint('AppBootstrap: load start');
    try {
      await _loadData().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      debugPrint('AppBootstrap: load timed out after 5s');
    } catch (e, st) {
      debugPrint('AppBootstrap: load failed: $e\n$st');
    }
    _markReady();
  }

  Future<void> _loadData() async {
    final state = context.read<AppState>();

    // -------------------------------------------------------------------------
    // REVAMP STEP 1 — Supabase: staff (by email) + team name via staff.team_id
    // -------------------------------------------------------------------------
    try {
      var email = activeUserEmail();
      if (email == null || email.isEmpty) {
        await SsoAuthService.refreshSession();
        email = activeUserEmail();
      }
      debugPrint('AppBootstrap: activeUserEmail=$email');
      if (email != null && email.isNotEmpty) {
        final lookup = await StaffTeamLookupService.lookupByEmail(email);
        final resolvedAppId = lookup.resolvedAppId;
        debugPrint(
          'AppBootstrap: staff lookup success=${lookup.isSuccess} '
          'appId=$resolvedAppId staffId=${lookup.staffId} '
          'error=${lookup.errorMessage}',
        );
        if (mounted) {
          state.setRevampStaffLookup(lookup);
        }
        if (mounted && lookup.isSuccess) {
          state.setUserStaffContext(
            staffAppId: resolvedAppId,
            staffUuid: lookup.staffId,
          );
          final display = lookup.resolvedDisplayName;
          if (resolvedAppId != null &&
              resolvedAppId.isNotEmpty &&
              display != null &&
              display.isNotEmpty) {
            state.mergeAssignees([Assignee(id: resolvedAppId, name: display)]);
          }
          final subIds =
              await DatabaseService.fetchSubordinateAppIdsForSupervisor(
                resolvedAppId ?? '',
              );
          if (mounted) state.setSubordinateAppIds(subIds);
        }
      }
    } catch (e) {
      debugPrint('AppBootstrap revamp staff/team lookup: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      state.setAdminViewMode(
        prefs.getBool(AppState.adminViewStorageKey) ?? false,
      );
    } catch (e) {
      debugPrint('AppBootstrap admin view restore: $e');
    }

    TaskFetchVisibility? taskVisibility;
    if (mounted && !state.adminViewMode) {
      taskVisibility = await DatabaseService.enrichTaskFetchVisibility(
        state.buildTaskFetchVisibility(),
      );
      if (taskVisibility != null) {
        state.setSubordinateStaffUuids(taskVisibility.subordinateStaffUuids);
        final resolvedUuid = taskVisibility.supervisorStaffUuid?.trim();
        if (resolvedUuid != null && resolvedUuid.isNotEmpty) {
          state.setUserStaffContext(
            staffAppId: state.effectiveStaffAppId,
            staffUuid: resolvedUuid,
          );
        }
      }
    }

    // Load Asana tasks/projects from the database.
    if (!PostgrestConfig.isConfigured) {
      return;
    }
    try {
      final adminViewMode = state.adminViewMode;
      final taskData = await DatabaseService.fetchTasks(
        visibility: adminViewMode
            ? null
            : taskVisibility ?? state.buildTaskFetchVisibility(),
      );
      if (!mounted) return;
      final loaded = taskData ?? TasksLoadResult.empty;
      debugPrint(
        'AppBootstrap: fetchTasks returned ${loaded.tasks.length} tasks',
      );
      state.applyTasks(
        loaded,
        visibilityScoped:
            !adminViewMode &&
            taskVisibility != null &&
            taskVisibility.isConfigured,
      );
      debugPrint(
        'AppBootstrap: ${state.tasks.length} tasks in AppState '
        '(visibilityScoped=${state.tasksLoadedWithVisibilityScope}, '
        'staffAppId=${state.userStaffAppId}, '
        'lookupKeys=${state.taskVisibilityLookupKeys.length})',
      );
      final filterTeams = await DatabaseService.fetchTeamsForFilter();
      final staffLabels = await DatabaseService.fetchStaffAssignees();
      final appIdToTeamId = await DatabaseService.fetchStaffAppIdToTeamIdMap();
      if (!mounted) return;
      if (filterTeams.isNotEmpty) {
        state.setTeamsForFilter(filterTeams);
      }
      if (staffLabels.isNotEmpty) {
        state.mergeAssignees(staffLabels);
      }
      if (appIdToTeamId.isNotEmpty) {
        state.setStaffAppIdToTeamIdMap(appIdToTeamId);
      }
      final projects = await DatabaseService.fetchAllProjects();
      if (!mounted) return;
      state.applyProjects(projects);
    } catch (e) {
      debugPrint('AppBootstrap: load tasks/projects from the database: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      if (widget.suppressLoadingUi) {
        return const SizedBox.shrink();
      }
      return Scaffold(
        body: StartupLoadingView(
          label: PostgrestConfig.isConfigured ? 'Loading' : 'Starting',
        ),
      );
    }
    if (_error != null && PostgrestConfig.isConfigured) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _ready = false;
                      _error = null;
                    });
                    _load();
                  },
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Continue without database data'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _StartupShell(child: _bootstrapShellChild());
  }
}

class StartupLoadingView extends StatelessWidget {
  const StartupLoadingView({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const palette = AsanaLandingPalette.asana;
    return ColoredBox(
      color: palette.banner,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const ProjectTrackerLogo(height: 48),
                const SizedBox(width: 12),
                Text(
                  'Project\nTracker',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: palette.onBanner,
                    height: 1.05,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.onBanner,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: Color(0x66FFFFFF),
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupShell extends StatelessWidget {
  const _StartupShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
