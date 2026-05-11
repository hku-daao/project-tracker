import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/supabase_config.dart';
import '../models/calendar_holiday.dart';
import '../services/supabase_service.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _clampDay(DateTime day, DateTime first, DateTime last) {
  final x = _dateOnly(day);
  final a = _dateOnly(first);
  final b = _dateOnly(last);
  if (x.isBefore(a)) return a;
  if (x.isAfter(b)) return b;
  return x;
}

String _formatYmd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Returns null if not exactly `yyyy-mm-dd` or not a real calendar day.
DateTime? _tryParseYmd(String raw) {
  final s = raw.trim();
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final y = int.tryParse(m.group(1)!);
  final mo = int.tryParse(m.group(2)!);
  final day = int.tryParse(m.group(3)!);
  if (y == null || mo == null || day == null) return null;
  if (mo < 1 || mo > 12) return null;
  final dim = DateTime(y, mo + 1, 0).day;
  if (day < 1 || day > dim) return null;
  return DateTime(y, mo, day);
}

/// Loads holidays from Supabase when configured; otherwise falls back to [showDatePicker].
Future<DateTime?> showHolidayAwareDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  if (!SupabaseConfig.isConfigured) {
    return showDatePicker(
      context: context,
      initialDate: _clampDay(initialDate, firstDate, lastDate),
      firstDate: _dateOnly(firstDate),
      lastDate: _dateOnly(lastDate),
    );
  }
  final holidays = await SupabaseService.fetchCalendarHolidaysBetween(
    firstDate,
    lastDate,
  );
  if (!context.mounted) return null;
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => _HolidayDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      holidays: holidays,
    ),
  );
}

class _HolidayDatePickerDialog extends StatefulWidget {
  const _HolidayDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.holidays,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final List<CalendarHoliday> holidays;

  @override
  State<_HolidayDatePickerDialog> createState() => _HolidayDatePickerDialogState();
}

class _HolidayDatePickerDialogState extends State<_HolidayDatePickerDialog> {
  late DateTime _displayMonth;
  late DateTime _selected;
  late final TextEditingController _dateInputController;

  static const _hkuBg = Color(0xFFE3F2FD);
  static const _hkuFg = Color(0xFF0D47A1);
  static const _hkBg = Color(0xFFFFEBEE);
  static const _hkFg = Color(0xFFB71C1C);

  Map<String, List<CalendarHoliday>> get _byDayKey {
    final m = <String, List<CalendarHoliday>>{};
    for (final h in widget.holidays) {
      final k =
          '${h.date.year}-${h.date.month.toString().padLeft(2, '0')}-${h.date.day.toString().padLeft(2, '0')}';
      m.putIfAbsent(k, () => []).add(h);
    }
    return m;
  }

  @override
  void initState() {
    super.initState();
    final i = _clampDay(widget.initialDate, widget.firstDate, widget.lastDate);
    _selected = i;
    _displayMonth = DateTime(i.year, i.month, 1);
    _dateInputController = TextEditingController(text: _formatYmd(i));
  }

  @override
  void dispose() {
    _dateInputController.dispose();
    super.dispose();
  }

  void _syncInputFromSelected() {
    _dateInputController.text = _formatYmd(_selected);
  }

  bool get _canGoPrev {
    final lastPrev = DateTime(_displayMonth.year, _displayMonth.month, 0);
    return !_dateOnly(lastPrev).isBefore(_dateOnly(widget.firstDate));
  }

  bool get _canGoNext {
    final firstNext = DateTime(_displayMonth.year, _displayMonth.month + 1, 1);
    return !_dateOnly(firstNext).isAfter(_dateOnly(widget.lastDate));
  }

