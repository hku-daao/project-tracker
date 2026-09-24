import 'package:flutter/material.dart';

import '../../utils/hk_time.dart';
import 'asana_theme.dart';

/// Same Overdue / Due today / Completed chip used on task lists and map blocks.
class AsanaDueBadge extends StatelessWidget {
  const AsanaDueBadge({super.key, required this.label});

  final String label;

  static String? labelFor({
    required DateTime? due,
    required String status,
    String? submission,
  }) {
    if (status.trim().toLowerCase() != 'incomplete') return null;
    if ((submission ?? '').trim().toLowerCase() == 'submitted') return null;
    if (due == null) return null;
    final today = HkTime.todayDateOnlyHk();
    final day = DateTime(due.year, due.month, due.day);
    if (day.year == today.year &&
        day.month == today.month &&
        day.day == today.day) {
      return 'Due today';
    }
    if (day.isBefore(today)) return 'Overdue';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final (:bg, :fg) = switch (label) {
      'Overdue' => (
        bg: const Color(0xFFFFEBEE),
        fg: const Color(0xFFC62828),
      ),
      'Completed' => (
        bg: const Color(0xFFE8F5E9),
        fg: const Color(0xFF2E7D32),
      ),
      _ => (
        bg: const Color(0xFFFFF3E0),
        fg: const Color(0xFFE65100),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: asanaTextStyle(
          Theme.of(context).textTheme.labelSmall,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1.1,
        ),
      ),
    );
  }
}
