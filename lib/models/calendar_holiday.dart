/// Row from [public.calendar_holiday] (HKU vs HK calendar markers).
class CalendarHoliday {
  const CalendarHoliday({
    required this.holidayType,
    required this.name,
    required this.date,
    required this.fullOrPm,
  });

  final String holidayType;
  final String name;
  final DateTime date;
  final String fullOrPm;

  bool get isHku =>
      holidayType.trim().toUpperCase() == 'HKU';

  bool get isHk => holidayType.trim().toUpperCase() == 'HK';

  factory CalendarHoliday.fromMap(Map<String, dynamic> m) {
    final raw = m['holiday_date'];
    DateTime d;
    if (raw is DateTime) {
      d = DateTime(raw.year, raw.month, raw.day);
    } else {
      final s = raw?.toString().trim() ?? '';
      final parts = s.split('T').first.split('-');
      if (parts.length >= 3) {
        d = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      } else {
        d = DateTime.now();
      }
    }
    return CalendarHoliday(
      holidayType: (m['holiday_type'] ?? m['holidayType'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      date: d,
      fullOrPm: (m['full_or_pm'] ?? m['fullOrPm'] ?? 'Full').toString(),
    );
  }
}
