import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/project_record.dart';
import '../../models/singular_subtask.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/task.dart';
import '../../services/database_service.dart';
import 'asana_theme.dart';
import '../asana_landing_screen.dart';

class AsanaPerformancePanel extends StatefulWidget {
  const AsanaPerformancePanel({super.key, required this.palette});

  final AsanaLandingPalette palette;

  @override
  State<AsanaPerformancePanel> createState() => _AsanaPerformancePanelState();
}

class _AsanaPerformancePanelState extends State<AsanaPerformancePanel> {
  bool _loading = true;
  String? _error;
  String _loadedTaskSignature = '';
  Map<String, String> _officeIdByStaffKey = {};
  Map<String, String> _officeNameById = {};
  Map<String, List<SingularSubtask>> _subtasksByTaskId = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final taskIds =
        context
            .read<AppState>()
            .tasks
            .map((t) => t.id.trim())
            .where((id) => id.isNotEmpty)
            .toList()
          ..sort();
    final signature = taskIds.join('|');
    if (signature != _loadedTaskSignature) {
      _loadedTaskSignature = signature;
      _load(taskIds);
    }
  }

  Future<void> _load(List<String> taskIds) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final picker = await DatabaseService.fetchStaffAssigneePickerData();
      final subtasks =
          await DatabaseService.fetchSubtasksGroupedIncludingDeleted(taskIds);
      if (!mounted) return;
      setState(() {
        _officeIdByStaffKey = _officeMapByStaffKey(picker.staff);
        _officeNameById = {
          for (final office in picker.offices)
            office.officeId.trim().toLowerCase(): office.officeName.trim(),
        };
        _subtasksByTaskId = subtasks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Map<String, String> _officeMapByStaffKey(List<StaffForAssignment> staff) {
    final map = <String, String>{};
    for (final s in staff) {
      final officeId = s.officeId?.trim();
      if (officeId == null || officeId.isEmpty) continue;
      final appId = s.assigneeId.trim();
      if (appId.isNotEmpty) map[appId.toLowerCase()] = officeId;
      final uuid = s.staffUuid?.trim();
      if (uuid != null && uuid.isNotEmpty) map[uuid.toLowerCase()] = officeId;
    }
    return map;
  }

  bool _projectDeleted(ProjectRecord p) =>
      p.status.trim().toLowerCase() == 'deleted';

  bool _taskDeleted(Task t) =>
      (t.dbStatus ?? '').trim().toLowerCase() == 'deleted';

  bool _subtaskDeleted(SingularSubtask s) =>
      s.status.trim().toLowerCase() == 'deleted';

  bool _taskCompleted(Task t) {
    final status = (t.dbStatus ?? '').trim().toLowerCase();
    return status == 'completed' ||
        status == 'complete' ||
        t.status == TaskStatus.done;
  }

  bool _subtaskCompleted(SingularSubtask s) {
    final status = s.status.trim().toLowerCase();
    return status == 'completed' || status == 'complete';
  }

  bool _belongsToOffice(Iterable<String?> staffKeys, String officeLabel) {
    final target = officeLabel.trim().toLowerCase();
    if (target.isEmpty) return false;
    for (final rawKey in staffKeys) {
      final key = rawKey?.trim().toLowerCase();
      if (key == null || key.isEmpty) continue;
      final officeId = _officeIdByStaffKey[key]?.trim();
      if (officeId == null || officeId.isEmpty) continue;
      final id = officeId.toLowerCase();
      final name = (_officeNameById[id] ?? '').trim().toLowerCase();
      if (id == target || name == target) return true;
      if (id.contains(target) || name.contains(target)) return true;
    }
    return false;
  }

  Iterable<String?> _projectOwnerKeys(ProjectRecord p) {
    if (p.picStaffUuids.isNotEmpty) return p.picStaffUuids;
    return p.assigneeStaffUuids;
  }

  Iterable<String?> _taskOwnerKeys(Task t) {
    final pic = t.pic?.trim();
    if (pic != null && pic.isNotEmpty) return [pic];
    return t.assigneeIds;
  }

  Iterable<String?> _subtaskOwnerKeys(SingularSubtask s) {
    final pic = s.pic?.trim();
    if (pic != null && pic.isNotEmpty) return [pic];
    return s.assigneeIds;
  }

  _PerformanceMetrics _metricsFor(String officeLabel, AppState state) {
    final projects = state.projects
        .where((p) => !_projectDeleted(p))
        .where((p) => _belongsToOffice(_projectOwnerKeys(p), officeLabel))
        .toList();
    final tasks = state.tasks
        .where((t) => !_taskDeleted(t))
        .where((t) => _belongsToOffice(_taskOwnerKeys(t), officeLabel))
        .toList();
    final subtasks = _subtasksByTaskId.values
        .expand((list) => list)
        .where((s) => !_subtaskDeleted(s))
        .where((s) => _belongsToOffice(_subtaskOwnerKeys(s), officeLabel))
        .toList();

    return _PerformanceMetrics(
      projects: projects.length,
      tasks: tasks.length,
      subtasks: subtasks.length,
      completedTasks: tasks.where(_taskCompleted).length,
      completedSubtasks: subtasks.where(_subtaskCompleted).length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.adminViewMode) {
      return ColoredBox(color: widget.palette.content);
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load performance data.\n$_error',
          textAlign: TextAlign.center,
          style: asanaTextStyle(
            Theme.of(context).textTheme.bodyMedium,
            color: Colors.red.shade700,
          ),
        ),
      );
    }

    final daao = _metricsFor('DAAO', state);
    final cpao = _metricsFor('CPAO', state);

    return ColoredBox(
      color: widget.palette.content,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        children: [
          _PerformanceBlock(
            title: 'DAAO',
            metrics: daao,
            palette: widget.palette,
          ),
          const SizedBox(height: 24),
          _PerformanceBlock(
            title: 'CPAO',
            metrics: cpao,
            palette: widget.palette,
          ),
        ],
      ),
    );
  }
}

class _PerformanceMetrics {
  const _PerformanceMetrics({
    required this.projects,
    required this.tasks,
    required this.subtasks,
    required this.completedTasks,
    required this.completedSubtasks,
  });

  final int projects;
  final int tasks;
  final int subtasks;
  final int completedTasks;
  final int completedSubtasks;
}

class _PerformanceBlock extends StatelessWidget {
  const _PerformanceBlock({
    required this.title,
    required this.metrics,
    required this.palette,
  });

  final String title;
  final _PerformanceMetrics metrics;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final cards = [
      ('Projects', metrics.projects),
      ('Tasks', metrics.tasks),
      ('Subtasks', metrics.subtasks),
      ('Completed tasks', metrics.completedTasks),
      ('Completed subtasks', metrics.completedSubtasks),
    ];
    return Material(
      color: palette.listSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: asanaTextStyle(
                Theme.of(context).textTheme.titleLarge,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: kAsanaTextPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final card in cards)
                  _PerformanceScoreCard(
                    label: card.$1,
                    value: card.$2,
                    palette: palette,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceScoreCard extends StatelessWidget {
  const _PerformanceScoreCard({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final int value;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            palette.accent.withValues(alpha: 0.08),
            palette.listSurface,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.accent.withValues(alpha: 0.16)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: asanaTextStyle(
                  Theme.of(context).textTheme.headlineMedium,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: asanaTextStyle(
                  Theme.of(context).textTheme.bodyMedium,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF3B4552),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
