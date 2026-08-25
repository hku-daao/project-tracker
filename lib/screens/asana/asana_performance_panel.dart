import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/project_record.dart';
import '../../models/singular_subtask.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/task.dart';
import '../../services/database_service.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';
import 'asana_theme.dart';
import '../asana_landing_screen.dart';

enum AsanaPerformanceViewMode { group, individual }

class AsanaPerformancePanel extends StatefulWidget {
  const AsanaPerformancePanel({
    super.key,
    required this.palette,
    required this.viewMode,
  });

  final AsanaLandingPalette palette;
  final AsanaPerformanceViewMode viewMode;

  @override
  State<AsanaPerformancePanel> createState() => _AsanaPerformancePanelState();
}

class _AsanaPerformancePanelState extends State<AsanaPerformancePanel> {
  bool _loading = true;
  String? _error;
  String _loadedTaskSignature = '';
  Map<String, String> _officeIdByStaffKey = {};
  Map<String, String> _officeNameById = {};
  Map<String, String> _teamIdByStaffKey = {};
  Map<String, String> _canonicalStaffKeyByLookup = {};
  Map<String, List<SingularSubtask>> _subtasksByTaskId = {};
  String? _individualStaffUuid;
  String? _individualAppId;
  String? _individualName;
  String? _periodStartMonth;
  String? _periodEndMonth;

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
      final individual = await DatabaseService.fetchStaffIdentityByEmail(
        'kenkylee@hku.hk',
      );
      final subtasks =
          await DatabaseService.fetchSubtasksGroupedIncludingDeleted(taskIds);
      if (!mounted) return;
      setState(() {
        _officeIdByStaffKey = _officeMapByStaffKey(picker.staff);
        _teamIdByStaffKey = _teamMapByStaffKey(picker.staff);
        _canonicalStaffKeyByLookup = _canonicalMapByStaffKey(picker.staff);
        _officeNameById = {
          for (final office in picker.offices)
            office.officeId.trim().toLowerCase(): office.officeName.trim(),
        };
        _subtasksByTaskId = subtasks;
        _individualStaffUuid = individual.staffUuid;
        _individualAppId = individual.appId;
        _individualName = individual.name;
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

  Map<String, String> _teamMapByStaffKey(List<StaffForAssignment> staff) {
    final map = <String, String>{};
    for (final s in staff) {
      final teamId = s.teamId?.trim();
      if (teamId == null || teamId.isEmpty) continue;
      final appId = s.assigneeId.trim();
      if (appId.isNotEmpty) map[appId.toLowerCase()] = teamId;
      final uuid = s.staffUuid?.trim();
      if (uuid != null && uuid.isNotEmpty) map[uuid.toLowerCase()] = teamId;
    }
    return map;
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

  Map<String, String> _canonicalMapByStaffKey(List<StaffForAssignment> staff) {
    final map = <String, String>{};
    for (final s in staff) {
      final canonical =
          (s.staffUuid?.trim().isNotEmpty == true
                  ? s.staffUuid!.trim()
                  : s.assigneeId.trim())
              .toLowerCase();
      if (canonical.isEmpty) continue;
      final appId = s.assigneeId.trim().toLowerCase();
      if (appId.isNotEmpty) map[appId] = canonical;
      final uuid = s.staffUuid?.trim().toLowerCase();
      if (uuid != null && uuid.isNotEmpty) map[uuid] = canonical;
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
    final activeStaff = <String>{};
    void addActive(String? key) {
      final k = key?.trim();
      if (k == null || k.isEmpty) return;
      if (_belongsToOffice([k], officeLabel)) {
        final lower = k.toLowerCase();
        activeStaff.add(_canonicalStaffKeyByLookup[lower] ?? lower);
      }
    }

    for (final t in tasks) {
      addActive(t.pic);
      for (final id in t.assigneeIds) {
        addActive(id);
      }
    }
    for (final s in subtasks) {
      addActive(s.pic);
      for (final id in s.assigneeIds) {
        addActive(id);
      }
    }

    return _PerformanceMetrics(
      projects: projects.length,
      tasks: tasks.length,
      subtasks: subtasks.length,
      completedTasks: tasks.where(_taskCompleted).length,
      completedSubtasks: subtasks.where(_subtaskCompleted).length,
      pausedTasks: tasks.where((t) => t.isPaused).length,
      pausedSubtasks: subtasks.where((s) => s.isPaused).length,
      activeStaff: activeStaff.length,
    );
  }

  bool _keyMatchesIndividual(String? value) {
    final v = value?.trim().toLowerCase();
    if (v == null || v.isEmpty) return false;
    final appId = _individualAppId?.trim().toLowerCase();
    final uuid = _individualStaffUuid?.trim().toLowerCase();
    return (appId != null && appId.isNotEmpty && v == appId) ||
        (uuid != null && uuid.isNotEmpty && v == uuid);
  }

  bool _anyKeyMatchesIndividual(Iterable<String> values) {
    return values.any(_keyMatchesIndividual);
  }

  String? _individualTeamId() {
    for (final key in [_individualStaffUuid, _individualAppId]) {
      final normalized = key?.trim().toLowerCase();
      if (normalized == null || normalized.isEmpty) continue;
      final teamId = _teamIdByStaffKey[normalized];
      if (teamId != null && teamId.isNotEmpty) return teamId;
    }
    return null;
  }

  String _monthKey(DateTime? value) {
    if (value == null) return 'No date';
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  String _complexityKey(String? value) {
    final s = value?.trim().toLowerCase();
    return switch (s) {
      'low' => 'Low',
      'medium' => 'Medium',
      'high' => 'High',
      _ => 'Medium',
    };
  }

  _IndividualPerformance _individualPerformance(AppState state) {
    final byMonth = <String, _MonthlyIndividualPerformance>{};

    _MonthlyIndividualPerformance month(String key) {
      return byMonth.putIfAbsent(key, () => _MonthlyIndividualPerformance(key));
    }

    void countCreated({
      required DateTime? createdAt,
      required bool createdByIndividual,
      required bool assignedToIndividual,
      required Iterable<String> assigneeIds,
      required bool isTask,
    }) {
      if (!createdByIndividual) return;
      final m = month(_monthKey(createdAt));
      m.createdTotal++;
      if (isTask) {
        m.createdTasks++;
      } else {
        m.createdSubtasks++;
      }
      final myTeamId = _individualTeamId();
      var hasSameTeamOther = false;
      var hasOtherTeam = false;
      for (final id in assigneeIds) {
        if (_keyMatchesIndividual(id)) continue;
        final teamId = _teamIdByStaffKey[id.trim().toLowerCase()];
        if (myTeamId != null &&
            myTeamId.isNotEmpty &&
            teamId != null &&
            teamId == myTeamId) {
          hasSameTeamOther = true;
        } else {
          hasOtherTeam = true;
        }
      }
      if (hasOtherTeam) {
        m.createdToOtherTeam++;
        if (isTask) {
          m.createdTaskToOtherTeam++;
        } else {
          m.createdSubtaskToOtherTeam++;
        }
      } else if (hasSameTeamOther) {
        m.createdToSameTeam++;
        if (isTask) {
          m.createdTaskToSameTeam++;
        } else {
          m.createdSubtaskToSameTeam++;
        }
      } else if (assignedToIndividual) {
        m.createdToSelf++;
        if (isTask) {
          m.createdTaskToSelf++;
        } else {
          m.createdSubtaskToSelf++;
        }
      } else {
        m.createdToOtherTeam++;
        if (isTask) {
          m.createdTaskToOtherTeam++;
        } else {
          m.createdSubtaskToOtherTeam++;
        }
      }
    }

    void countCompleted({
      required DateTime? completedAt,
      required String? complexity,
      required bool completed,
      required bool isPic,
      required bool isAssignee,
      required bool isCreator,
    }) {
      if (!completed) return;
      final m = month(_monthKey(completedAt));
      final c = _complexityKey(complexity);
      if (isCreator && isPic) {
        m.completedAsCreatorAndPic.increment(c);
      }
      if (isPic && !isCreator) {
        m.completedAsPicNotCreator.increment(c);
      }
      if (isCreator && !isAssignee) {
        m.completedAsCreatorNotAssignee.increment(c);
      }
    }

    for (final t in state.tasks.where((t) => !_taskDeleted(t))) {
      final isCreator = _keyMatchesIndividual(t.createByAssigneeKey);
      final isAssignee = _anyKeyMatchesIndividual(t.assigneeIds);
      final isPic = _keyMatchesIndividual(t.pic);
      countCreated(
        createdAt: t.createdAt,
        createdByIndividual: isCreator,
        assignedToIndividual: isAssignee,
        assigneeIds: t.assigneeIds,
        isTask: true,
      );
      countCompleted(
        completedAt: t.completionDate ?? t.updateDate ?? t.lastUpdated,
        complexity: t.complexity,
        completed: _taskCompleted(t),
        isPic: isPic,
        isAssignee: isAssignee,
        isCreator: isCreator,
      );
    }

    final subtasks = _subtasksByTaskId.values
        .expand((list) => list)
        .where((s) => !_subtaskDeleted(s));
    for (final s in subtasks) {
      final isCreator = _keyMatchesIndividual(s.createByStaffId);
      final isAssignee = _anyKeyMatchesIndividual(s.assigneeIds);
      final isPic = _keyMatchesIndividual(s.pic);
      countCreated(
        createdAt: s.createDate,
        createdByIndividual: isCreator,
        assignedToIndividual: isAssignee,
        assigneeIds: s.assigneeIds,
        isTask: false,
      );
      countCompleted(
        completedAt: s.completionDate ?? s.updateDate,
        complexity: s.complexity,
        completed: _subtaskCompleted(s),
        isPic: isPic,
        isAssignee: isAssignee,
        isCreator: isCreator,
      );
    }

    final months = byMonth.values.toList()
      ..sort((a, b) => b.month.compareTo(a.month));
    return _IndividualPerformance(
      email: 'kenkylee@hku.hk',
      displayName: _individualName?.trim().isNotEmpty == true
          ? _individualName!.trim()
          : 'Ken Lee',
      months: months,
    );
  }

  List<_MonthlyIndividualPerformance> _filteredWorkMonths(
    _IndividualPerformance performance,
  ) {
    final months = performance.months;
    final start = _periodStartMonth;
    final end = _periodEndMonth;
    if ((start == null || start.isEmpty) && (end == null || end.isEmpty)) {
      return months;
    }
    var lower = start;
    var upper = end;
    if (lower != null &&
        upper != null &&
        lower.isNotEmpty &&
        upper.isNotEmpty &&
        lower.compareTo(upper) > 0) {
      final tmp = lower;
      lower = upper;
      upper = tmp;
    }
    return months.where((m) {
      if (lower != null && lower.isNotEmpty && m.month.compareTo(lower) < 0) {
        return false;
      }
      if (upper != null && upper.isNotEmpty && m.month.compareTo(upper) > 0) {
        return false;
      }
      return true;
    }).toList();
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
    final individual = _individualPerformance(state);
    final filteredWorkMonths = _filteredWorkMonths(individual);

    return ColoredBox(
      color: widget.palette.content,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        children: [
          if (widget.viewMode == AsanaPerformanceViewMode.group)
            _OfficePerformanceSection(
              daao: daao,
              cpao: cpao,
              palette: widget.palette,
            ),
          if (widget.viewMode == AsanaPerformanceViewMode.individual)
            _IndividualPerformanceBlock(
              performance: individual,
              workMonths: filteredWorkMonths,
              periodStartMonth: _periodStartMonth,
              periodEndMonth: _periodEndMonth,
              onPeriodStartChanged: (value) {
                setState(() {
                  _periodStartMonth = value;
                });
              },
              onPeriodEndChanged: (value) {
                setState(() {
                  _periodEndMonth = value;
                });
              },
              palette: widget.palette,
            ),
        ],
      ),
    );
  }
}

class _ComplexityCounts {
  int low = 0;
  int medium = 0;
  int high = 0;

  int get total => low + medium + high;
  int get weightedScore => low + medium * 2 + high * 3;
  int get maxComplexityCount =>
      [low, medium, high, 1].reduce((a, b) => a > b ? a : b);

  void increment(String complexity) {
    switch (complexity) {
      case 'Low':
        low++;
      case 'Medium':
        medium++;
      case 'High':
        high++;
      default:
        medium++;
    }
  }
}

class _MonthlyIndividualPerformance {
  _MonthlyIndividualPerformance(this.month);

  final String month;
  int createdTotal = 0;
  int createdTasks = 0;
  int createdSubtasks = 0;
  int createdToSelf = 0;
  int createdToSameTeam = 0;
  int createdToOtherTeam = 0;
  int createdTaskToSelf = 0;
  int createdTaskToSameTeam = 0;
  int createdTaskToOtherTeam = 0;
  int createdSubtaskToSelf = 0;
  int createdSubtaskToSameTeam = 0;
  int createdSubtaskToOtherTeam = 0;
  final completedAsCreatorAndPic = _ComplexityCounts();
  final completedAsPicNotCreator = _ComplexityCounts();
  final completedAsCreatorNotAssignee = _ComplexityCounts();

  int get outputScore =>
      completedAsCreatorAndPic.weightedScore +
      completedAsPicNotCreator.weightedScore;

  int get delegationScore => completedAsCreatorNotAssignee.weightedScore;

  int get workInitiationScore =>
      createdToSelf + createdToSameTeam * 2 + createdToOtherTeam * 3;
}

class _IndividualPerformance {
  const _IndividualPerformance({
    required this.email,
    required this.displayName,
    required this.months,
  });

  final String email;
  final String displayName;
  final List<_MonthlyIndividualPerformance> months;
}

_MonthlyIndividualPerformance _aggregateMonths(
  List<_MonthlyIndividualPerformance> months,
) {
  if (months.isEmpty) return _MonthlyIndividualPerformance('No data');
  final label = months.length == 1
      ? months.first.month
      : '${_monthLabel(months.last.month)} - ${_monthLabel(months.first.month)}';
  final out = _MonthlyIndividualPerformance(label);
  void addCounts(_ComplexityCounts target, _ComplexityCounts source) {
    target.low += source.low;
    target.medium += source.medium;
    target.high += source.high;
  }

  for (final m in months) {
    out.createdTotal += m.createdTotal;
    out.createdTasks += m.createdTasks;
    out.createdSubtasks += m.createdSubtasks;
    out.createdToSelf += m.createdToSelf;
    out.createdToSameTeam += m.createdToSameTeam;
    out.createdToOtherTeam += m.createdToOtherTeam;
    out.createdTaskToSelf += m.createdTaskToSelf;
    out.createdTaskToSameTeam += m.createdTaskToSameTeam;
    out.createdTaskToOtherTeam += m.createdTaskToOtherTeam;
    out.createdSubtaskToSelf += m.createdSubtaskToSelf;
    out.createdSubtaskToSameTeam += m.createdSubtaskToSameTeam;
    out.createdSubtaskToOtherTeam += m.createdSubtaskToOtherTeam;
    addCounts(out.completedAsCreatorAndPic, m.completedAsCreatorAndPic);
    addCounts(out.completedAsPicNotCreator, m.completedAsPicNotCreator);
    addCounts(
      out.completedAsCreatorNotAssignee,
      m.completedAsCreatorNotAssignee,
    );
  }
  return out;
}

class _MobileWorkInitiationCard extends StatelessWidget {
  const _MobileWorkInitiationCard({required this.month, required this.palette});

  final _MonthlyIndividualPerformance month;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    TextStyle? style({bool header = false, bool breakdown = false}) =>
        asanaTextStyle(
          Theme.of(context).textTheme.bodySmall,
          fontSize: header ? 11 : (breakdown ? 11 : 12),
          fontWeight: header
              ? FontWeight.w700
              : (breakdown ? FontWeight.w500 : FontWeight.w700),
          color: header || !breakdown
              ? const Color(0xFF3B4552)
              : kAsanaTextSecondary,
        );

    TableRow row(
      String label,
      int tasks,
      int subtasks, {
      required int total,
      bool breakdown = false,
    }) {
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(label, style: style(breakdown: breakdown)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(
              '$tasks',
              textAlign: TextAlign.right,
              style: style(breakdown: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(
              '$subtasks',
              textAlign: TextAlign.right,
              style: style(breakdown: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text('$total', textAlign: TextAlign.right, style: style()),
          ),
        ],
      );
    }

    Widget header(String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: style(header: true),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.accent.withValues(alpha: 0.04),
          palette.listSurface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.accent.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _monthLabel(month.month),
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.bodyMedium,
                      fontWeight: FontWeight.w800,
                      color: kAsanaTextPrimary,
                    ),
                  ),
                ),
                _UsageScorePill(
                  score: month.workInitiationScore,
                  palette: palette,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.45),
                1: FlexColumnWidth(0.7),
                2: FlexColumnWidth(0.8),
                3: FlexColumnWidth(1.05),
              },
              children: [
                TableRow(
                  children: [
                    const SizedBox.shrink(),
                    header('Tasks'),
                    header('Sub-\ntasks'),
                    header('Work items'),
                  ],
                ),
                row(
                  'Created',
                  month.createdTasks,
                  month.createdSubtasks,
                  total: month.createdTotal,
                ),
                row(
                  'Self-managed',
                  month.createdTaskToSelf,
                  month.createdSubtaskToSelf,
                  total: month.createdToSelf,
                  breakdown: true,
                ),
                row(
                  'Same team',
                  month.createdTaskToSameTeam,
                  month.createdSubtaskToSameTeam,
                  total: month.createdToSameTeam,
                  breakdown: true,
                ),
                row(
                  'Cross team',
                  month.createdTaskToOtherTeam,
                  month.createdSubtaskToOtherTeam,
                  total: month.createdToOtherTeam,
                  breakdown: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageScorePill extends StatelessWidget {
  const _UsageScorePill({required this.score, required this.palette});

  final int score;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'Work Initiation Score = self-managed items x1 + same-team delegation x2 + cross-team delegation x3.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.accent.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            'Usage score $score',
            style: asanaTextStyle(
              Theme.of(context).textTheme.bodySmall,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: palette.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkInitiationScoreInfoButton extends StatelessWidget {
  const _WorkInitiationScoreInfoButton({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return _PerformanceInfoButton(
      palette: palette,
      title: 'Work Creation Activity Score',
      content:
          'It estimates how actively the staff member starts work in Project Tracker.',
      tableRows: const [
        ['Creation pattern', 'Weight'],
        ['Self-managed', '1'],
        ['Same-team delegation', '2'],
        ['Cross-team delegation', '3'],
      ],
    );
  }
}

class _WorkOutputScoreInfoButton extends StatelessWidget {
  const _WorkOutputScoreInfoButton({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return _PerformanceInfoButton(
      palette: palette,
      title: 'Output Score',
      content:
          'This score estimates completed hands-on output from self-initiated own work and collaborative responsibility.',
      tableRows: const [
        ['Complexity', 'Weight'],
        ['Low', '1'],
        ['Medium', '2'],
        ['High', '3'],
      ],
    );
  }
}

class _DelegationScoreInfoButton extends StatelessWidget {
  const _DelegationScoreInfoButton({required this.palette});

  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return _PerformanceInfoButton(
      palette: palette,
      title: 'Delegation Score',
      content:
          'This score estimates management and follow-through for work assigned to others.',
      tableRows: const [
        ['Complexity', 'Weight'],
        ['Low', '1'],
        ['Medium', '2'],
        ['High', '3'],
      ],
    );
  }
}

String _monthLabel(String monthKey) {
  final parts = monthKey.split('-');
  if (parts.length != 2) return monthKey;
  final year = parts[0];
  final month = int.tryParse(parts[1]);
  const names = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  if (month == null || month < 1 || month > 12) return monthKey;
  return '$year ${names[month]}';
}

class _IndividualPerformanceBlock extends StatelessWidget {
  const _IndividualPerformanceBlock({
    required this.performance,
    required this.workMonths,
    required this.periodStartMonth,
    required this.periodEndMonth,
    required this.onPeriodStartChanged,
    required this.onPeriodEndChanged,
    required this.palette,
  });

  final _IndividualPerformance performance;
  final List<_MonthlyIndividualPerformance> workMonths;
  final String? periodStartMonth;
  final String? periodEndMonth;
  final ValueChanged<String?> onPeriodStartChanged;
  final ValueChanged<String?> onPeriodEndChanged;
  final AsanaLandingPalette palette;

  List<DataRow> _usageRows(
    BuildContext context,
    _MonthlyIndividualPerformance m,
  ) {
    Text cell(String value, {bool breakdown = false}) {
      return Text(
        value,
        style: asanaTextStyle(
          Theme.of(context).textTheme.bodySmall,
          fontSize: breakdown ? 11 : 12,
          fontWeight: breakdown ? FontWeight.w500 : FontWeight.w700,
          color: breakdown ? kAsanaTextSecondary : const Color(0xFF3B4552),
        ),
      );
    }

    DataRow row({
      required String month,
      required String type,
      required int created,
      required int self,
      required int sameTeam,
      required int otherTeam,
      required String usageScore,
      required bool breakdown,
    }) {
      return DataRow(
        cells: [
          DataCell(cell(month, breakdown: breakdown)),
          DataCell(cell(type, breakdown: breakdown)),
          DataCell(cell('$created', breakdown: breakdown)),
          DataCell(cell('$self', breakdown: breakdown)),
          DataCell(cell('$sameTeam', breakdown: breakdown)),
          DataCell(cell('$otherTeam', breakdown: breakdown)),
          DataCell(cell(usageScore, breakdown: breakdown)),
        ],
      );
    }

    return [
      row(
        month: _monthLabel(m.month),
        type: 'Work items',
        created: m.createdTotal,
        self: m.createdToSelf,
        sameTeam: m.createdToSameTeam,
        otherTeam: m.createdToOtherTeam,
        usageScore: '${m.workInitiationScore}',
        breakdown: false,
      ),
      row(
        month: '',
        type: 'Tasks',
        created: m.createdTasks,
        self: m.createdTaskToSelf,
        sameTeam: m.createdTaskToSameTeam,
        otherTeam: m.createdTaskToOtherTeam,
        usageScore: '',
        breakdown: true,
      ),
      row(
        month: '',
        type: 'Sub-tasks',
        created: m.createdSubtasks,
        self: m.createdSubtaskToSelf,
        sameTeam: m.createdSubtaskToSameTeam,
        otherTeam: m.createdSubtaskToOtherTeam,
        usageScore: '',
        breakdown: true,
      ),
    ];
  }

  Widget _workInitiationTable(
    BuildContext context,
    _MonthlyIndividualPerformance summaryMonth,
  ) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _MobileWorkInitiationCard(month: summaryMonth, palette: palette),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle: asanaTextStyle(
          Theme.of(context).textTheme.bodySmall,
          fontWeight: FontWeight.w700,
          color: kAsanaTextPrimary,
        ),
        dataTextStyle: asanaTextStyle(
          Theme.of(context).textTheme.bodySmall,
          color: const Color(0xFF3B4552),
        ),
        columns: const [
          DataColumn(label: Text('Month')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('Created')),
          DataColumn(label: Text('Self-managed')),
          DataColumn(label: Text('Same-team delegation')),
          DataColumn(label: Text('Cross-team delegation')),
          DataColumn(label: Text('Usage score')),
        ],
        rows: _usageRows(context, summaryMonth),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summaryMonth = _aggregateMonths(workMonths);
    return Material(
      color: palette.listSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Individual Performance POC',
              style: asanaTextStyle(
                Theme.of(context).textTheme.titleLarge,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: kAsanaTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${performance.displayName} (${performance.email})',
              style: asanaTextStyle(
                Theme.of(context).textTheme.bodyMedium,
                color: kAsanaTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            _WorkPerformanceFilters(
              months: performance.months.map((m) => m.month).toList(),
              periodStartMonth: periodStartMonth,
              periodEndMonth: periodEndMonth,
              onPeriodStartChanged: onPeriodStartChanged,
              onPeriodEndChanged: onPeriodEndChanged,
              palette: palette,
            ),
            const SizedBox(height: 18),
            _PerformanceSectionTitle(
              title: 'Work Output',
              subtitle:
                  'Completed hands-on task/subtask output by role and complexity for the selected months.',
              trailing: _WorkOutputScoreInfoButton(palette: palette),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _MonthlyCompletionCard(month: summaryMonth, palette: palette),
              ],
            ),
            const SizedBox(height: 22),
            _PerformanceSectionTitle(
              title: 'Delegation',
              subtitle:
                  'Work this staff member created for others to complete, summarizing management and follow-through for the selected months.',
              trailing: _DelegationScoreInfoButton(palette: palette),
            ),
            const SizedBox(height: 12),
            _DelegationCard(month: summaryMonth, palette: palette),
            const SizedBox(height: 22),
            _PerformanceSectionTitle(
              title: 'Work Creation Activity',
              subtitle:
                  'How actively this staff member creates work items in Project Tracker, split by task type and delegation pattern.',
              trailing: _WorkInitiationScoreInfoButton(palette: palette),
            ),
            const SizedBox(height: 8),
            _workInitiationTable(context, summaryMonth),
          ],
        ),
      ),
    );
  }
}

class _PerformanceSectionTitle extends StatelessWidget {
  const _PerformanceSectionTitle({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                title,
                style: asanaTextStyle(
                  Theme.of(context).textTheme.titleMedium,
                  fontWeight: FontWeight.w700,
                  color: kAsanaTextPrimary,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: asanaTextStyle(
            Theme.of(context).textTheme.bodySmall,
            color: kAsanaTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _WorkPerformanceFilters extends StatelessWidget {
  const _WorkPerformanceFilters({
    required this.months,
    required this.periodStartMonth,
    required this.periodEndMonth,
    required this.onPeriodStartChanged,
    required this.onPeriodEndChanged,
    required this.palette,
  });

  final List<String> months;
  final String? periodStartMonth;
  final String? periodEndMonth;
  final ValueChanged<String?> onPeriodStartChanged;
  final ValueChanged<String?> onPeriodEndChanged;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AsanaFilterDropdown(
          title: 'Months',
          value: _periodLabel(),
          highlighted: periodStartMonth != null || periodEndMonth != null,
          buttonWidth: 220,
          onPressed: _showPeriodPicker,
        ),
      ],
    );
  }

  String _periodLabel() {
    if (periodStartMonth == null && periodEndMonth == null) return 'All months';
    final start = periodStartMonth == null
        ? 'Start'
        : _monthLabel(periodStartMonth!);
    final end = periodEndMonth == null ? 'End' : _monthLabel(periodEndMonth!);
    return '$start - $end';
  }

  Future<void> _showPeriodPicker(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screen = MediaQuery.sizeOf(buttonContext);
    final panelWidth = screen.width < 456 ? screen.width - 16 : 440.0;
    const panelHeight = 360.0;
    var left = offset.dx;
    if (left + panelWidth > screen.width - 8) {
      left = screen.width - panelWidth - 8;
    }
    if (left < 8) left = 8;
    var top = offset.dy + size.height + 4;
    if (top + panelHeight > screen.height - 8) {
      top = offset.dy - panelHeight - 4;
    }
    if (top < 8) top = 8;

    final result = await showDialog<({String? start, String? end})>(
      context: buttonContext,
      barrierColor: Colors.black26,
      builder: (context) {
        String? start;
        String? end;
        final orderedMonths = months.reversed.toList();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool inRange(String month) {
              if (start == null || end == null) return false;
              var lower = start!;
              var upper = end!;
              if (lower.compareTo(upper) > 0) {
                final tmp = lower;
                lower = upper;
                upper = tmp;
              }
              return month.compareTo(lower) >= 0 && month.compareTo(upper) <= 0;
            }

            void selectMonth(String month) {
              setDialogState(() {
                if (start == null || (start != null && end != null)) {
                  start = month;
                  end = null;
                } else {
                  end = month;
                }
              });
            }

            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    color: Theme.of(context).colorScheme.surface,
                    child: SizedBox(
                      width: panelWidth,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Select period',
                              style: asanaTextStyle(
                                Theme.of(context).textTheme.titleSmall,
                                fontWeight: FontWeight.w700,
                                color: kAsanaTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Click one month for a single-month period, or click two months for a range.',
                              style: asanaDetailLabelStyle(context),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final month in orderedMonths)
                                  ChoiceChip(
                                    label: Text(_monthLabel(month)),
                                    selected:
                                        month == start ||
                                        month == end ||
                                        inRange(month),
                                    onSelected: (_) => selectMonth(month),
                                    side: BorderSide(
                                      color:
                                          (month == start ||
                                              month == end ||
                                              inRange(month))
                                          ? palette.accent
                                          : palette.accent.withValues(
                                              alpha: 0.28,
                                            ),
                                    ),
                                    selectedColor: palette.accent.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, (
                                    start: null,
                                    end: null,
                                  )),
                                  child: const Text('Clear'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: start == null
                                      ? null
                                      : () => Navigator.pop(context, (
                                          start: start,
                                          end: end ?? start,
                                        )),
                                  style:
                                      AsanaTaskDetailActionStyles.updateFilled(
                                        palette,
                                        context: context,
                                      ),
                                  child: const Text('Apply'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      onPeriodStartChanged(result.start);
      onPeriodEndChanged(result.end);
    }
  }
}

class _MonthlyCompletionCard extends StatelessWidget {
  const _MonthlyCompletionCard({required this.month, required this.palette});

  final _MonthlyIndividualPerformance month;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final maxCount = [
      month.completedAsCreatorAndPic.maxComplexityCount,
      month.completedAsPicNotCreator.maxComplexityCount,
      1,
    ].reduce((a, b) => a > b ? a : b);
    return SizedBox(
      width: 360,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            palette.accent.withValues(alpha: 0.04),
            palette.listSurface,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.accent.withValues(alpha: 0.14)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _monthLabel(month.month),
                      style: asanaTextStyle(
                        Theme.of(context).textTheme.titleSmall,
                        fontWeight: FontWeight.w800,
                        color: kAsanaTextPrimary,
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: palette.accent.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        'Output score ${month.outputScore}',
                        style: asanaTextStyle(
                          Theme.of(context).textTheme.bodySmall,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: palette.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ComplexityBarGroup(
                title: 'Self-Initiated Own Work',
                infoText:
                    'Completed tasks/subtasks where this staff member was both Creator and PIC.',
                counts: month.completedAsCreatorAndPic,
                maxCount: maxCount,
                palette: palette,
              ),
              const SizedBox(height: 12),
              _ComplexityBarGroup(
                title: 'Collaborative Responsibility',
                infoText:
                    'Completed tasks/subtasks where this staff member was PIC but not Creator.',
                counts: month.completedAsPicNotCreator,
                maxCount: maxCount,
                palette: palette,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DelegationCard extends StatelessWidget {
  const _DelegationCard({required this.month, required this.palette});

  final _MonthlyIndividualPerformance month;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final counts = month.completedAsCreatorNotAssignee;
    return SizedBox(
      width: 360,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            palette.accent.withValues(alpha: 0.04),
            palette.listSurface,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.accent.withValues(alpha: 0.14)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _monthLabel(month.month),
                      style: asanaTextStyle(
                        Theme.of(context).textTheme.titleSmall,
                        fontWeight: FontWeight.w800,
                        color: kAsanaTextPrimary,
                      ),
                    ),
                  ),
                  _OutputScorePill(
                    label: 'Delegation score',
                    score: month.delegationScore,
                    palette: palette,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ComplexityBarGroup(
                title: 'Delegated Work Assigned',
                infoText:
                    'Completed tasks/subtasks created by this staff member where they were not an assignee.',
                counts: counts,
                maxCount: counts.maxComplexityCount,
                palette: palette,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutputScorePill extends StatelessWidget {
  const _OutputScorePill({
    required this.label,
    required this.score,
    required this.palette,
  });

  final String label;
  final int score;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.accent.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '$label $score',
          style: asanaTextStyle(
            Theme.of(context).textTheme.bodySmall,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: palette.accent,
          ),
        ),
      ),
    );
  }
}

class _ComplexityBarGroup extends StatelessWidget {
  const _ComplexityBarGroup({
    required this.title,
    required this.infoText,
    required this.counts,
    required this.maxCount,
    required this.palette,
  });

  final String title;
  final String infoText;
  final _ComplexityCounts counts;
  final int maxCount;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: asanaTextStyle(
                        Theme.of(context).textTheme.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF3B4552),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _PerformanceInfoButton(
                    palette: palette,
                    title: title,
                    content: infoText,
                  ),
                ],
              ),
            ),
            Text(
              '${counts.total}',
              style: asanaTextStyle(
                Theme.of(context).textTheme.bodySmall,
                fontWeight: FontWeight.w800,
                color: kAsanaTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _ComplexityBar(label: 'Low', value: counts.low, maxCount: maxCount),
        _ComplexityBar(
          label: 'Medium',
          value: counts.medium,
          maxCount: maxCount,
        ),
        _ComplexityBar(label: 'High', value: counts.high, maxCount: maxCount),
      ],
    );
  }
}

class _ComplexityBar extends StatelessWidget {
  const _ComplexityBar({
    required this.label,
    required this.value,
    required this.maxCount,
  });

  final String label;
  final int value;
  final int maxCount;

  Color get _color {
    return switch (label) {
      'Low' => const Color(0xFF2563EB),
      'Medium' => const Color(0xFFF59E0B),
      'High' => const Color(0xFF16A34A),
      _ => const Color(0xFF6B7280),
    };
  }

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount <= 0 ? 0.0 : value / maxCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: asanaTextStyle(
                Theme.of(context).textTheme.bodySmall,
                color: kAsanaTextSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth * fraction.clamp(0.0, 1.0);
                return SizedBox(
                  height: 9,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: width,
                      height: 9,
                      child: ColoredBox(color: _color),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: asanaTextStyle(
                Theme.of(context).textTheme.bodySmall,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3B4552),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceInfoButton extends StatelessWidget {
  const _PerformanceInfoButton({
    required this.palette,
    required this.title,
    required this.content,
    this.tableRows = const [],
  });

  final AsanaLandingPalette palette;
  final String title;
  final String content;
  final List<List<String>> tableRows;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'What does this mean?',
      child: IconButton(
        onPressed: () => _showInfo(context),
        icon: Icon(Icons.info_outline, size: 17, color: palette.accent),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        splashRadius: 16,
      ),
    );
  }

  Future<void> _showInfo(BuildContext context) async {
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: palette.panelBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFEDEAE9), width: 1),
        ),
        elevation: 12,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                title,
                style: asanaTextStyle(
                  theme.textTheme.titleMedium,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kAsanaTextPrimary,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                content,
                style: asanaTextStyle(
                  theme.textTheme.bodyMedium,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: kAsanaTextSecondary,
                  height: 1.4,
                ),
              ),
              if (tableRows.isNotEmpty) ...[
                const SizedBox(height: 14),
                Table(
                  border: TableBorder.all(color: const Color(0xFFE5E7EB)),
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                    1: FlexColumnWidth(1),
                  },
                  children: [
                    for (var i = 0; i < tableRows.length; i++)
                      TableRow(
                        decoration: BoxDecoration(
                          color: i == 0
                              ? palette.accent.withValues(alpha: 0.08)
                              : Colors.transparent,
                        ),
                        children: [
                          for (final cell in tableRows[i])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Text(
                                cell,
                                style: asanaTextStyle(
                                  theme.textTheme.bodySmall,
                                  fontWeight: i == 0
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: i == 0
                                      ? kAsanaTextPrimary
                                      : kAsanaTextSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
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
    required this.pausedTasks,
    required this.pausedSubtasks,
    required this.activeStaff,
  });

  final int projects;
  final int tasks;
  final int subtasks;
  final int completedTasks;
  final int completedSubtasks;
  final int pausedTasks;
  final int pausedSubtasks;
  final int activeStaff;

  int get workItems => tasks + subtasks;
  int get completedWorkItems => completedTasks + completedSubtasks;
  int get pausedWorkItems => pausedTasks + pausedSubtasks;
  int get incompleteWorkItems =>
      (workItems - completedWorkItems - pausedWorkItems).clamp(0, 1 << 30);
}

class _OfficePerformanceSection extends StatelessWidget {
  const _OfficePerformanceSection({
    required this.daao,
    required this.cpao,
    required this.palette,
  });

  final _PerformanceMetrics daao;
  final _PerformanceMetrics cpao;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.listSurface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Office Performance POC',
              style: asanaTextStyle(
                Theme.of(context).textTheme.titleLarge,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: kAsanaTextPrimary,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 920;
                final daaoBlock = _PerformanceBlock(
                  title: 'DAAO',
                  metrics: daao,
                  palette: palette,
                );
                final cpaoBlock = _PerformanceBlock(
                  title: 'CPAO',
                  metrics: cpao,
                  palette: palette,
                );
                if (compact) {
                  return Column(
                    children: [
                      daaoBlock,
                      const SizedBox(height: 18),
                      cpaoBlock,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: daaoBlock),
                    const SizedBox(width: 18),
                    Expanded(child: cpaoBlock),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
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
    const summaryCardHeight = 104.0;
    const summaryCardGap = 14.0;
    const workItemsCardHeight = summaryCardHeight * 2 + summaryCardGap;
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
            _PerformanceCardsLayout(
              metrics: metrics,
              palette: palette,
              summaryCardHeight: summaryCardHeight,
              workItemsCardHeight: workItemsCardHeight,
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkItemsScoreCard extends StatelessWidget {
  const _WorkItemsScoreCard({
    required this.metrics,
    required this.palette,
    required this.height,
  });

  final _PerformanceMetrics metrics;
  final AsanaLandingPalette palette;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            palette.accent.withValues(alpha: 0.08),
            palette.listSurface,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.accent.withValues(alpha: 0.16)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxHeight <= 130) {
              final compactHeight = constraints.maxHeight < 92;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  compactHeight ? 8 : 12,
                  12,
                  compactHeight ? 8 : 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${metrics.workItems}',
                            style: asanaTextStyle(
                              Theme.of(context).textTheme.headlineMedium,
                              fontSize: compactHeight ? 18 : 26,
                              fontWeight: FontWeight.w800,
                              color: palette.accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Work items',
                            style: asanaTextStyle(
                              Theme.of(context).textTheme.bodyMedium,
                              fontSize: compactHeight ? 8.5 : 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF3B4552),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: constraints.maxWidth * 0.28,
                      child: _MiniScoreCard(
                        label: 'Tasks',
                        value: metrics.tasks,
                        palette: palette,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: constraints.maxWidth * 0.28,
                      child: _MiniScoreCard(
                        label: 'Sub-tasks',
                        value: metrics.subtasks,
                        palette: palette,
                      ),
                    ),
                  ],
                ),
              );
            }
            final compact = constraints.maxWidth < 190;
            final side = compact ? 12.0 : 18.0;
            final bottom = compact ? 12.0 : 16.0;
            final subWidth = (constraints.maxWidth - side * 2 - 18) / 2;
            final subHeight = (constraints.maxHeight - 62) / 2;
            return Stack(
              children: [
                Positioned(
                  left: side,
                  top: compact ? 14 : 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${metrics.workItems}',
                        style: asanaTextStyle(
                          Theme.of(context).textTheme.headlineMedium,
                          fontSize: compact ? 26 : 30,
                          fontWeight: FontWeight.w800,
                          color: palette.accent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Work items',
                        style: asanaTextStyle(
                          Theme.of(context).textTheme.bodyMedium,
                          fontSize: compact ? 12 : 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF3B4552),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: side,
                  bottom: bottom,
                  width: subWidth,
                  height: subHeight,
                  child: _MiniScoreCard(
                    label: 'Tasks',
                    value: metrics.tasks,
                    palette: palette,
                  ),
                ),
                Positioned(
                  right: side,
                  bottom: bottom,
                  width: subWidth,
                  height: subHeight,
                  child: _MiniScoreCard(
                    label: 'Sub-tasks',
                    value: metrics.subtasks,
                    palette: palette,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PerformanceCardsLayout extends StatelessWidget {
  const _PerformanceCardsLayout({
    required this.metrics,
    required this.palette,
    required this.summaryCardHeight,
    required this.workItemsCardHeight,
  });

  final _PerformanceMetrics metrics;
  final AsanaLandingPalette palette;
  final double summaryCardHeight;
  final double workItemsCardHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        if (compact) {
          const gap = 10.0;
          const compactCardHeight = 68.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _PerformanceScoreCard(
                      label: 'Projects',
                      value: metrics.projects,
                      palette: palette,
                      wide: true,
                      height: compactCardHeight,
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: _PerformanceScoreCard(
                      label: 'Staff',
                      value: metrics.activeStaff,
                      palette: palette,
                      wide: true,
                      height: compactCardHeight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: gap),
              _WorkItemsScoreCard(
                metrics: metrics,
                palette: palette,
                height: compactCardHeight,
              ),
              const SizedBox(height: gap),
              Row(
                children: [
                  Expanded(
                    child: _PerformanceScoreCard(
                      label: 'Completed',
                      value: metrics.completedWorkItems,
                      palette: palette,
                      wide: true,
                      height: compactCardHeight,
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: _PerformanceScoreCard(
                      label: 'Incomplete',
                      value: metrics.incompleteWorkItems,
                      palette: palette,
                      wide: true,
                      height: compactCardHeight,
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: _PerformanceScoreCard(
                      label: 'Paused',
                      value: metrics.pausedWorkItems,
                      palette: palette,
                      wide: true,
                      height: compactCardHeight,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _PerformanceScoreCard(
                      label: 'Projects',
                      value: metrics.projects,
                      palette: palette,
                      height: summaryCardHeight,
                    ),
                    const SizedBox(height: 14),
                    _PerformanceScoreCard(
                      label: 'Staff',
                      value: metrics.activeStaff,
                      palette: palette,
                      height: summaryCardHeight,
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _WorkItemsScoreCard(
                    metrics: metrics,
                    palette: palette,
                    height: workItemsCardHeight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PerformanceScoreCard(
                    label: 'Completed',
                    value: metrics.completedWorkItems,
                    palette: palette,
                    wide: true,
                    height: summaryCardHeight,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _PerformanceScoreCard(
                    label: 'Incomplete',
                    value: metrics.incompleteWorkItems,
                    palette: palette,
                    wide: true,
                    height: summaryCardHeight,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _PerformanceScoreCard(
                    label: 'Paused',
                    value: metrics.pausedWorkItems,
                    palette: palette,
                    wide: true,
                    height: summaryCardHeight,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MiniScoreCard extends StatelessWidget {
  const _MiniScoreCard({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final int value;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final textColor = Color.lerp(
      palette.accent,
      const Color(0xFF3B4552),
      0.24,
    )!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 70 || constraints.maxHeight < 64;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 5 : 10,
              vertical: compact ? 4 : 8,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.headlineMedium,
                    fontSize: compact ? 15 : 24,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodyMedium,
                    fontSize: compact ? 7.2 : 12,
                    fontWeight: FontWeight.w600,
                    color: textColor.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PerformanceScoreCard extends StatelessWidget {
  const _PerformanceScoreCard({
    required this.label,
    required this.value,
    required this.palette,
    this.wide = false,
    this.height,
  });

  final String label;
  final int value;
  final AsanaLandingPalette palette;
  final bool wide;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wide ? double.infinity : 190,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 120 || constraints.maxHeight < 92;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                palette.accent.withValues(alpha: 0.08),
                palette.listSurface,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.accent.withValues(alpha: 0.16)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 18,
                compact ? 10 : 16,
                compact ? 8 : 18,
                compact ? 10 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.headlineMedium,
                      fontSize: compact ? 18 : 30,
                      fontWeight: FontWeight.w800,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.bodyMedium,
                      fontSize: compact ? 8.5 : 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3B4552),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
