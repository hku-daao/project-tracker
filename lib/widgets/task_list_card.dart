import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/task.dart';
import '../priority.dart';
import '../services/supabase_service.dart';
import '../screens/task_detail_screen.dart';

/// PIC team colour definition (`staff.team_id` / `team.team_id` business keys).
class PicTeamColorEntry {
  const PicTeamColorEntry({
    required this.teamKey,
    required this.color,
    required this.legendLabel,
  });

  final String teamKey;
  final Color color;
  final String legendLabel;
}

/// Ordered list for [TaskListCard.cardColorForPicTeam] and [PicTeamColorLegend].
const List<PicTeamColorEntry> kPicTeamColorEntries = [
  PicTeamColorEntry(
    teamKey: 'advancement_intel',
    color: Color(0xFFF0E68C),
    legendLabel: 'Advancement Intelligence',
  ),
  PicTeamColorEntry(
    teamKey: 'president_office',
    color: Color(0xFFDDA0DD),
    legendLabel: 'President Office',
  ),
  PicTeamColorEntry(
    teamKey: 'fundraising',
    color: Color(0xFF00FFFF),
    legendLabel: 'Fundraising',
  ),
  PicTeamColorEntry(
    teamKey: 'alumni',
    color: Color(0xFF7CFC00),
    legendLabel: 'Alumni',
  ),
  PicTeamColorEntry(
    teamKey: 'admin_team',
    color: Color(0xFFFA8072),
    legendLabel: 'Admin',
  ),
];

/// Legend for Home / Tasks: explains PIC team background colours on [TaskListCard].
class PicTeamColorLegend extends StatelessWidget {
  const PicTeamColorLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Task background colour reflects the PIC’s team.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final e in kPicTeamColorEntries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: e.color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.35),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    e.legendLabel,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Task row for list tabs: name, assignees, status, start/due dates (matches singular + legacy tasks).
class TaskListCard extends StatelessWidget {
  const TaskListCard({super.key, required this.task});

  final Task task;

  /// Background tint from PIC's [`staff.team_id`] / [`team.team_id`] (home / initiative task lists).
  static Color? cardColorForPicTeam(String? teamBusinessId) {
    final t = teamBusinessId?.trim().toLowerCase();
    if (t == null || t.isEmpty) return null;
    for (final e in kPicTeamColorEntries) {
      if (e.teamKey == t) return e.color;
    }
    return null;
  }

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
    final picKey = t.pic?.trim();
    final nameLookupKeys = <String>{
      ...t.assigneeIds,
      if (picKey != null && picKey.isNotEmpty) picKey,
    }.toList();
    return FutureBuilder<(Map<String, String>, String?)>(
      future: () async {
        final names = await SupabaseService.staffDisplayNamesForKeys(nameLookupKeys);
        final picTeam =
            await SupabaseService.fetchStaffTeamBusinessIdForAssigneeKey(picKey);
        return (names, picTeam);
      }(),
      builder: (context, snapshot) {
        final nameMap = snapshot.data?.$1 ?? {};
        final picTeamId = snapshot.data?.$2;
        final officerNames = t.assigneeIds
            .map((id) => nameMap[id] ?? state.assigneeById(id)?.name ?? id)
            .toList()
          ..sort();
        final showPicLine = t.assigneeIds.length > 1 &&
            picKey != null &&
            picKey.isNotEmpty;
        final pk = picKey;
        final cardTint = cardColorForPicTeam(picTeamId);
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: cardTint,
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
                if (showPicLine && pk != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'PIC: ${nameMap[pk] ?? state.assigneeById(pk)?.name ?? pk}',
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
