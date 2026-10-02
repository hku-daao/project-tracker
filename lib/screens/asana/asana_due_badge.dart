import 'package:flutter/material.dart';

import '../../utils/hk_time.dart';
import 'asana_theme.dart';

/// Same Overdue / Due Today / Incomplete / Completed / Submitted chip used on map blocks.
class AsanaDueBadge extends StatelessWidget {
  const AsanaDueBadge({
    super.key,
    required this.label,
    this.fontSize = 9,
    this.height,
  });

  final String label;
  final double fontSize;
  final double? height;

  static String? labelFor({
    required DateTime? due,
    required String status,
    String? submission,
    bool completed = false,
  }) {
    if (completed) return 'Completed';
    if ((submission ?? '').trim().toLowerCase() == 'submitted') {
      return 'Submitted';
    }
    if (status.trim().toLowerCase() != 'incomplete') return null;
    if (due != null) {
      final today = HkTime.todayDateOnlyHk();
      final day = DateTime(due.year, due.month, due.day);
      if (day.year == today.year &&
          day.month == today.month &&
          day.day == today.day) {
        return 'Due Today';
      }
      if (day.isBefore(today)) return 'Overdue';
    }
    return 'Incomplete';
  }

  @override
  Widget build(BuildContext context) {
    final (:bg, :fg) = switch (label) {
      'Overdue' => (
        bg: const Color(0xFFFFEBEE),
        fg: const Color(0xFFC62828),
      ),
      'Due Today' || 'Due today' => (
        bg: const Color(0xFFFFF3E0),
        fg: const Color(0xFFE65100),
      ),
      'Completed' => (
        bg: const Color(0xFFE8F5E9),
        fg: const Color(0xFF2E7D32),
      ),
      'Submitted' => (
        bg: Colors.red,
        fg: Colors.white,
      ),
      'Incomplete' => (
        bg: const Color(0xFFECEFF1),
        fg: const Color(0xFF455A64),
      ),
      _ => (
        bg: const Color(0xFFFFF3E0),
        fg: const Color(0xFFE65100),
      ),
    };
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: 6,
        vertical: height == null ? 1 : 0,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: asanaTextStyle(
          Theme.of(context).textTheme.labelSmall,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1,
        ),
      ),
    );
  }
}

/// Overdue / Due today chip used on the Task view due-date cell.
String? asanaTaskViewDueLabel({
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

/// Same Overdue / Due today label as the Task view due-date column.
class AsanaTaskViewDueLabel extends StatelessWidget {
  const AsanaTaskViewDueLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final overdue = label == 'Overdue';
    final bg = overdue ? const Color(0xFFFFEBEE) : const Color(0xFFFFF3E0);
    final fg = overdue ? const Color(0xFFC62828) : const Color(0xFFE65100);
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
