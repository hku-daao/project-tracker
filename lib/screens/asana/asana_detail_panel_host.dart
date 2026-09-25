import 'package:flutter/material.dart';

import '../asana_landing_screen.dart';
import 'asana_create_discussion_detail_panel.dart';
import 'asana_detail_selection.dart';
import 'asana_create_project_detail_panel.dart';
import 'asana_project_detail_panel.dart';
import 'asana_subproject_detail_panel.dart';
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
    this.onPushCreateTaskForProject,
    this.onPushTaskFromProject,
    this.onPushCreateSubproject,
    this.onPushSubproject,
    this.onSubprojectCreated,
    this.onTaskCreated,
    this.onDiscussionCreated,
    this.onProjectCreated,
    this.onProjectChanged,
    this.onSubtaskCreated,
    this.onSubtaskChanged,
    this.onTaskChanged,
    this.detailRefreshToken = 0,
  });

  final AsanaDetailSelection selection;
  final AsanaLandingPalette palette;
  final VoidCallback onClose;
  final VoidCallback? onPop;
  final void Function(String parentTaskId)? onPushCreateSubtask;
  final void Function(String subtaskId)? onPushSubtask;
  final void Function(String projectId)? onPushCreateTaskForProject;
  final void Function(String taskId)? onPushTaskFromProject;
  final void Function(String projectId)? onPushCreateSubproject;
  final void Function(String subprojectId, String projectId)? onPushSubproject;
  final void Function(String projectId, String subprojectId)? onSubprojectCreated;
  final void Function(String taskId)? onTaskCreated;
  final VoidCallback? onDiscussionCreated;
  final void Function(String projectId)? onProjectCreated;
  final VoidCallback? onProjectChanged;
  final void Function(String parentTaskId, String subtaskId)? onSubtaskCreated;
  final VoidCallback? onSubtaskChanged;
  final VoidCallback? onTaskChanged;
  final int detailRefreshToken;

  @override
  Widget build(BuildContext context) {
    return switch (selection) {
      AsanaTaskDetailSelection(:final taskId) => AsanaTaskDetailPanel(
        taskId: taskId,
        palette: palette,
        refreshToken: detailRefreshToken,
        onClose: onClose,
        onChanged: onTaskChanged,
        onPushCreateSubtask: onPushCreateSubtask == null
            ? null
            : () => onPushCreateSubtask!(taskId),
        onPushSubtask: onPushSubtask,
      ),
      AsanaSubtaskDetailSelection(:final subtaskId) => AsanaSubtaskDetailPanel(
        subtaskId: subtaskId,
        palette: palette,
        onClose: onPop ?? onClose,
        onChanged: onSubtaskChanged,
      ),
      AsanaProjectDetailSelection(:final projectId) => AsanaProjectDetailPanel(
        projectId: projectId,
        palette: palette,
        refreshToken: detailRefreshToken,
        onClose: onClose,
        onChanged: onProjectChanged,
        onPushCreateTask: onPushCreateTaskForProject == null
            ? null
            : () => onPushCreateTaskForProject!(projectId),
        onPushTask: onPushTaskFromProject,
        onPushCreateSubproject: onPushCreateSubproject == null
            ? null
            : () => onPushCreateSubproject!(projectId),
        onPushSubproject: onPushSubproject == null
            ? null
            : (subprojectId) => onPushSubproject!(subprojectId, projectId),
      ),
      AsanaCreateSubtaskDetailSelection(:final parentTaskId) =>
        AsanaSubtaskDetailPanel(
          createMode: true,
          parentTaskId: parentTaskId,
          palette: palette,
          onClose: onPop ?? onClose,
          onCreated: onSubtaskCreated == null
              ? null
              : (subtaskId) => onSubtaskCreated!(parentTaskId, subtaskId),
          onChanged: onSubtaskChanged,
        ),
      AsanaCreateTaskDetailSelection(:final initialProjectId) =>
        AsanaTaskDetailPanel(
          createMode: true,
          initialProjectId: initialProjectId,
          palette: palette,
          onClose: onClose,
          onCreated: onTaskCreated,
        ),
      AsanaCreateProjectDetailSelection() => AsanaCreateProjectDetailPanel(
        palette: palette,
        onClose: onClose,
        onCreated: onProjectCreated,
      ),
      AsanaCreateDiscussionDetailSelection() => AsanaCreateDiscussionDetailPanel(
        palette: palette,
        onClose: onClose,
        onCreated: onDiscussionCreated,
      ),
      AsanaSubprojectDetailSelection(
        :final subprojectId,
        :final projectId,
      ) => AsanaSubprojectDetailPanel(
        projectId: projectId,
        subprojectId: subprojectId,
        palette: palette,
        onClose: onPop ?? onClose,
        onChanged: onProjectChanged,
      ),
      AsanaCreateSubprojectDetailSelection(:final projectId) =>
        AsanaSubprojectDetailPanel(
          createMode: true,
          projectId: projectId,
          palette: palette,
          onClose: onPop ?? onClose,
          onCreated: onSubprojectCreated == null
              ? null
              : (subprojectId) => onSubprojectCreated!(projectId, subprojectId),
          onChanged: onProjectChanged,
        ),
    };
  }
}
