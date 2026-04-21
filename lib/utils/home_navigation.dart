import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// Pops the entire stack back to the first route (home), then selects the **Tasks** tab.
void navigateToHomeTasksTab(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).popUntil((route) => route.isFirst);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    app.requestSwitchToTasksTab();
  });
}
