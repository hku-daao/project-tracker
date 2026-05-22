import 'package:flutter/material.dart';

import '../asana_landing_screen.dart';
import '../high_level/create_subtask_screen.dart';
import 'asana_detail_selection.dart';
import 'asana_create_project_detail_panel.dart';
import 'asana_project_detail_panel.dart';
import 'asana_subtask_detail_panel.dart';
import 'asana_task_detail_panel.dart';

/// Right-hand slide content (Asana-styled detail, not legacy full screens).
class AsanaDetailPanelHost extends StatelessWidget {
  const AsanaDetailPanelHost({
    super.key,
    required this.selection,
    required this.palette,
    required this.onClose,
    this.onPop,
    this.onPushCreateSubtask,
    this.onPushSubtask,
    this.detailRefreshToken = 0,
  });

  final AsanaDetailSelection selection;
  final AsanaLandingPalette palette;
  final VoidCallback onClose;
  final VoidCallback? onPop;
  final void Function(String parentTaskId)? onPushCreateSubtask;
  final void Function(String subtaskId)? onPushSubtask;
  final int detailRefreshToken;

  @override
  Widget build(BuildContext context) {
    return switch (selection) {
      AsanaTaskDetailSelection(:final taskId) => AsanaTaskDetailPanel(
          taskId: taskId,
          palette: palette,
          refreshToken: detailRefreshToken,
          onClose: onClose,
          onPushCreateSubtask: onPushCreateSubtask == null
              ? null
              : () => onPushCreateSubtask!(taskId),
          onPushSubtask: onPushSubtask,
        ),
      AsanaSubtaskDetailSelection(:final subtaskId) => AsanaSubtaskDetailPanel(
          subtaskId: subtaskId,
          palette: palette,
        ),
      AsanaProjectDetailSelection(:final projectId) => AsanaProjectDetailPanel(
          projectId: projectId,
        ),
      AsanaCreateSubtaskDetailSelection(:final parentTaskId) =>
        CreateSubtaskScreen(
          taskId: parentTaskId,
          onAsanaPanelClose: onPop ?? onClose,
          onAsanaSubtaskCreated: (_) => (onPop ?? onClose)(),
        ),
      AsanaCreateTaskDetailSelection() => AsanaTaskDetailPanel(
          createMode: true,
          palette: palette,
          onClose: onClose,
        ),
      AsanaCreateProjectDetailSelection() => AsanaCreateProjectDetailPanel(
          palette: palette,
          onClose: onClose,
        ),
    };
  }
}
