import 'package:flutter/cupertino.dart';
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
  String _filterType = 'all'; // 'all','assigned','created','incomplete','completed','deleted'
  bool _remindersExpanded = false;

  /// On my plate as assignee — dark blue chip when selected.
  Widget _assignedToMeFilterIcon(bool selected) {
    return Icon(
      Icons.assignment_ind,
      size: 18,
      color: selected ? Colors.white : const Color(0xFF0D47A1),
    );
  }

  /// Tasks I created — task icon on "My created tasks".
  Widget _myCreatedTasksFilterIcon(bool selected) {
    return Icon(
      Icons.task_alt,
      size: 18,
      color: selected ? Colors.black87 : Colors.lightBlue.shade800,
    );
  }

  /// Half-filled circle (yellow) — contrast on amber when this filter is selected.
  Widget _incompleteFilterIcon(bool selected) {
    return Icon(
      CupertinoIcons.circle_lefthalf_fill,
      size: 18,
      color: selected ? Colors.amber.shade900 : Colors.amber.shade800,
    );
  }

  /// Filled circle — white on dark green when selected.
  Widget _completedFilterIcon(bool selected) {
    return Icon(
      Icons.circle,
      size: 18,
      color: selected ? Colors.white : const Color(0xFF1B5E20),
    );
  }

  /// Trash — white on grey when selected.
  Widget _deletedFilterIcon(bool selected) {
    return Icon(
      Icons.delete_outline,
      size: 18,
      color: selected ? Colors.white : Colors.grey.shade700,
    );
  }

  /// Scrollable chips so labels stay on one line on narrow / mobile screens.
  Widget _buildTaskFilterChip({
    required String value,
    required String label,
    required bool selected,
    Color? selectedBg,
    Color? selectedLabelColor,
    Widget? leading,
  }) {
    final theme = Theme.of(context);
    final Color onLabel;
    if (!selected) {
      onLabel = theme.colorScheme.onSurface;
    } else if (selectedLabelColor != null) {
      onLabel = selectedLabelColor!;
    } else if (selectedBg == null) {
      onLabel = theme.colorScheme.onPrimary;
    } else {
      onLabel = theme.colorScheme.onSecondaryContainer;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        showCheckmark: false,
        avatar: leading,
        label: Text(
          label,
          maxLines: 1,
          softWrap: false,
        ),
        selected: selected,
        onSelected: (_) => setState(() => _filterType = value),
        selectedColor: selectedBg,
        labelStyle: TextStyle(
          color: onLabel,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_filterType == 'my') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _filterType = 'all');
      });
    }
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
    final mine = state.userStaffAppId?.trim();
    bool hasMine() => mine != null && mine.isNotEmpty;
    bool isAssignedToMe(Task t) =>
        hasMine() && t.assigneeIds.contains(mine!);
    bool isCreatedByMe(Task t) =>
        hasMine() && t.createByAssigneeKey == mine;

    final filterKey = _filterType == 'my' ? 'all' : _filterType;

    // Apply status filter
    List<Initiative> filteredInitiatives = [];
    List<Task> filteredTasks = [];
    List<Task> filteredDeletedTasks = [];
    
    if (filterKey == 'all') {
      filteredInitiatives = initiatives;
      filteredTasks = tasksNonDeleted;
      filteredDeletedTasks = [];
    } else if (filterKey == 'assigned') {
      filteredInitiatives = [];
      filteredTasks =
          tasksNonDeleted.where((t) => isAssignedToMe(t)).toList();
      filteredDeletedTasks = [];
    } else if (filterKey == 'created') {
      filteredInitiatives = [];
      filteredTasks = tasksNonDeleted.where((t) => isCreatedByMe(t)).toList();
      filteredDeletedTasks = [];
    } else if (filterKey == 'incomplete') {
      filteredInitiatives = initiatives.where((i) => state.initiativeProgressPercent(i.id) < 100).toList();
      filteredTasks = tasksNonDeleted.where((t) {
        if (t.isSingularTableRow) return singularIncomplete(t);
        return t.status != TaskStatus.done;
      }).toList();
      filteredDeletedTasks = [];
    } else if (filterKey == 'completed') {
      filteredInitiatives = initiatives.where((i) => state.initiativeProgressPercent(i.id) >= 100).toList();
      filteredTasks = tasksNonDeleted.where((t) {
        if (t.isSingularTableRow) return singularCompleted(t);
        return t.status == TaskStatus.done;
      }).toList();
      filteredDeletedTasks = [];
    } else if (filterKey == 'deleted') {
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
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildTaskFilterChip(
                  value: 'all',
                  label: 'All',
                  selected: filterKey == 'all',
                  selectedBg: null,
                  selectedLabelColor: null,
                  leading: null,
                ),
                _buildTaskFilterChip(
                  value: 'assigned',
                  label: 'Assigned to me',
                  selected: filterKey == 'assigned',
                  selectedBg: const Color(0xFF0D47A1),
                  selectedLabelColor: Colors.white,
                  leading: _assignedToMeFilterIcon(filterKey == 'assigned'),
                ),
                _buildTaskFilterChip(
                  value: 'created',
                  label: 'My created tasks',
                  selected: filterKey == 'created',
                  selectedBg: Colors.lightBlue.shade200,
                  selectedLabelColor: Colors.black87,
                  leading: _myCreatedTasksFilterIcon(filterKey == 'created'),
                ),
                _buildTaskFilterChip(
                  value: 'incomplete',
                  label: 'Incomplete',
                  selected: filterKey == 'incomplete',
                  selectedBg: Colors.amber.shade300,
                  selectedLabelColor: Colors.black87,
                  leading: _incompleteFilterIcon(filterKey == 'incomplete'),
                ),
                _buildTaskFilterChip(
                  value: 'completed',
                  label: 'Completed',
                  selected: filterKey == 'completed',
                  selectedBg: const Color(0xFF1B5E20),
                  selectedLabelColor: Colors.white,
                  leading: _completedFilterIcon(filterKey == 'completed'),
                ),
                _buildTaskFilterChip(
                  value: 'deleted',
                  label: 'Deleted',
                  selected: filterKey == 'deleted',
                  selectedBg: Colors.grey.shade500,
                  selectedLabelColor: Colors.white,
                  leading: _deletedFilterIcon(filterKey == 'deleted'),
                ),
              ],
            ),
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
