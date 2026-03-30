import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/task.dart';
import '../priority.dart';
import '../services/supabase_service.dart';
import '../screens/task_detail_screen.dart';

/// Task row for list tabs: name, assignees, status, start/due dates (matches singular + legacy tasks).
class TaskListCard extends StatelessWidget {
  const TaskListCard({super.key, required this.task});

  final Task task;

  static String statusLabel(Task t) {
    if (t.isSingularTableRow) {
      final raw = t.dbStatus?.trim();
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return taskStatusDisplayNames[t.status] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final t = task;
    return FutureBuilder<Map<String, String>>(
      future: SupabaseService.staffDisplayNamesForKeys(t.assigneeIds),
      builder: (context, snapshot) {
        final officerNames = t.assigneeIds
            .map((id) => snapshot.data?[id] ?? state.assigneeById(id)?.name ?? id)
            .toList()
          ..sort();
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(t.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (officerNames.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Assignee(s): ${officerNames.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                if (t.createByStaffName != null &&
                    t.createByStaffName!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Creator: ${t.createByStaffName!.trim()}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                Text(
                  '${priorityToDisplayName(t.priority)} · ${statusLabel(t)}'
                  '${t.startDate != null ? ' · Start ${DateFormat.yMMMd().format(t.startDate!)}' : ''}'
                  '${t.endDate != null ? ' · Due ${DateFormat.yMMMd().format(t.endDate!)}' : ''}',
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TaskDetailScreen(taskId: t.id),
              ),
            ),
          ),
        );
      },
    );
  }
}
