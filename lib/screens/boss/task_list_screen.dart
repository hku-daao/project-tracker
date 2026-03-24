import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../widgets/task_list_card.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  String? _selectedTeamId; // null = All

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = state.tasksForTeam(_selectedTeamId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                (team) => DropdownMenuItem<String?>(
                  value: team.id,
                  child: Text(team.name),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _selectedTeamId = v),
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Text(
                    _selectedTeamId == null
                        ? 'No tasks yet. Create one in the "Create Task" tab.'
                        : 'No tasks for this team.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: tasks.length,
                  itemBuilder: (context, i) {
                    return TaskListCard(task: tasks[i]);
                  },
                ),
        ),
      ],
    );
  }
}
