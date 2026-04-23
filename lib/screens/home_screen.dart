import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_state.dart';
import '../../models/staff_team_lookup.dart';
import '../../config/admin_config.dart';
import '../../config/api_config.dart';
import '../../config/environment_config.dart';
import '../../config/supabase_config.dart';
import '../../services/backend_api.dart';
import '../../web_deep_link.dart';
import 'high_level/initiative_list_screen.dart';
import 'high_level/create_task_screen.dart';
import 'admin/system_admin_screen.dart';

/// Warn before leaving the create flow while a draft exists (create screen / Sign out).
Future<bool> _confirmLeaveCreateTaskDraft(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Unsaved task'),
      content: Text.rich(
        TextSpan(
          style: Theme.of(ctx).textTheme.bodyLarge,
          children: const [
            TextSpan(text: 'Press '),
            TextSpan(
              text: 'Create task',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text:
                  ' to save your task. If you leave now, nothing will be saved.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Stay'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Leave anyway'),
        ),
      ],
    ),
  );
  return r == true;
}

/// Microsoft Forms — feedback (AppBar).
const String _kFeedbackFormUrl =
    'https://forms.cloud.microsoft/Pages/ResponsePage.aspx?id=TrX5QnckukG_CXoNKoP_CXmxjjVqONdDujd4tWBFFN9UMk1ZS0EzMFZSSlFSMkhXTjI5UE82QThKTC4u';

