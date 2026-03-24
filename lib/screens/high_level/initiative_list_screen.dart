import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
import '../../models/initiative.dart';
import '../../models/task.dart';
import '../../models/team.dart';
import '../../models/assignee.dart';
import '../../priority.dart';
import '../../widgets/task_list_card.dart';
import 'initiative_detail_screen.dart';

class InitiativeListScreen extends StatefulWidget {
  const InitiativeListScreen({super.key});

  @override
  State<InitiativeListScreen> createState() => _InitiativeListScreenState();
}

class _InitiativeListScreenState extends State<InitiativeListScreen> {
  String? _selectedTeamId;
  String? _selectedAssigneeId;
  String _filterType = 'all'; // 'all', 'incomplete', 'completed', 'deleted'
  bool _remindersExpanded = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    var initiatives = state.initiativesForTeam(_selectedTeamId);
    var tasks = state.tasksForTeam(_selectedTeamId);

    if (_selectedAssigneeId != null) {
      initiatives = initiatives
          .where((i) => i.directorIds.contains(_selectedAssigneeId!))
          .toList();
      tasks = tasks
          .where((t) => t.assigneeIds.contains(_selectedAssigneeId!))
          .toList();
    }

    bool singularDeleted(Task t) {
      if (!t.isSingularTableRow) return false;
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      return s == 'delete' || s == 'deleted';
    }

    bool singularCompleted(Task t) {
      if (!t.isSingularTableRow) return false;
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      return s == 'completed' || s == 'complete';
    }

    bool singularIncomplete(Task t) {
      if (!t.isSingularTableRow) return false;
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      if (s.isEmpty) return true;
      return s == 'incomplete';
    }

    final tasksNonDeleted = tasks.where((t) => !singularDeleted(t)).toList();
    final tasksDeletedSingular = tasks.where(singularDeleted).toList();
    
    // Apply status filter
    List<Initiative> filteredInitiatives = [];
    List<Task> filteredTasks = [];
    List<Task> filteredDeletedTasks = [];
    
    if (_filterType == 'all') {
      filteredInitiatives = initiatives;
      filteredTasks = tasksNonDeleted;
      filteredDeletedTasks = [];
    } else if (_filterType == 'incomplete') {
      filteredInitiatives = initiatives.where((i) => state.initiativeProgressPercent(i.id) < 100).toList();
      filteredTasks = tasksNonDeleted.where((t) {
        if (t.isSingularTableRow) return singularIncomplete(t);
        return t.status != TaskStatus.done;
      }).toList();
      filteredDeletedTasks = [];
    } else if (_filterType == 'completed') {
      filteredInitiatives = initiatives.where((i) => state.initiativeProgressPercent(i.id) >= 100).toList();
      filteredTasks = tasksNonDeleted.where((t) {
        if (t.isSingularTableRow) return singularCompleted(t);
        return t.status == TaskStatus.done;
      }).toList();
      filteredDeletedTasks = [];
    } else if (_filterType == 'deleted') {
      filteredInitiatives = [];
      filteredTasks = [];
      filteredDeletedTasks = tasksDeletedSingular;
    }
    
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
                  child: Text('All teams'),
                ),
                ...state.teams.map(
                  (Team team) => DropdownMenuItem<String?>(
                    value: team.id,
                    child: Text(team.name),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() {
                  _selectedTeamId = v;
                  _selectedAssigneeId = null; // Reset assignee when team changes
                });
              },
            ),
          ),
          if (_selectedTeamId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: DropdownButtonFormField<String?>(
                value: _selectedAssigneeId,
                decoration: const InputDecoration(
                  labelText: 'Filter by team member (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All team members'),
                  ),
                  ..._getTeamMembers(state, _selectedTeamId!).map(
                    (Assignee assignee) => DropdownMenuItem<String?>(
                      value: assignee.id,
                      child: Text(assignee.name),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedAssigneeId = v),
              ),
            ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'incomplete', label: Text('Incomplete')),
              ButtonSegment(value: 'completed', label: Text('Completed')),
              ButtonSegment(value: 'deleted', label: Text('Deleted')),
            ],
            selected: {_filterType},
            onSelectionChanged: (Set<String> selected) {
              setState(() => _filterType = selected.first);
            },
          ),
        ),
        Expanded(
          child: filteredInitiatives.isEmpty && filteredTasks.isEmpty && filteredDeletedTasks.isEmpty
              ? Center(
                  child: Text(
                    _selectedTeamId == null
                        ? 'No tasks yet. Create one in the "Create task" tab.'
                        : 'No tasks for this filter.',
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        if (filteredInitiatives.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Text(
                              'Initiatives',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          ...filteredInitiatives.map((init) => _buildInitiativeCard(context, state, init)),
                        ],
                        if (filteredTasks.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 8),
                            child: Text(
                              'Tasks',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          ...filteredTasks.map((t) => TaskListCard(task: t)),
                        ],
                        if (filteredDeletedTasks.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 24, bottom: 8),
                            child: Text(
                              'Deleted tasks',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                            ),
                          ),
                          ...filteredDeletedTasks.map((t) => TaskListCard(task: t)),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  List<Assignee> _getTeamMembers(AppState state, String teamId) {
    try {
      final team = state.teams.firstWhere((t) => t.id == teamId);
      final allMemberIds = [...team.directorIds, ...team.officerIds];
      return allMemberIds
          .map((id) => state.assigneeById(id))
          .whereType<Assignee>()
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return [];
    }
  }

  static Color _progressColor(int percent) {
    if (percent >= 100) return Colors.green;
    if (percent >= 50) return Color.lerp(Colors.yellow, Colors.green, (percent - 50) / 50)!;
    return Color.lerp(Colors.red, Colors.yellow, percent / 50)!;
  }

  Widget _buildInitiativeCard(BuildContext context, AppState state, Initiative init) {
    final progress = state.initiativeProgressPercent(init.id);
    final progressColor = _progressColor(progress);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(init.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${priorityToDisplayName(init.priority)} · $progress%'
              + (init.startDate != null
                  ? ' · Start ${DateFormat.yMMMd().format(init.startDate!)}'
                  : '')
              + (init.endDate != null
                  ? ' · Due ${DateFormat.yMMMd().format(init.endDate!)}'
                  : ''),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              backgroundColor: progressColor.withValues(alpha: 0.3),
            ),
            if (init.directorIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: init.directorIds.map((id) {
                  final a = state.assigneeById(id);
                  final isDirector = state.isDirector(id);
                  return Chip(
                    label: Text(
                      a?.name ?? id,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: isDirector
                        ? Colors.lightBlue.shade100
                        : Colors.purple.shade100,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InitiativeDetailScreen(initiativeId: init.id),
          ),
        ),
      ),
    );
  }

}
