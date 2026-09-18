import 'package:flutter/material.dart';

import '../../utils/hk_time.dart';
import 'asana_detail_widgets.dart';
import 'asana_theme.dart';

enum AsanaRecurrenceFrequency { daily, weekly, monthly, yearly }

enum AsanaDailyMode { everyNDays, everyWeekday }

enum AsanaMonthlyMode { dayOfMonth, nthWeekday }

enum AsanaYearlyMode { monthDay, nthWeekdayOfMonth }

enum AsanaRecurrenceEndMode { byDate, afterCount }

/// Outlook-style recurrence settings used only on create (not stored as a series).
class AsanaRecurrenceDraft {
  AsanaRecurrenceDraft({
    this.frequency = AsanaRecurrenceFrequency.weekly,
    this.interval = 1,
    this.dailyMode = AsanaDailyMode.everyNDays,
    Set<int>? weeklyWeekdays,
    this.monthlyMode = AsanaMonthlyMode.dayOfMonth,
    this.monthDay = 1,
    this.weekdayNth = 1,
    this.weekday = DateTime.monday,
    this.yearlyMode = AsanaYearlyMode.monthDay,
    this.yearlyMonth = 1,
    this.workingDaysInclusive = 4,
    this.endMode = AsanaRecurrenceEndMode.byDate,
    this.endAfterCount = 10,
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) : weeklyWeekdays = weeklyWeekdays ?? <int>{},
       rangeStart = _dateOnly(rangeStart ?? HkTime.todayDateOnlyHk()),
       rangeEnd = _dateOnly(
         rangeEnd ??
             _addMonths(rangeStart ?? HkTime.todayDateOnlyHk(), 3),
       );

  AsanaRecurrenceFrequency frequency;
  int interval;
  AsanaDailyMode dailyMode;
  Set<int> weeklyWeekdays;
  AsanaMonthlyMode monthlyMode;
  int monthDay;
  int weekdayNth;
  int weekday;
  AsanaYearlyMode yearlyMode;
  int yearlyMonth;
  int workingDaysInclusive;
  AsanaRecurrenceEndMode endMode;
  int endAfterCount;
  DateTime rangeStart;
  DateTime rangeEnd;

  static const int maxOccurrences = 52;

  static AsanaRecurrenceDraft seeded({
    DateTime? start,
    int workingDaysInclusive = 4,
  }) {
    final anchor = _dateOnly(start ?? HkTime.todayDateOnlyHk());
    return AsanaRecurrenceDraft(
      weeklyWeekdays: {anchor.weekday},
      monthDay: anchor.day,
      weekday: anchor.weekday,
      weekdayNth: _weekdayNthOf(anchor),
      yearlyMonth: anchor.month,
      workingDaysInclusive: workingDaysInclusive.clamp(1, 99),
      rangeStart: anchor,
      rangeEnd: _addMonths(anchor, 3),
    );
  }

  int get clampedInterval => interval.clamp(1, 99);

  int get clampedWorkingDays => workingDaysInclusive.clamp(1, 99);

  int get clampedEndAfterCount => endAfterCount.clamp(1, maxOccurrences);

  /// Recurring dates are **start dates**, not due dates.
  List<DateTime> occurrenceStartDates() {
    final out = <DateTime>[];
    var d = _dateOnly(rangeStart);
    final targetCount = endMode == AsanaRecurrenceEndMode.afterCount
        ? clampedEndAfterCount
        : maxOccurrences;
    final walkCap = d.add(const Duration(days: 366 * 4));
    final end = endMode == AsanaRecurrenceEndMode.byDate
        ? _dateOnly(rangeEnd)
        : walkCap;
    if (endMode == AsanaRecurrenceEndMode.byDate && end.isBefore(d)) {
      return out;
    }
    final walkEnd = end.isBefore(walkCap) ? end : walkCap;
    while (!d.isAfter(walkEnd) && out.length < targetCount) {
      if (_matches(d)) out.add(d);
      d = d.add(const Duration(days: 1));
    }
    return out;
  }

  bool _matches(DateTime raw) {
    final start = _dateOnly(rangeStart);
    final cur = _dateOnly(raw);
    if (cur.isBefore(start)) return false;
    if (endMode == AsanaRecurrenceEndMode.byDate &&
        cur.isAfter(_dateOnly(rangeEnd))) {
      return false;
    }
    final n = clampedInterval;
    switch (frequency) {
      case AsanaRecurrenceFrequency.daily:
        if (dailyMode == AsanaDailyMode.everyWeekday) {
          return cur.weekday <= DateTime.friday;
        }
        final days = cur.difference(start).inDays;
        return days >= 0 && days % n == 0;
      case AsanaRecurrenceFrequency.weekly:
        final days = weeklyWeekdays.isEmpty
            ? <int>{start.weekday}
            : weeklyWeekdays;
        if (!days.contains(cur.weekday)) return false;
        final startMonday = start.subtract(Duration(days: start.weekday - 1));
        final curMonday = cur.subtract(Duration(days: cur.weekday - 1));
        final weekDelta = curMonday.difference(startMonday).inDays ~/ 7;
        return weekDelta >= 0 && weekDelta % n == 0;
      case AsanaRecurrenceFrequency.monthly:
        final md = (cur.year - start.year) * 12 + (cur.month - start.month);
        if (md < 0 || md % n != 0) return false;
        if (monthlyMode == AsanaMonthlyMode.dayOfMonth) {
          return cur.day == _effectiveDayOfMonth(cur.year, cur.month, monthDay);
        }
        return _isNthWeekday(cur, weekdayNth, weekday);
      case AsanaRecurrenceFrequency.yearly:
        final yd = cur.year - start.year;
        if (yd < 0 || yd % n != 0) return false;
        if (cur.month != yearlyMonth) return false;
        if (yearlyMode == AsanaYearlyMode.monthDay) {
          return cur.day ==
              _effectiveDayOfMonth(cur.year, yearlyMonth, monthDay);
        }
        return _isNthWeekday(cur, weekdayNth, weekday);
    }
  }
}

String asanaRecurringPrefixedName(String originalName, DateTime due) {
  final d = _dateOnly(due);
  final label = '${_kShortMonths[d.month - 1]} ${_englishOrdinal(d.day)}, ${d.year}';
  return '[$label] ${originalName.trim()}';
}

const _kShortMonths = [
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

const _kMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _kWeekdayShort = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
const _kWeekdayDart = [
  DateTime.sunday,
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
  DateTime.saturday,
];
const _kWeekdayLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _kNthLabels = [
  (1, 'First'),
  (2, 'Second'),
  (3, 'Third'),
  (4, 'Fourth'),
  (-1, 'Last'),
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _addMonths(DateTime d, int months) {
  var y = d.year;
  var m = d.month + months;
  while (m > 12) {
    m -= 12;
    y++;
  }
  while (m < 1) {
    m += 12;
    y--;
  }
  final last = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > last ? last : d.day);
}

int _weekdayNthOf(DateTime d) {
  final n = ((d.day - 1) ~/ 7) + 1;
  return n > 4 ? 4 : n;
}

int _effectiveDayOfMonth(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  if (day < 1) return 1;
  return day > last ? last : day;
}

bool _isNthWeekday(DateTime d, int nth, int weekday) {
  if (d.weekday != weekday) return false;
  if (nth == -1) {
    return d.add(const Duration(days: 7)).month != d.month;
  }
  var count = 0;
  for (var day = 1; day <= d.day; day++) {
    if (DateTime(d.year, d.month, day).weekday == weekday) count++;
  }
  return count == nth;
}

String _englishOrdinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

String asanaFormatRecurrenceDate(DateTime d) {
  return HkTime.formatInstantAsHk(_dateOnly(d), 'MMM d, yyyy');
}

String _weekdayLongName(int weekday) {
  if (weekday < 1 || weekday > 7) return '';
  return _kWeekdayLong[weekday - 1];
}

String _nthWord(int nth) {
  for (final e in _kNthLabels) {
    if (e.$1 == nth) return e.$2;
  }
  return '$nth';
}

/// Field/value lines for the recurring-create assignment email.
List<Map<String, String>> asanaRecurrenceEmailFields(
  AsanaRecurrenceDraft draft, {
  String? reason,
}) {
  final fields = <Map<String, String>>[];
  void add(String label, String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    fields.add({'label': label, 'value': v});
  }

  add('Repeat', switch (draft.frequency) {
    AsanaRecurrenceFrequency.daily => 'Daily',
    AsanaRecurrenceFrequency.weekly => 'Weekly',
    AsanaRecurrenceFrequency.monthly => 'Monthly',
    AsanaRecurrenceFrequency.yearly => 'Yearly',
  });

  if (draft.frequency == AsanaRecurrenceFrequency.daily &&
      draft.dailyMode == AsanaDailyMode.everyWeekday) {
    add('Every', 'Weekday (Monday–Friday)');
  } else {
    final n = draft.clampedInterval;
    final unit = switch (draft.frequency) {
      AsanaRecurrenceFrequency.daily => n == 1 ? 'day' : 'days',
      AsanaRecurrenceFrequency.weekly => n == 1 ? 'week' : 'weeks',
      AsanaRecurrenceFrequency.monthly => n == 1 ? 'month' : 'months',
      AsanaRecurrenceFrequency.yearly => n == 1 ? 'year' : 'years',
    };
    add('Every', '$n $unit');
  }

  switch (draft.frequency) {
    case AsanaRecurrenceFrequency.weekly:
      final days = (draft.weeklyWeekdays.isEmpty
              ? <int>{draft.rangeStart.weekday}
              : draft.weeklyWeekdays)
          .toList()
        ..sort();
      add(
        'On',
        days.map(_weekdayLongName).where((n) => n.isNotEmpty).join(', '),
      );
    case AsanaRecurrenceFrequency.monthly:
      if (draft.monthlyMode == AsanaMonthlyMode.dayOfMonth) {
        add('Pattern', 'Day of month');
        add('Day', _englishOrdinal(draft.monthDay.clamp(1, 31)));
      } else {
        add('Pattern', 'The Nth weekday');
        add(
          'On',
          '${_nthWord(draft.weekdayNth)} ${_weekdayLongName(draft.weekday)}',
        );
      }
    case AsanaRecurrenceFrequency.yearly:
      final month = _kMonthNames[(draft.yearlyMonth.clamp(1, 12)) - 1];
      if (draft.yearlyMode == AsanaYearlyMode.monthDay) {
        add('Pattern', 'On month and day');
        add('On', '$month ${_englishOrdinal(draft.monthDay.clamp(1, 31))}');
      } else {
        add('Pattern', 'The Nth weekday of month');
        add(
          'On',
          '${_nthWord(draft.weekdayNth)} ${_weekdayLongName(draft.weekday)} of $month',
        );
      }
    case AsanaRecurrenceFrequency.daily:
      break;
  }

  add('Working days required', '${draft.clampedWorkingDays}');
  add('Reason', reason ?? '');
  add('Start at', asanaFormatRecurrenceDate(draft.rangeStart));
  if (draft.endMode == AsanaRecurrenceEndMode.byDate) {
    add('End', 'End by ${asanaFormatRecurrenceDate(draft.rangeEnd)}');
  } else {
    final n = draft.clampedEndAfterCount;
    add('End', 'End after $n ${n == 1 ? 'occurrence' : 'occurrences'}');
  }
  return fields;
}

class AsanaRecurrenceCreateSection extends StatelessWidget {
  const AsanaRecurrenceCreateSection({
    super.key,
    required this.expanded,
    required this.draft,
    required this.canEdit,
    required this.onToggle,
    required this.onChanged,
    required this.onPickStartAt,
    required this.onPickEndBy,
    required this.defaultWorkingDays,
    this.reasonController,
    this.reasonReadOnly = false,
  });

  final bool expanded;
  final AsanaRecurrenceDraft draft;
  final bool canEdit;
  final VoidCallback onToggle;
  final VoidCallback onChanged;
  final Future<void> Function(BuildContext fieldContext) onPickStartAt;
  final Future<void> Function(BuildContext fieldContext) onPickEndBy;
  final int defaultWorkingDays;
  final TextEditingController? reasonController;
  final bool reasonReadOnly;

  bool get _needsReason => draft.clampedWorkingDays > defaultWorkingDays;

  @override
  Widget build(BuildContext context) {
    final count = expanded ? draft.occurrenceStartDates().length : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: canEdit ? onToggle : null,
              icon: Icon(
                expanded ? Icons.repeat : Icons.repeat_outlined,
                size: 18,
                color: expanded
                    ? Theme.of(context).colorScheme.primary
                    : kAsanaTextSecondary,
              ),
              label: Text(
                expanded ? 'Recurring (on)' : 'Make recurring',
                style: asanaTextStyle(
                  Theme.of(context).textTheme.bodySmall,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: expanded
                      ? Theme.of(context).colorScheme.primary
                      : kAsanaTextSecondary,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                border: Border.all(color: const Color(0xFFEDEAE9)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(context, 'Repeat'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final f in AsanaRecurrenceFrequency.values)
                        _chip(
                          context,
                          label: _frequencyLabel(f),
                          selected: draft.frequency == f,
                          onTap: () {
                            draft.frequency = f;
                            onChanged();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _intervalRow(context),
                  ..._patternExtras(context),
                  const SizedBox(height: 12),
                  _label(context, 'Working days required'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _stepper(
                        context,
                        value: draft.clampedWorkingDays,
                        onChanged: (v) {
                          draft.workingDaysInclusive = v;
                          onChanged();
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          draft.clampedWorkingDays == 1
                              ? 'working day (including start date)'
                              : 'working days (including start date)',
                          style: asanaTextStyle(
                            Theme.of(context).textTheme.bodySmall,
                            fontSize: 13,
                            color: kAsanaTextPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Default is $defaultWorkingDays for the current priority '
                    '(Standard 4, Urgent 2).',
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.bodySmall,
                      fontSize: 12,
                      color: kAsanaTextSecondary,
                    ),
                  ),
                  if (_needsReason && reasonController != null) ...[
                    const SizedBox(height: 10),
                    _label(context, 'Reason'),
                    const SizedBox(height: 6),
                    AsanaHoverTextField(
                      controller: reasonController!,
                      canEdit: canEdit,
                      readOnly: reasonReadOnly,
                      showOutline: true,
                      maxLines: 4,
                      minLines: 2,
                      hintText: 'Required when working days exceed the default',
                      style: asanaDetailMultilineValueStyle(context),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _label(context, 'Start at'),
                  const SizedBox(height: 6),
                  AsanaHoverTapValueLike(
                    text: asanaFormatRecurrenceDate(draft.rangeStart),
                    canEdit: canEdit,
                    onTap: onPickStartAt,
                  ),
                  const SizedBox(height: 12),
                  _label(context, 'End'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip(
                        context,
                        label: 'End by date',
                        selected: draft.endMode == AsanaRecurrenceEndMode.byDate,
                        onTap: () {
                          draft.endMode = AsanaRecurrenceEndMode.byDate;
                          onChanged();
                        },
                      ),
                      _chip(
                        context,
                        label: 'End after',
                        selected:
                            draft.endMode == AsanaRecurrenceEndMode.afterCount,
                        onTap: () {
                          draft.endMode = AsanaRecurrenceEndMode.afterCount;
                          onChanged();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (draft.endMode == AsanaRecurrenceEndMode.byDate)
                    AsanaHoverTapValueLike(
                      text: asanaFormatRecurrenceDate(draft.rangeEnd),
                      canEdit: canEdit,
                      onTap: onPickEndBy,
                    )
                  else
                    Row(
                      children: [
                        _stepper(
                          context,
                          value: draft.clampedEndAfterCount,
                          maxValue: AsanaRecurrenceDraft.maxOccurrences,
                          onChanged: (v) {
                            draft.endAfterCount = v;
                            onChanged();
                          },
                        ),
                        const SizedBox(width: 8),
                        Text(
                          draft.clampedEndAfterCount == 1
                              ? 'occurrence'
                              : 'occurrences',
                          style: asanaTextStyle(
                            Theme.of(context).textTheme.bodySmall,
                            fontSize: 13,
                            color: kAsanaTextPrimary,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Text(
                    count == 0
                        ? draft.endMode == AsanaRecurrenceEndMode.byDate
                              ? 'No start dates match this pattern between Start at and End by.'
                              : 'No start dates match this pattern.'
                        : draft.endMode == AsanaRecurrenceEndMode.byDate &&
                              count >= AsanaRecurrenceDraft.maxOccurrences
                        ? 'Creates ${AsanaRecurrenceDraft.maxOccurrences} items (limit).'
                        : 'Creates $count item${count == 1 ? '' : 's'} (start dates).',
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.bodySmall,
                      fontSize: 12,
                      color: kAsanaTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _intervalRow(BuildContext context) {
    final unit = switch (draft.frequency) {
      AsanaRecurrenceFrequency.daily =>
        draft.dailyMode == AsanaDailyMode.everyWeekday ? 'weekday' : 'day',
      AsanaRecurrenceFrequency.weekly => 'week',
      AsanaRecurrenceFrequency.monthly => 'month',
      AsanaRecurrenceFrequency.yearly => 'year',
    };
    final hideStepper =
        draft.frequency == AsanaRecurrenceFrequency.daily &&
        draft.dailyMode == AsanaDailyMode.everyWeekday;
    if (hideStepper) {
      return Text(
        'Every weekday (Monday–Friday)',
        style: asanaTextStyle(
          Theme.of(context).textTheme.bodySmall,
          fontSize: 13,
          color: kAsanaTextPrimary,
        ),
      );
    }
    return Row(
      children: [
        Text(
          'Every',
          style: asanaTextStyle(
            Theme.of(context).textTheme.bodySmall,
            fontSize: 13,
            color: kAsanaTextPrimary,
          ),
        ),
        const SizedBox(width: 8),
        _stepper(
          context,
          value: draft.clampedInterval,
          onChanged: (v) {
            draft.interval = v;
            onChanged();
          },
        ),
        const SizedBox(width: 8),
        Text(
          draft.clampedInterval == 1 ? unit : '${unit}s',
          style: asanaTextStyle(
            Theme.of(context).textTheme.bodySmall,
            fontSize: 13,
            color: kAsanaTextPrimary,
          ),
        ),
      ],
    );
  }

  List<Widget> _patternExtras(BuildContext context) {
    switch (draft.frequency) {
      case AsanaRecurrenceFrequency.daily:
        return [
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                context,
                label: 'Every N days',
                selected: draft.dailyMode == AsanaDailyMode.everyNDays,
                onTap: () {
                  draft.dailyMode = AsanaDailyMode.everyNDays;
                  onChanged();
                },
              ),
              _chip(
                context,
                label: 'Every weekday',
                selected: draft.dailyMode == AsanaDailyMode.everyWeekday,
                onTap: () {
                  draft.dailyMode = AsanaDailyMode.everyWeekday;
                  onChanged();
                },
              ),
            ],
          ),
        ];
      case AsanaRecurrenceFrequency.weekly:
        return [
          const SizedBox(height: 10),
          _label(context, 'On'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _kWeekdayShort.length; i++)
                _chip(
                  context,
                  label: _kWeekdayShort[i],
                  selected: draft.weeklyWeekdays.contains(_kWeekdayDart[i]),
                  onTap: () {
                    final day = _kWeekdayDart[i];
                    if (draft.weeklyWeekdays.contains(day)) {
                      if (draft.weeklyWeekdays.length > 1) {
                        draft.weeklyWeekdays.remove(day);
                      }
                    } else {
                      draft.weeklyWeekdays.add(day);
                    }
                    onChanged();
                  },
                ),
            ],
          ),
        ];
      case AsanaRecurrenceFrequency.monthly:
        return [
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                context,
                label: 'Day of month',
                selected: draft.monthlyMode == AsanaMonthlyMode.dayOfMonth,
                onTap: () {
                  draft.monthlyMode = AsanaMonthlyMode.dayOfMonth;
                  onChanged();
                },
              ),
              _chip(
                context,
                label: 'The Nth weekday',
                selected: draft.monthlyMode == AsanaMonthlyMode.nthWeekday,
                onTap: () {
                  draft.monthlyMode = AsanaMonthlyMode.nthWeekday;
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (draft.monthlyMode == AsanaMonthlyMode.dayOfMonth)
            _dayOfMonthDropdown(context)
          else
            _nthWeekdayRow(context),
        ];
      case AsanaRecurrenceFrequency.yearly:
        return [
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                context,
                label: 'On month and day',
                selected: draft.yearlyMode == AsanaYearlyMode.monthDay,
                onTap: () {
                  draft.yearlyMode = AsanaYearlyMode.monthDay;
                  onChanged();
                },
              ),
              _chip(
                context,
                label: 'The Nth weekday of month',
                selected: draft.yearlyMode == AsanaYearlyMode.nthWeekdayOfMonth,
                onTap: () {
                  draft.yearlyMode = AsanaYearlyMode.nthWeekdayOfMonth;
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (draft.yearlyMode == AsanaYearlyMode.monthDay)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _monthDropdown(context),
                _dayOfMonthDropdown(context),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _nthDropdown(context),
                _weekdayDropdown(context),
                _monthDropdown(context),
              ],
            ),
        ];
    }
  }

  Widget _dayOfMonthDropdown(BuildContext context) {
    return _dropdown<int>(
      context,
      value: draft.monthDay.clamp(1, 31),
      items: [
        for (var d = 1; d <= 31; d++)
          DropdownMenuItem(value: d, child: Text(_englishOrdinal(d))),
      ],
      onChanged: (v) {
        if (v == null) return;
        draft.monthDay = v;
        onChanged();
      },
    );
  }

  Widget _nthWeekdayRow(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [_nthDropdown(context), _weekdayDropdown(context)],
    );
  }

  Widget _nthDropdown(BuildContext context) {
    return _dropdown<int>(
      context,
      value: draft.weekdayNth,
      items: [
        for (final e in _kNthLabels)
          DropdownMenuItem(value: e.$1, child: Text(e.$2)),
      ],
      onChanged: (v) {
        if (v == null) return;
        draft.weekdayNth = v;
        onChanged();
      },
    );
  }

  Widget _weekdayDropdown(BuildContext context) {
    return _dropdown<int>(
      context,
      value: draft.weekday,
      items: [
        for (var i = 0; i < _kWeekdayLong.length; i++)
          DropdownMenuItem(value: i + 1, child: Text(_kWeekdayLong[i])),
      ],
      onChanged: (v) {
        if (v == null) return;
        draft.weekday = v;
        onChanged();
      },
    );
  }

  Widget _monthDropdown(BuildContext context) {
    return _dropdown<int>(
      context,
      value: draft.yearlyMonth.clamp(1, 12),
      items: [
        for (var i = 0; i < _kMonthNames.length; i++)
          DropdownMenuItem(value: i + 1, child: Text(_kMonthNames[i])),
      ],
      onChanged: (v) {
        if (v == null) return;
        draft.yearlyMonth = v;
        onChanged();
      },
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        items: items,
        onChanged: canEdit ? onChanged : null,
        style: asanaTextStyle(
          Theme.of(context).textTheme.bodySmall,
          fontSize: 13,
          color: kAsanaTextPrimary,
        ),
      ),
    );
  }

  Widget _stepper(
    BuildContext context, {
    required int value,
    required ValueChanged<int> onChanged,
    int maxValue = 99,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepButton(context, Icons.remove, () {
          if (value > 1) onChanged(value - 1);
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '$value',
            style: asanaTextStyle(
              Theme.of(context).textTheme.bodyMedium,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kAsanaTextPrimary,
            ),
          ),
        ),
        _stepButton(context, Icons.add, () {
          if (value < maxValue) onChanged(value + 1);
        }),
      ],
    );
  }

  Widget _stepButton(BuildContext context, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: canEdit ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: kAsanaTextSecondary),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected ? primary.withValues(alpha: 0.12) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: canEdit ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? primary : const Color(0xFFEDEAE9),
            ),
          ),
          child: Text(
            label,
            style: asanaTextStyle(
              Theme.of(context).textTheme.bodySmall,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? primary : kAsanaTextPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Text(
      text,
      style: asanaTextStyle(
        Theme.of(context).textTheme.bodySmall,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: kAsanaTextSecondary,
      ),
    );
  }

  String _frequencyLabel(AsanaRecurrenceFrequency f) {
    return switch (f) {
      AsanaRecurrenceFrequency.daily => 'Daily',
      AsanaRecurrenceFrequency.weekly => 'Weekly',
      AsanaRecurrenceFrequency.monthly => 'Monthly',
      AsanaRecurrenceFrequency.yearly => 'Yearly',
    };
  }
}

/// Compact tappable value used inside the recurrence box (avoids the 2-col row).
class AsanaHoverTapValueLike extends StatefulWidget {
  const AsanaHoverTapValueLike({
    super.key,
    required this.text,
    required this.canEdit,
    required this.onTap,
  });

  final String text;
  final bool canEdit;
  final Future<void> Function(BuildContext fieldContext) onTap;

  @override
  State<AsanaHoverTapValueLike> createState() => _AsanaHoverTapValueLikeState();
}

class _AsanaHoverTapValueLikeState extends State<AsanaHoverTapValueLike> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.canEdit ? () => widget.onTap(context) : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.canEdit && _hovering
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFFEDEAE9),
            ),
          ),
          child: Text(
            widget.text,
            style: asanaTextStyle(
              Theme.of(context).textTheme.bodySmall,
              fontSize: 13,
              color: kAsanaTextPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