Future<void> _openFeedbackForm(BuildContext context) async {
  final uri = Uri.parse(_kFeedbackFormUrl);
  final ok = await canLaunchUrl(uri);
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(duration: const Duration(seconds: 4), content: Text('Could not open feedback form')),
    );
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _welcomeDisplayName(StaffTeamLookupResult? lookup) {
  final display = lookup?.staffDisplayName?.trim();
  if (display != null && display.isNotEmpty) return display;
  final n = lookup?.staffName?.trim();
  if (n != null && n.isNotEmpty) return n;
  final u = FirebaseAuth.instance.currentUser;
  final dn = u?.displayName?.trim();
  if (dn != null && dn.isNotEmpty) return dn;
  final e = u?.email;
  if (e != null && e.isNotEmpty) {
    final at = e.split('@').first.trim();
    if (at.isNotEmpty) return at;
  }
  return 'User';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _backendOk;
  String? _backendError;
  bool _checkingBackend = false;
  final BackendApi _backendApi = BackendApi();
  AppState? _appState;

  /// Hides the FAB while scrolling down; shows again on scroll up or when scrolling stops.
  bool _createTaskFabVisible = true;

  @override
  void initState() {
    super.initState();
    _checkBackend();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (!identical(_appState, app)) {
      _appState?.removeListener(_onConsumeSwitchToTasksTab);
      _appState = app;
      _appState!.addListener(_onConsumeSwitchToTasksTab);
    }
  }

  /// Clears [AppState.takeSwitchToTasksTabPending] after save / deep link; task list is always shown.
  void _onConsumeSwitchToTasksTab() {
    if (!mounted) return;
    _appState?.takeSwitchToTasksTabPending();
  }

  @override
  void dispose() {
    _appState?.removeListener(_onConsumeSwitchToTasksTab);
    super.dispose();
  }

  void _openCreateTaskScreen() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Create task')),
          body: const CreateTaskScreen(),
        ),
      ),
    );
  }

  bool _onLandingScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollUpdateNotification) {
      final d = n.scrollDelta;
      if (d == null) return false;
      if (d > 6 && _createTaskFabVisible) {
        setState(() => _createTaskFabVisible = false);
      } else if (d < -6 && !_createTaskFabVisible) {
        setState(() => _createTaskFabVisible = true);
      }
    } else if (n is ScrollEndNotification) {
      if (!_createTaskFabVisible) {
        setState(() => _createTaskFabVisible = true);
      }
    }
    return false;
  }

  Future<void> _checkBackend() async {
    if (_checkingBackend) return;
    setState(() {
      _checkingBackend = true;
      _backendError = null;
    });
    try {
      final result = await _backendApi.checkHealth();
      if (mounted) {
        setState(() {
          _backendOk = result.ok;
          _backendError = result.ok ? null : (result.message ?? 'Unknown error');
          _checkingBackend = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _backendOk = false;
          _backendError = e.toString();
          _checkingBackend = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final revampLookup = context.watch<AppState>().revampStaffLookup;
    final welcomeName = _welcomeDisplayName(revampLookup);
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ) ??
        const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
        );
    final welcomeStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ) ??
        const TextStyle(fontWeight: FontWeight.w600);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 0,
        titleSpacing: 0,
        centerTitle: false,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final barW = constraints.maxWidth;
            return SizedBox(
              width: barW,
              height: kToolbarHeight,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Project Tracker',
                      style: titleStyle,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: barW * 0.42),
                        child: Text(
                          'Welcome, $welcomeName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: welcomeStyle,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (FirebaseAuth.instance.currentUser?.email
                                ?.toLowerCase() ==
                            AdminConfig.systemAdminEmail.toLowerCase())
                          IconButton(
                            icon: const Icon(
                              Icons.admin_panel_settings_outlined,
                            ),
                            tooltip: 'System Admin',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) =>
                                      const SystemAdminScreen(),
                                ),
                              );
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.feedback_outlined),
                          tooltip: 'Feedback',
                          onPressed: () => _openFeedbackForm(context),
                        ),
                        if (kIsWeb)
                          IconButton(
                            icon: const Icon(Icons.logout),
                            onPressed: () async {
                              final appState = context.read<AppState>();
                              if (appState.hasCreateTaskUnsavedDraft) {
                                final leave =
                                    await _confirmLeaveCreateTaskDraft(
                                  context,
                                );
                                if (!context.mounted || !leave) return;
                              }
                              if (kIsWeb) {
                                syncWebLocationForLanding();
                              }
                              await FirebaseAuth.instance.signOut();
                            },
                            tooltip: 'Sign out',
                          ),
                        Tooltip(
                          message: _backendOk == true
                              ? 'Backend (${AppEnvironment.label}): ${ApiConfig.baseUrl}'
                              : _backendOk == false
                                  ? 'Backend unavailable${_backendError != null ? ': $_backendError' : ''}'
                                  : 'Checking backend...',
                          child: IconButton(
                            icon: _checkingBackend
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _backendOk == true
                                        ? Icons.cloud_done
                                        : Icons.cloud_off,
                                    color: _backendOk == true
                                        ? Colors.green
                                        : _backendOk == false
                                            ? Colors.red
                                            : Colors.grey,
                                  ),
                            onPressed: () async {
                              await _checkBackend();
                              if (mounted &&
                                  _backendOk == false &&
                                  _backendError != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Backend: $_backendError'),
                                    duration: const Duration(seconds: 4),
                                    action: SnackBarAction(
                                      label: 'Retry',
                                      onPressed: _checkBackend,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!SupabaseConfig.isConfigured)
            Card(
              margin: const EdgeInsets.all(8),
              color: Colors.amber.shade100,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.storage, color: Colors.amber.shade900),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Supabase URL/key not set (${AppEnvironment.label}) — nothing is saved to the cloud. '
                        'For testing: set _testingAnonKey in supabase_config.dart or use '
                        '--dart-define=SUPABASE_ANON_KEY=.... See docs/ENVIRONMENTS.md.',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onLandingScrollNotification,
              child: const InitiativeListScreen(),
            ),
          ),
        ],
      ),
      floatingActionButton: AnimatedOpacity(
        opacity: _createTaskFabVisible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: !_createTaskFabVisible,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FloatingActionButton.extended(
              onPressed: _openCreateTaskScreen,
              icon: const Icon(Icons.add),
              label: const Text('Create task'),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
