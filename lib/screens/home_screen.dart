import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_state.dart';
import '../../models/staff_team_lookup.dart';
import '../../config/admin_config.dart';
import '../../config/environment_config.dart';
import '../../config/supabase_config.dart';
import '../../utils/home_navigation.dart';
import '../../web_deep_link.dart';
import '../../widgets/project_tracker_drawer.dart';
import '../services/startup_view_storage.dart';
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

const String _kImportantNoticeBody =
    'Do not store donor, prospect, or alumni data in Project Tracker, '
    'including personal details, giving history, or engagement records. '
    'Use Project Tracker only for task-based entries such as "prepare donor report" '
    'or "update alumni engagement plan", and link to the appropriate secure system—'
    'such as the institutional CRM or advancement intelligence platform—where the '
    'actual information is maintained.';

Future<void> _openFeedbackForm(BuildContext context) async {
  final uri = Uri.parse(_kFeedbackFormUrl);
  final ok = await canLaunchUrl(uri);
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(duration: Duration(seconds: 4), content: Text('Could not open feedback form')),
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
  AppState? _appState;

  /// Hides the FAB while scrolling down; shows again on scroll up or when scrolling stops.
  bool _createTaskFabVisible = true;

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

  void _closeDrawerThenFeedback() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openFeedbackForm(context);
    });
  }

  void _closeDrawerThenGoHome() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  void _closeDrawerThenOpenCustomizedDashboard() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: kOverviewDashboardRouteName),
          builder: (context) => const CustomizedDashboardPage(),
        ),
      );
    });
  }

  void _closeDrawerThenImportantNotice() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Important Notice'),
          content: SingleChildScrollView(
            child: Text(
              _kImportantNoticeBody,
              style: Theme.of(ctx).textTheme.bodyLarge,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _closeDrawerThenSignOut() async {
    Navigator.of(context).pop();
    if (!mounted) return;
    final appState = context.read<AppState>();
    if (appState.hasCreateTaskUnsavedDraft) {
      final leave = await _confirmLeaveCreateTaskDraft(context);
      if (!mounted || !leave) return;
    }
    if (kIsWeb) {
      syncWebLocationForLanding();
    }
    await FirebaseAuth.instance.signOut();
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
    return Scaffold(
      drawer: ProjectTrackerDrawer(
        welcomeName: welcomeName,
        onHome: _closeDrawerThenGoHome,
        onDashboardCustomized: _closeDrawerThenOpenCustomizedDashboard,
        onFeedback: _closeDrawerThenFeedback,
        onImportantNotice: _closeDrawerThenImportantNotice,
        onSignOut: () async {
          await _closeDrawerThenSignOut();
        },
      ),
      appBar: AppBar(
        centerTitle: true,
        titleSpacing: 0,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Project Tracker',
            style: titleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          if (FirebaseAuth.instance.currentUser?.email?.toLowerCase() ==
              AdminConfig.systemAdminEmail.toLowerCase())
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'System Admin',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const SystemAdminScreen(),
                  ),
                );
              },
            ),
        ],
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

/// Overview (flat task list): drawer, pin as default view, FAB — body is
/// [InitiativeListScreen.customizedFlat].
class CustomizedDashboardPage extends StatefulWidget {
  const CustomizedDashboardPage({super.key});

  @override
  State<CustomizedDashboardPage> createState() => _CustomizedDashboardPageState();
}

class _CustomizedDashboardPageState extends State<CustomizedDashboardPage> {
  bool _createTaskFabVisible = true;
  bool _preferCustomizedLoaded = false;
  bool _preferCustomized = false;

  @override
  void initState() {
    super.initState();
    _loadPinPreference();
  }

  Future<void> _loadPinPreference() async {
    final v = await StartupViewStorage.isCustomizedPinned();
    if (!mounted) return;
    setState(() {
      _preferCustomized = v;
      _preferCustomizedLoaded = true;
    });
  }

  Future<void> _togglePinDefaultView() async {
    final next = !_preferCustomized;
    await StartupViewStorage.setPreferCustomized(next);
    if (!mounted) return;
    setState(() => _preferCustomized = next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Overview will open by default next time you start the app.'
              : 'Landing page will open by default.',
        ),
      ),
    );
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

  bool _onCustomizedScrollNotification(ScrollNotification n) {
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

  @override
  Widget build(BuildContext context) {
    final revampLookup = context.watch<AppState>().revampStaffLookup;
    final welcomeName = _welcomeDisplayName(revampLookup);
    final overviewTitleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ) ??
        const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
        );
    return Scaffold(
      drawer: ProjectTrackerDrawer(
        welcomeName: welcomeName,
        onHome: () {
          Navigator.of(context).pop();
          Navigator.of(context).pop();
        },
        onDashboardCustomized: () => Navigator.of(context).pop(),
        onFeedback: () {
          Navigator.of(context).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) _openFeedbackForm(context);
          });
        },
        onImportantNotice: () {
          Navigator.of(context).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Important Notice'),
                content: SingleChildScrollView(
                  child: Text(
                    _kImportantNoticeBody,
                    style: Theme.of(ctx).textTheme.bodyLarge,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          });
        },
        onSignOut: () async {
          Navigator.of(context).pop();
          if (!context.mounted) return;
          final appState = context.read<AppState>();
          if (appState.hasCreateTaskUnsavedDraft) {
            final leave = await _confirmLeaveCreateTaskDraft(context);
            if (!context.mounted || !leave) return;
          }
          if (kIsWeb) {
            syncWebLocationForLanding();
          }
          await FirebaseAuth.instance.signOut();
        },
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        titleSpacing: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Overview',
            style: overviewTitleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          if (_preferCustomizedLoaded)
            IconButton(
              tooltip: _preferCustomized
                  ? 'Unpin default view'
                  : 'Pin Overview as default view',
              icon: Icon(
                _preferCustomized ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              onPressed: _togglePinDefaultView,
            ),
        ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onCustomizedScrollNotification,
        child: const InitiativeListScreen(customizedFlat: true),
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
