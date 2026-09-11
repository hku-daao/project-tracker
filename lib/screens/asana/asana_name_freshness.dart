import 'package:flutter/material.dart';

import '../../utils/hk_time.dart';
import 'asana_theme.dart';

/// Recency of a project / task / sub-task name cell.
enum AsanaNameFreshness { none, created, updated }

/// Created today wins over updated today so both badges never show together.
AsanaNameFreshness asanaNameFreshness({
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  if (_isHkCalendarToday(createdAt)) return AsanaNameFreshness.created;
  if (_isHkCalendarToday(updatedAt)) return AsanaNameFreshness.updated;
  return AsanaNameFreshness.none;
}

bool _isHkCalendarToday(DateTime? instant) {
  if (instant == null) return false;
  return HkTime.formatInstantAsHk(instant, 'yyyy-MM-dd') ==
      HkTime.todayDateOnlyForDb();
}

/// Name text with a top-right recency chip, matching due-date Overdue placement.
class AsanaNameWithFreshness extends StatelessWidget {
  const AsanaNameWithFreshness({
    super.key,
    required this.name,
    required this.style,
    this.createdAt,
    this.updatedAt,
    this.maxLines = 1,
    this.softWrap,
  });

  final String name;
  final TextStyle? style;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int maxLines;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final kind = asanaNameFreshness(createdAt: createdAt, updatedAt: updatedAt);
    final text = Text(
      name,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      softWrap: softWrap,
    );
    if (kind == AsanaNameFreshness.none) return text;

    final created = kind == AsanaNameFreshness.created;
    final label = created ? 'NEW' : 'Updated';
    final bg = created ? const Color(0xFFE3F2FD) : const Color(0xFFF3E5F5);
    final fg = created ? const Color(0xFF1565C0) : const Color(0xFF7B1FA2);
    final singleLine = maxLines <= 1;
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.only(right: created ? 36 : 56),
            child: text,
          ),
        ),
        Positioned(
          top: -3,
          right: 0,
          child: Container(
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
          ),
        ),
      ],
    );
    if (!singleLine) return stack;
    return SizedBox(height: 32, child: stack);
  }
}
