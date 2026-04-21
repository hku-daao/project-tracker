import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/singular_subtask.dart';
import '../models/task.dart';
import '../priority.dart';
import '../screens/high_level/subtask_detail_screen.dart';
import '../screens/task_detail_screen.dart';
import '../services/supabase_service.dart';
import '../utils/hk_time.dart';
import 'singular_subtask_row_card.dart';
import 'subtask_meta_line.dart';

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
    color: Color(0xFFFFFBE8),
    legendLabel: 'Advancement Intelligence',
  ),
  PicTeamColorEntry(
    teamKey: 'president_office',
    color: Color(0xFFFEE8FF),
    legendLabel: 'President Office',
  ),
  PicTeamColorEntry(
    teamKey: 'fundraising',
    color: Color(0xFFE8FDFF),
    legendLabel: 'Fundraising',
  ),
  PicTeamColorEntry(
    teamKey: 'alumni',
    color: Color(0xFFEEFFD4),
    legendLabel: 'Alumni',
  ),
  PicTeamColorEntry(
    teamKey: 'admin_team',
    color: Color(0xFFFFE9E3),
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
          style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
            fontSize: kLandingListCardFontSize,
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
                    style: (theme.textTheme.bodyMedium ?? const TextStyle())
                        .copyWith(fontSize: kLandingListCardFontSize),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

enum _SubtaskListCardSortColumn {
  assignee,
  pic,
  startDate,
  dueDate,
  status,
  submission,
}

String _subtaskSortColumnLabel(_SubtaskListCardSortColumn c) {
  switch (c) {
    case _SubtaskListCardSortColumn.assignee:
      return 'Assignee';
    case _SubtaskListCardSortColumn.pic:
      return 'PIC';
    case _SubtaskListCardSortColumn.startDate:
      return 'Start date';
    case _SubtaskListCardSortColumn.dueDate:
      return 'Due date';
    case _SubtaskListCardSortColumn.status:
      return 'Status';
    case _SubtaskListCardSortColumn.submission:
      return 'Submission';
  }
}

typedef _TaskListCardData = (
  Map<String, String> names,
  String? picTeam,
  List<SingularSubtask> subtasks,
);

/// Task row for list tabs: name, assignees, status, start/due dates (matches singular + legacy tasks).
class TaskListCard extends StatefulWidget {
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

  static bool _isTaskDisplayCompleted(Task t) {
    if (t.isSingularTableRow) {
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      return s == 'completed' || s == 'complete';
    }
    return t.status == TaskStatus.done;
  }

  /// Same green as the **Accepted** submission chip (`#298A00`).
  static const Color kCompletedOnMetaColor = kSubtaskCompletedOnMetaColor;

  /// Priority · status · Start · Due · Completed on … (single line).
  static Widget buildTaskMetaLine(BuildContext context, Task t) {
    final theme = Theme.of(context);
    final baseStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(fontSize: kLandingListCardFontSize);
    final prefix =
        '${priorityToDisplayName(t.priority)} · ${statusLabel(t)}'
        '${t.startDate != null ? ' · Start ${DateFormat.yMMMd().format(t.startDate!)}' : ''}';
    final due = t.endDate;
    final duePart =
        due != null ? ' · Due ${DateFormat.yMMMd().format(due)}' : '';
    final comp = t.completionDate;
    final showCompleted = _isTaskDisplayCompleted(t) && comp != null;
    if (!showCompleted) {
      return Text(
        '$prefix$duePart',
        style: baseStyle,
      );
    }
    final completedSeg =
        ' · Completed on ${HkTime.formatInstantAsHk(comp, 'MMM dd, y')}';
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: '$prefix$duePart'),
          TextSpan(
            text: completedSeg,
            style: baseStyle.copyWith(
              color: kCompletedOnMetaColor,
              fontWeight: FontWeight.w600,
              fontSize: kLandingListCardFontSize,
            ),
          ),
        ],
      ),
    );
  }

  static bool _isSubmissionSubmitted(Task t) {
    final s = t.submission?.trim().toLowerCase() ?? '';
    return s == 'submitted';
  }

  static bool _isSubmissionAccepted(Task t) {
    final s = t.submission?.trim().toLowerCase() ?? '';
    return s == 'accepted';
  }

  static bool _isSubmissionReturned(Task t) {
    final s = t.submission?.trim().toLowerCase() ?? '';
    return s == 'returned';
  }

  static const Color _kAcceptedTagColor = kCompletedOnMetaColor;
  static const Color _kReturnedTagColor = Color(0xFF0B0094);

  /// Submission chips on list cards and sub-task rows ([_submissionBadge], [buildSubmissionTag]).
  static const double kSubmissionChipFontSize = 11;

  /// “Over preset timeline” pill on list cards ([buildOverPresetTimelineTag]).
  static const double kOverPresetPillFontSize = 11;

  static Widget _submissionBadge(String label, Color backgroundColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: kSubmissionChipFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Same colours as the submission chips on the home task list ([_submissionBadge]).
  /// Returns `null` if [submission] is empty.
  static Widget? buildSubmissionTag(String? submission) {
    final raw = submission?.trim() ?? '';
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower == 'submitted') {
      return _submissionBadge('Submitted', Colors.red);
    }
    if (lower == 'accepted') {
      return _submissionBadge('Accepted', _kAcceptedTagColor);
    }
    if (lower == 'returned') {
      return _submissionBadge('Returned', _kReturnedTagColor);
    }
    if (lower == 'pending') {
      return _submissionBadge('Pending', Colors.grey.shade700);
    }
    return _submissionBadge(raw, Colors.grey.shade600);
  }

  static const Color _kOverPresetTimelineColor = Color(0xFFFFCD05);

  /// Tag when extend-timeline reason exists (list cards; no raw reason text).
  static Widget buildOverPresetTimelineTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kOverPresetTimelineColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Over preset timeline',
        style: TextStyle(
          color: const Color(0xFF1A1A1A),
          fontSize: kOverPresetPillFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  State<TaskListCard> createState() => _TaskListCardState();
}

