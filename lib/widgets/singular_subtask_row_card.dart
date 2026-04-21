import 'package:flutter/material.dart';

import '../models/singular_subtask.dart';
import 'subtask_meta_line.dart';
import 'task_list_card.dart';

/// List row matching the sub-task [Card] on [TaskDetailScreen].
class SingularSubtaskRowCard extends StatelessWidget {
  const SingularSubtaskRowCard({
    super.key,
    required this.subtask,
    required this.resolveName,
    this.onTap,
  });

  final SingularSubtask subtask;
  final String Function(String assigneeKey) resolveName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body14 = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(fontSize: kLandingListCardFontSize);
    final titleStyle =
        body14.copyWith(fontWeight: FontWeight.bold);
    final secondaryStyle = body14.copyWith(fontWeight: FontWeight.w500);
    final s = subtask;
    final assigneeNamesLine = s.assigneeNamesDisplayLine(resolveName);
    final picLine = s.picDisplayName(resolveName);
    final subTag = (s.submission?.trim().toLowerCase() == 'pending')
        ? null
        : TaskListCard.buildSubmissionTag(s.submission);
    final showOverPreset = (s.changeDueReason ?? '').trim().isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    s.subtaskName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                if (subTag != null) ...[
                  const SizedBox(width: 8),
                  subTag,
                ],
              ],
            ),
            if (showOverPreset) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TaskListCard.buildOverPresetTimelineTag(),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                'Assignee(s): $assigneeNamesLine',
                style: secondaryStyle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'PIC: $picLine',
                style: secondaryStyle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SubtaskMetaLine(subtask: s),
            ),
          ],
        ),
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}
