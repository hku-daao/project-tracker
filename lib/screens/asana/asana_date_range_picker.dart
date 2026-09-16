import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/hk_time.dart';
import 'asana_theme.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Month grid with year/month jump controls and themed range selection.
class AsanaDateRangePickerPanel extends StatefulWidget {
  const AsanaDateRangePickerPanel({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.accentColor,
    this.initialRange,
    this.helpText = 'Due date range',
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final Color accentColor;
  final DateTimeRange? initialRange;
  final String helpText;

  @override
  State<AsanaDateRangePickerPanel> createState() =>
      _AsanaDateRangePickerPanelState();
}

class _AsanaDateRangePickerPanelState extends State<AsanaDateRangePickerPanel> {
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  late int _displayYear;
  late int _displayMonth;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRange;
    _rangeStart = initial != null ? _dateOnly(initial.start) : null;
    _rangeEnd = initial != null ? _dateOnly(initial.end) : null;
    final anchor = _rangeEnd ?? _rangeStart ?? HkTime.todayDateOnlyHk();
    _displayYear = anchor.year;
    _displayMonth = anchor.month;
  }

  DateTime get _first => _dateOnly(widget.firstDate);
  DateTime get _last => _dateOnly(widget.lastDate);

  Iterable<int> get _yearOptions =>
      List.generate(_last.year - _first.year + 1, (i) => _first.year + i);

  bool _dayEnabled(DateTime day) =>
      !day.isBefore(_first) && !day.isAfter(_last);

  void _setDisplayMonth(int year, int month) {
    setState(() {
      _displayYear = year;
      _displayMonth = month;
    });
  }

  void _onDayTap(DateTime day) {
    if (!_dayEnabled(day)) return;
    setState(() {
      if (_rangeStart == null || (_rangeStart != null && _rangeEnd != null)) {
        _rangeStart = day;
        _rangeEnd = null;
        return;
      }
      if (day.isBefore(_rangeStart!)) {
        _rangeEnd = _rangeStart;
        _rangeStart = day;
      } else {
        _rangeEnd = day;
      }
    });
  }

  bool _isRangeStart(DateTime day) =>
      _rangeStart != null && _sameDay(day, _rangeStart!);

  bool _isRangeEnd(DateTime day) {
    if (_rangeStart == null) return false;
    final end = _rangeEnd ?? _rangeStart!;
    return _sameDay(day, end);
  }

  bool _inRange(DateTime day) {
    if (_rangeStart == null) return false;
    final end = _rangeEnd ?? _rangeStart!;
    final start = _rangeStart!;
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTimeRange? _buildResult() {
    if (_rangeStart == null) return null;
    final end = _rangeEnd ?? _rangeStart!;
    final start = _rangeStart!.isBefore(end) ? _rangeStart! : end;
    final finish = _rangeStart!.isBefore(end) ? end : _rangeStart!;
    return DateTimeRange(start: start, end: finish);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accentColor;
    final dropdownTheme = theme.copyWith(
      canvasColor: theme.colorScheme.surface,
      colorScheme: theme.colorScheme.copyWith(
        surface: theme.colorScheme.surface,
        primary: accent,
      ),
    );
    final today = HkTime.todayDateOnlyHk();
    final monthLabel = MaterialLocalizations.of(
      context,
    ).formatMonthYear(DateTime(_displayYear, _displayMonth));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.helpText,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: Theme(
                    data: dropdownTheme,
                    child: DropdownButton<int>(
                      dropdownColor: theme.colorScheme.surface,
                      isExpanded: true,
                      value: _displayYear,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: kAsanaTextPrimary,
                      ),
                      items: _yearOptions
                          .map(
                            (y) =>
                                DropdownMenuItem(value: y, child: Text('$y')),
                          )
                          .toList(),
                      onChanged: (y) {
                        if (y == null) return;
                        _setDisplayMonth(y, _displayMonth);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: Theme(
                    data: dropdownTheme,
                    child: DropdownButton<int>(
                      dropdownColor: theme.colorScheme.surface,
                      isExpanded: true,
                      value: _displayMonth,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: kAsanaTextPrimary,
                      ),
                      items: List.generate(12, (i) {
                        final m = i + 1;
                        final monthName = DateFormat.MMM().format(
                          DateTime(2000, m),
                        );
                        return DropdownMenuItem(
                          value: m,
                          child: Text(monthName),
                        );
                      }),
                      onChanged: (m) {
                        if (m == null) return;
                        _setDisplayMonth(_displayYear, m);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            monthLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: kAsanaTextSecondary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _MonthDayGrid(
            year: _displayYear,
            month: _displayMonth,
            accentColor: accent,
            today: today,
            firstDate: _first,
            lastDate: _last,
            isRangeStart: _isRangeStart,
            isRangeEnd: _isRangeEnd,
            inRange: _inRange,
            dayEnabled: _dayEnabled,
            onDayTap: _onDayTap,
          ),
        ),
        if (_rangeStart != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _rangeEnd == null
                  ? 'Select end date'
                  : '${_formatDay(_rangeStart!)} – ${_formatDay(_rangeEnd!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _rangeStart == null
                    ? null
                    : () => Navigator.pop(context, _buildResult()),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: accent.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDay(DateTime d) =>
      MaterialLocalizations.of(context).formatShortDate(d);
}

class _MonthDayGrid extends StatelessWidget {
  const _MonthDayGrid({
    required this.year,
    required this.month,
    required this.accentColor,
    required this.today,
    required this.firstDate,
    required this.lastDate,
    required this.isRangeStart,
    required this.isRangeEnd,
    required this.inRange,
    required this.dayEnabled,
    required this.onDayTap,
  });

  final int year;
  final int month;
  final Color accentColor;
  final DateTime today;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool Function(DateTime day) isRangeStart;
  final bool Function(DateTime day) isRangeEnd;
  final bool Function(DateTime day) inRange;
  final bool Function(DateTime day) dayEnabled;
  final void Function(DateTime day) onDayTap;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(year, month);
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    // Monday-first grid (1 = Mon … 7 = Sun).
    final lead = (firstOfMonth.weekday - 1) % 7;
    final cellCount = lead + daysInMonth;
    final rows = (cellCount / 7).ceil();

    return Column(
      children: [
        Row(
          children: _weekdays
              .map(
                (w) => Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: kAsanaTextSecondary,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: List.generate(7, (c) {
                final index = r * 7 + c;
                if (index < lead || index >= lead + daysInMonth) {
                  return const Expanded(child: SizedBox(height: 36));
                }
                final dayNum = index - lead + 1;
                final day = DateTime(year, month, dayNum);
                final enabled = dayEnabled(day);
                final start = isRangeStart(day);
                final end = isRangeEnd(day);
                final mid = inRange(day) && !start && !end;
                final isToday =
                    day.year == today.year &&
                    day.month == today.month &&
                    day.day == today.day;

                Color? bg;
                Color fg = enabled ? kAsanaTextPrimary : kAsanaTextSecondary;
                Border? border;
                if (start || end) {
                  bg = accentColor;
                  fg = Colors.white;
                } else if (mid) {
                  bg = accentColor.withValues(alpha: 0.18);
                } else if (isToday && enabled) {
                  border = Border.all(color: accentColor, width: 1.5);
                }

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: enabled ? () => onDayTap(day) : null,
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(18),
                            border: border,
                          ),
                          child: Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: start || end
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: enabled ? fg : fg.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

DateTime asanaFirstDayOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

DateTime asanaLastDayOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

/// Result from [AsanaMonthRangePickerPanel]: apply a range or clear it.
class AsanaMonthRangePick {
  const AsanaMonthRangePick.apply(this.range) : cleared = false;
  const AsanaMonthRangePick.clear() : range = null, cleared = true;

  final DateTimeRange? range;
  final bool cleared;
}

/// Year + 12-month grid. First tap sets start month, second tap sets end month.
class AsanaMonthRangePickerPanel extends StatefulWidget {
  const AsanaMonthRangePickerPanel({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.accentColor,
    this.initialStartMonth,
    this.initialEndMonth,
    this.helpText = 'Project start month range',
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final Color accentColor;
  final DateTime? initialStartMonth;
  final DateTime? initialEndMonth;
  final String helpText;

  @override
  State<AsanaMonthRangePickerPanel> createState() =>
      _AsanaMonthRangePickerPanelState();
}

class _AsanaMonthRangePickerPanelState
    extends State<AsanaMonthRangePickerPanel> {
  DateTime? _startMonth;
  DateTime? _endMonth;
  late int _displayYear;

  @override
  void initState() {
    super.initState();
    _startMonth = widget.initialStartMonth == null
        ? null
        : asanaFirstDayOfMonth(widget.initialStartMonth!);
    _endMonth = widget.initialEndMonth == null
        ? null
        : asanaFirstDayOfMonth(widget.initialEndMonth!);
    final anchor = _endMonth ?? _startMonth ?? HkTime.todayDateOnlyHk();
    _displayYear = anchor.year;
  }

  DateTime get _first => asanaFirstDayOfMonth(widget.firstDate);
  DateTime get _last => asanaFirstDayOfMonth(widget.lastDate);

  Iterable<int> get _yearOptions =>
      List.generate(_last.year - _first.year + 1, (i) => _first.year + i);

  bool _monthEnabled(DateTime month) {
    final m = asanaFirstDayOfMonth(month);
    return !m.isBefore(_first) && !m.isAfter(_last);
  }

  void _onMonthTap(DateTime month) {
    if (!_monthEnabled(month)) return;
    final tapped = asanaFirstDayOfMonth(month);
    setState(() {
      if (_startMonth == null || (_startMonth != null && _endMonth != null)) {
        _startMonth = tapped;
        _endMonth = null;
        return;
      }
      if (tapped.isBefore(_startMonth!)) {
        _endMonth = _startMonth;
        _startMonth = tapped;
      } else {
        _endMonth = tapped;
      }
    });
  }

  bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  bool _isStart(DateTime month) =>
      _startMonth != null && _sameMonth(month, _startMonth!);

  bool _isEnd(DateTime month) {
    if (_startMonth == null) return false;
    final end = _endMonth ?? _startMonth!;
    return _sameMonth(month, end);
  }

  bool _inRange(DateTime month) {
    if (_startMonth == null) return false;
    final start = _startMonth!;
    final end = _endMonth ?? _startMonth!;
    final m = asanaFirstDayOfMonth(month);
    return !m.isBefore(start) && !m.isAfter(end);
  }

  DateTimeRange? _buildResult() {
    if (_startMonth == null) return null;
    final start = _startMonth!;
    final end = _endMonth ?? _startMonth!;
    final low = start.isBefore(end) ? start : end;
    final high = start.isBefore(end) ? end : start;
    return DateTimeRange(
      start: asanaFirstDayOfMonth(low),
      end: asanaLastDayOfMonth(high),
    );
  }

  String _monthLabel(DateTime d) => DateFormat('MMM yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accentColor;
    final dropdownTheme = theme.copyWith(
      canvasColor: theme.colorScheme.surface,
      colorScheme: theme.colorScheme.copyWith(
        surface: theme.colorScheme.surface,
        primary: accent,
      ),
    );
    final today = asanaFirstDayOfMonth(HkTime.todayDateOnlyHk());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.helpText,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            _endMonth == null
                ? (_startMonth == null
                      ? 'First tap: earliest project start month.\nSecond tap: latest project start month.'
                      : 'Now choose the latest project start month')
                : 'Project started ${_monthLabel(_startMonth!)} – ${_monthLabel(_endMonth!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: _startMonth == null ? kAsanaTextSecondary : accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonHideUnderline(
            child: Theme(
              data: dropdownTheme,
              child: DropdownButton<int>(
                dropdownColor: theme.colorScheme.surface,
                isExpanded: true,
                value: _displayYear.clamp(_first.year, _last.year),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: kAsanaTextPrimary,
                ),
                items: _yearOptions
                    .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                    .toList(),
                onChanged: (y) {
                  if (y == null) return;
                  setState(() => _displayYear = y);
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            children: [
              for (var row = 0; row < 4; row++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      for (var col = 0; col < 3; col++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: _MonthChip(
                              month: DateTime(_displayYear, row * 3 + col + 1),
                              today: today,
                              enabled: _monthEnabled(
                                DateTime(_displayYear, row * 3 + col + 1),
                              ),
                              isStart: _isStart(
                                DateTime(_displayYear, row * 3 + col + 1),
                              ),
                              isEnd: _isEnd(
                                DateTime(_displayYear, row * 3 + col + 1),
                              ),
                              inRange: _inRange(
                                DateTime(_displayYear, row * 3 + col + 1),
                              ),
                              accent: accent,
                              onTap: () => _onMonthTap(
                                DateTime(_displayYear, row * 3 + col + 1),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const AsanaMonthRangePick.clear()),
                child: const Text('Clear'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _startMonth == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        AsanaMonthRangePick.apply(_buildResult()!),
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: accent.withValues(alpha: 0.35),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({
    required this.month,
    required this.today,
    required this.enabled,
    required this.isStart,
    required this.isEnd,
    required this.inRange,
    required this.accent,
    required this.onTap,
  });

  final DateTime month;
  final DateTime today;
  final bool enabled;
  final bool isStart;
  final bool isEnd;
  final bool inRange;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final edge = isStart || isEnd;
    final bg = edge
        ? accent
        : inRange
        ? accent.withValues(alpha: 0.16)
        : Colors.transparent;
    final fg = !enabled
        ? kAsanaTextSecondary.withValues(alpha: 0.45)
        : edge
        ? Colors.white
        : kAsanaTextPrimary;
    final isToday = month.year == today.year && month.month == today.month;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: isToday && !edge
                ? Border.all(color: accent.withValues(alpha: 0.7))
                : null,
          ),
          child: Text(
            DateFormat('MMM').format(month),
            style: TextStyle(
              fontSize: 13,
              fontWeight: edge ? FontWeight.w700 : FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
