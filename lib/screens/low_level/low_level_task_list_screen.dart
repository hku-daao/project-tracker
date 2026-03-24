import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
import '../../models/task.dart';
import '../../models/team.dart';
import '../../widgets/task_list_card.dart';

/// Low-level view: list tasks (Planner-style), filter by team.
class LowLevelTaskListScreen extends StatefulWidget {
  const LowLevelTaskListScreen({super.key});

  @override
  State<LowLevelTaskListScreen> createState() => _LowLevelTaskListScreenState();
}

class _LowLevelTaskListScreenState extends State<LowLevelTaskListScreen> {
  String? _selectedTeamId;
  bool _remindersExpanded = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = state.tasksForTeam(_selectedTeamId);
    final incomplete = tasks.where((t) => t.status != TaskStatus.done).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final completed = tasks.where((t) => t.status == TaskStatus.done).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final deletedRecords = state.deletedTasksForTeam(_selectedTeamId);
    final reminders = state.getPendingReminders(_selectedTeamId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reminders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ExpansionTile(
              title: const Text('Reminders (would send to Directors)'),
              initiallyExpanded: _remindersExpanded,
              onExpansionChanged: (v) => setState(() => _remindersExpanded = v),
              children: reminders.map((r) => ListTile(
                title: Text(r.itemName),
                subtitle: Text(
                  '${r.reminderType} → ${r.recipientNames.join(", ")}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )).toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DropdownButtonFormField<String?>(
            value: _selectedTeamId,
            decoration: const InputDecoration(
              labelText: 'Filter by team',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All tasks'),
              ),
              ...context.watch<AppState>().teams.map(
                (Team team) => DropdownMenuItem<String?>(
                  value: team.id,
                  child: Text(team.name),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _selectedTeamId = v),
          ),
        ),
        Expanded(
          child: tasks.isEmpty && deletedRecords.isEmpty
              ? Center(
                  child: Text(
                    _selectedTeamId == null
                        ? 'No tasks yet. Create one in the "Create Task" tab.'
                        : 'No tasks for this team.',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (incomplete.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Text(
                          'Incomplete tasks',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      ...incomplete.map((t) => TaskListCard(task: t)),
                    ],
                    if (completed.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Text(
                          'Completed tasks',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      ...completed.map((t) => TaskListCard(task: t)),
                    ],
                    if (deletedRecords.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 24, bottom: 8),
                        child: Text(
                          'Deleted tasks (audit)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                        ),
                      ),
                      ...deletedRecords.map((r) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.grey.shade100,
                            child: ListTile(
                              title: Text(
                                r.taskName,
                                style: TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: Colors.grey.shade700),
                              ),
                              subtitle: Text(
                                'Deleted by ${r.deletedByName} · ${DateFormat.yMMMd().add_Hm().format(r.deletedAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          )),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

}