class _TaskListCardState extends State<TaskListCard> {
  late Future<_TaskListCardData> _cardDataFuture;
  bool _subtasksExpanded = false;

  /// `null` = default order: [SingularSubtask.createDate] descending (newest first).
  _SubtaskListCardSortColumn? _activeSubtaskSort;
  bool _subtaskSortAscending = true;

  @override
  void initState() {
    super.initState();
    _cardDataFuture = _loadCardData();
  }

  @override
  void didUpdateWidget(covariant TaskListCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _cardDataFuture = _loadCardData();
      _subtasksExpanded = false;
    }
  }

  Future<_TaskListCardData> _loadCardData() async {
    final t = widget.task;
    final picKey = t.pic?.trim();
    final subtasks = t.isSingularTableRow
        ? await SupabaseService.fetchSubtasksForTask(t.id)
        : <SingularSubtask>[];
    final keys = <String>{
      ...t.assigneeIds,
      if (picKey != null && picKey.isNotEmpty) picKey,
    };
    for (final st in subtasks) {
      keys.addAll(st.assigneeIds);
      final p = st.pic?.trim();
      if (p != null && p.isNotEmpty) keys.add(p);
    }
    final names = await SupabaseService.staffDisplayNamesForKeys(keys.toList());
    final picTeam =
        await SupabaseService.fetchStaffTeamBusinessIdForAssigneeKey(picKey);
    return (names, picTeam, subtasks);
  }

  /// Latest calendar due among all sub-tasks (any count); `null` if none have a due date.
  DateTime? _maxSubtaskDue(List<SingularSubtask> subtasks) {
    DateTime? maxD;
    for (final st in subtasks) {
      final d = st.dueDate;
      if (d == null) continue;
      if (maxD == null || d.isAfter(maxD)) maxD = d;
    }
    return maxD;
  }

  static String _subtaskAssigneeSortKey(
    SingularSubtask s,
    String Function(String id) res,
  ) {
    final names = s.assigneeIds.map((id) => res(id)).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.join(', ');
  }

  static String _subtaskPicSortKey(
    SingularSubtask s,
    String Function(String id) res,
  ) {
    final p = s.pic?.trim();
    if (p == null || p.isEmpty) return '';
    return res(p);
  }

  static int _cmpStrForSort(String a, String b, bool ascending) {
    final sa = a.trim().toLowerCase();
    final sb = b.trim().toLowerCase();
    if (sa.isEmpty && sb.isEmpty) return 0;
    if (sa.isEmpty) return 1;
    if (sb.isEmpty) return -1;
    final c = sa.compareTo(sb);
    return ascending ? c : -c;
  }

  static int _cmpDateNullable(
    DateTime? a,
    DateTime? b,
    bool ascending, {
    bool dateOnly = false,
  }) {
    DateTime? na = a;
    DateTime? nb = b;
    if (dateOnly && a != null) {
      na = DateTime(a.year, a.month, a.day);
    }
    if (dateOnly && b != null) {
      nb = DateTime(b.year, b.month, b.day);
    }
    if (na == null && nb == null) return 0;
    if (na == null) return 1;
    if (nb == null) return -1;
    final c = na.compareTo(nb);
    return ascending ? c : -c;
  }

  List<SingularSubtask> _sortedSubtasks(
    List<SingularSubtask> raw,
    String Function(String id) resolveName,
  ) {
    final out = List<SingularSubtask>.from(raw);
    int tieBreak(SingularSubtask a, SingularSubtask b) {
      final ad = a.createDate;
      final bd = b.createDate;
      if (ad == null && bd == null) {
        return a.subtaskName.toLowerCase().compareTo(b.subtaskName.toLowerCase());
      }
      if (ad == null) return 1;
      if (bd == null) return -1;
      final c = bd.compareTo(ad);
      if (c != 0) return c;
      return a.subtaskName.toLowerCase().compareTo(b.subtaskName.toLowerCase());
    }

    if (_activeSubtaskSort == null) {
      out.sort((a, b) => tieBreak(a, b));
      return out;
    }

    final col = _activeSubtaskSort!;
    final asc = _subtaskSortAscending;
    out.sort((a, b) {
      int c;
      switch (col) {
        case _SubtaskListCardSortColumn.assignee:
          c = _cmpStrForSort(
            _subtaskAssigneeSortKey(a, resolveName),
            _subtaskAssigneeSortKey(b, resolveName),
            asc,
          );
          break;
        case _SubtaskListCardSortColumn.pic:
          c = _cmpStrForSort(
            _subtaskPicSortKey(a, resolveName),
            _subtaskPicSortKey(b, resolveName),
            asc,
          );
          break;
        case _SubtaskListCardSortColumn.startDate:
          c = _cmpDateNullable(a.startDate, b.startDate, asc, dateOnly: true);
          break;
        case _SubtaskListCardSortColumn.dueDate:
          c = _cmpDateNullable(a.dueDate, b.dueDate, asc, dateOnly: true);
          break;
        case _SubtaskListCardSortColumn.status:
          c = _cmpStrForSort(a.status, b.status, asc);
          break;
        case _SubtaskListCardSortColumn.submission:
          c = _cmpStrForSort(
            a.submission ?? '',
            b.submission ?? '',
            asc,
          );
          break;
      }
      if (c != 0) return c;
      return tieBreak(a, b);
    });
    return out;
  }

  Widget _buildSubtaskSortColumnControl(_SubtaskListCardSortColumn column) {
    final active = _activeSubtaskSort == column;
    final theme = Theme.of(context);
    final chipLabelStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
      fontSize: kLandingListCardFontSize,
      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'Sort by ${_subtaskSortColumnLabel(column)}',
        onSelected: (v) {
          setState(() {
            if (v == 'clear') {
              if (_activeSubtaskSort == column) {
                _activeSubtaskSort = null;
                _subtaskSortAscending = true;
              }
            } else if (v == 'asc') {
              _activeSubtaskSort = column;
              _subtaskSortAscending = true;
            } else if (v == 'desc') {
              _activeSubtaskSort = column;
              _subtaskSortAscending = false;
            }
          });
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'asc', child: Text('Ascending')),
          const PopupMenuItem(value: 'desc', child: Text('Descending')),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'clear',
            enabled: active,
            child: const Text('Clear sort'),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _subtaskSortColumnLabel(column),
                maxLines: 1,
                softWrap: false,
                style: chipLabelStyle,
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  _subtaskSortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reloadAfterSubtaskReturn() async {
    setState(() {
      _cardDataFuture = _loadCardData();
    });
    await _cardDataFuture;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final t = widget.task;
    final picKey = t.pic?.trim();
    return FutureBuilder<_TaskListCardData>(
      future: _cardDataFuture,
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final listText = (theme.textTheme.bodyMedium ?? const TextStyle())
            .copyWith(fontSize: kLandingListCardFontSize);
        final taskTitleStyle =
            listText.copyWith(fontWeight: FontWeight.bold);
        final listTextW500 =
            listText.copyWith(fontWeight: FontWeight.w500);
        final listTextVariant = listText.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        final subtasksHeaderStyle =
            listText.copyWith(fontWeight: FontWeight.w600);
        final nameMap = snapshot.data?.$1 ?? {};
        final picTeamId = snapshot.data?.$2;
        final subtasks = snapshot.data?.$3 ?? <SingularSubtask>[];
        final officerNames = t.assigneeIds
            .map((id) => nameMap[id] ?? state.assigneeById(id)?.name ?? id)
            .toList()
          ..sort();
        final showPicLine = t.assigneeIds.length > 1 &&
            picKey != null &&
            picKey.isNotEmpty;
        final pk = picKey;
        final cardTint = TaskListCard.cardColorForPicTeam(picTeamId);
        final maxSubDue = _maxSubtaskDue(subtasks);
        String resolveName(String id) =>
            nameMap[id] ?? state.assigneeById(id)?.name ?? id;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: cardTint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TaskDetailScreen(taskId: t.id),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    t.name,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: taskTitleStyle,
                                  ),
                                ),
                                if (TaskListCard._isSubmissionSubmitted(t)) ...[
                                  const SizedBox(width: 8),
                                  TaskListCard._submissionBadge(
                                    'Submitted',
                                    Colors.red,
                                  ),
                                ],
                                if (TaskListCard._isSubmissionAccepted(t)) ...[
                                  const SizedBox(width: 8),
                                  TaskListCard._submissionBadge(
                                    'Accepted',
                                    TaskListCard._kAcceptedTagColor,
                                  ),
                                ],
                                if (TaskListCard._isSubmissionReturned(t)) ...[
                                  const SizedBox(width: 8),
                                  TaskListCard._submissionBadge(
                                    'Returned',
                                    TaskListCard._kReturnedTagColor,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (officerNames.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'Assignee(s): ${officerNames.join(', ')}',
                                  style: listTextW500,
                                ),
                              ),
                            if (showPicLine && pk != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'PIC: ${nameMap[pk] ?? state.assigneeById(pk)?.name ?? pk}',
                                  style: listTextW500,
                                ),
                              ),
                            if (t.createByStaffName != null &&
                                t.createByStaffName!.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'Creator: ${t.createByStaffName!.trim()}',
                                  style: listTextVariant,
                                ),
                              ),
                            TaskListCard.buildTaskMetaLine(context, t),
                            if (subtasks.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                maxSubDue != null
                                    ? 'Maximum sub-task due date: ${DateFormat('yyyy-MM-dd').format(maxSubDue)}'
                                    : 'Maximum sub-task due date: —',
                                style: listTextVariant,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 4, top: 4),
                        child: Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ),
              if (subtasks.isNotEmpty) ...[
                const Divider(height: 1),
                InkWell(
                  onTap: () => setState(() {
                    _subtasksExpanded = !_subtasksExpanded;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _subtasksExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 22,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sub-tasks (${subtasks.length})',
                            style: subtasksHeaderStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_subtasksExpanded) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                'Sort',
                                style: subtasksHeaderStyle,
                              ),
                            ),
                            for (final col in _SubtaskListCardSortColumn.values)
                              _buildSubtaskSortColumnControl(col),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final s in _sortedSubtasks(subtasks, resolveName))
                          SingularSubtaskRowCard(
                            subtask: s,
                            resolveName: resolveName,
                            onTap: () async {
                              final changed =
                                  await Navigator.of(context).push<bool>(
                                MaterialPageRoute<bool>(
                                  builder: (_) => SubtaskDetailScreen(
                                    subtaskId: s.id,
                                    replaceWithParentTaskOnBack: true,
                                  ),
                                ),
                              );
                              if (changed == true && mounted) {
                                await _reloadAfterSubtaskReturn();
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}