  void _prevMonth() {
    if (!_canGoPrev) return;
    setState(() {
      _displayMonth =
          DateTime(_displayMonth.year, _displayMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    if (!_canGoNext) return;
    setState(() {
      _displayMonth =
          DateTime(_displayMonth.year, _displayMonth.month + 1, 1);
    });
  }

  List<DateTime?> _cellsForMonth() {
    final y = _displayMonth.year;
    final mo = _displayMonth.month;
    final first = DateTime(y, mo, 1);
    // Week starts Sunday: Sun=0 … Sat=6 (Dart weekday Mon=1 … Sun=7).
    final lead = first.weekday % 7;
    final dim = DateTime(y, mo + 1, 0).day;
    final cells = <DateTime?>[];
    for (var i = 0; i < lead; i++) {
      cells.add(null);
    }
    for (var d = 1; d <= dim; d++) {
      cells.add(DateTime(y, mo, d));
    }
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    while (cells.length < 42) {
      cells.add(null);
    }
    return cells;
  }

  Widget _weekdayHeader(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final refSunday = DateTime(2024, 1, 7);
    final fmt = DateFormat.E(locale.toString());
    final labels =
        List.generate(7, (i) => fmt.format(refSunday.add(Duration(days: i))));
    final theme = Theme.of(context);
    final sunRed = Colors.red.shade800;
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                labels[i],
                style: theme.textTheme.labelSmall?.copyWith(
                  color: i == 0 ? sunRed : null,
                  fontWeight: i == 0 ? FontWeight.w600 : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dayCell(BuildContext context, DateTime? day) {
    final theme = Theme.of(context);
    if (day == null) {
      return const Expanded(child: SizedBox(height: 56));
    }
    final d = _dateOnly(day);
    final inRange =
        !d.isBefore(_dateOnly(widget.firstDate)) &&
        !d.isAfter(_dateOnly(widget.lastDate));
    final key =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final hol = _byDayKey[key] ?? const <CalendarHoliday>[];
    final hasHku = hol.any((h) => h.isHku);
    final hasHk = hol.any((h) => h.isHk);
    Color? bg;
    Color nameColor = theme.colorScheme.onSurface;
    if (hol.isNotEmpty) {
      if (hasHku && hasHk) {
        bg = Color.lerp(_hkuBg, _hkBg, 0.5)!;
        nameColor = theme.colorScheme.onSurface;
      } else if (hasHku) {
        bg = _hkuBg;
        nameColor = _hkuFg;
      } else {
        bg = _hkBg;
        nameColor = _hkFg;
      }
    }
    final selected = _dateOnly(_selected) == d;
    final label = hol.map((h) => h.name).join(' · ');
    final isSunday = d.weekday == DateTime.sunday;
    final sunRed = Colors.red.shade800;
    final dayNumColor = !inRange
        ? theme.colorScheme.outline
        : (hasHk ? _hkFg : (isSunday ? sunRed : theme.colorScheme.onSurface));
    final child = Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: inRange
            ? () => setState(() {
                  _selected = d;
                  _syncInputFromSelected();
                })
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${d.day}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: dayNumColor,
                ),
              ),
              if (hol.isNotEmpty)
                Flexible(
                  child: Tooltip(
                    message: label,
                    child: Text(
                      hol.length == 1 ? hol.first.name : label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        height: 1.05,
                        color: nameColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!inRange) {
      return Expanded(
        child: Opacity(opacity: 0.35, child: child),
      );
    }
    return Expanded(child: child);
  }

  void _onOk(BuildContext context) {
    final raw = _dateInputController.text.trim();
    if (raw.isEmpty) {
      Navigator.of(context).pop(_selected);
      return;
    }
    final parsed = _tryParseYmd(raw);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter date as yyyy-mm-dd')),
      );
      return;
    }
    final clamped = _clampDay(parsed, widget.firstDate, widget.lastDate);
    if (clamped != _dateOnly(parsed)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Date was adjusted to stay within the allowed range'),
        ),
      );
    }
    Navigator.of(context).pop(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = DateFormat.yMMMM(
      Localizations.localeOf(context).toString(),
    ).format(_displayMonth);
    final cells = _cellsForMonth();
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      title: Row(
        children: [
          IconButton(
            onPressed: _canGoPrev ? _prevMonth : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: _canGoNext ? _nextMonth : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _dateInputController,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Date',
                hintText: 'yyyy-mm-dd',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            _weekdayHeader(context),
            const SizedBox(height: 6),
            for (var r = 0; r < 6; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    for (var c = 0; c < 7; c++)
                      _dayCell(context, cells[r * 7 + c]),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: Text(
                'Holiday',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: _hkuBg,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('HKU', style: theme.textTheme.labelSmall),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: _hkBg,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('HK', style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _onOk(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
