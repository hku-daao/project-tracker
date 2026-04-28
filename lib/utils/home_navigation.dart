import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// [MaterialPageRoute.settings.name] for [CustomizedDashboardPage] (Overview).
const String kOverviewDashboardRouteName = 'overview_dashboard';

/// Pops until Overview is on top, otherwise until landing home — never drops Overview when present.
void popUntilOverviewOrHome(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).popUntil((route) {
    final name = route.settings.name;
    return name == kOverviewDashboardRouteName || route.isFirst;
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final r = ModalRoute.of(context);
    if (r != null && r.isFirst) {
      app.requestSwitchToTasksTab();
    }
  });
}

/// Pops the entire stack back to the first route (home), then focuses the task list.
void navigateToHomeTasksTab(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).popUntil((route) => route.isFirst);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    app.requestSwitchToTasksTab();
  });
}
