import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/project_milestone.dart';
import '../asana_landing_screen.dart';
import 'asana_detail_widgets.dart';
import 'asana_theme.dart';

/// In-memory or saved milestone row used by create and project-detail slides.
class AsanaMilestoneDraft {
  AsanaMilestoneDraft({
    this.id,
    String description = '',
    this.achieved = false,
    int progressPercent = 0,
  }) : controller = TextEditingController(text: description),
       percentController = TextEditingController(
         text: progressPercent <= 0 ? '' : '$progressPercent',
       );

  String? id;
  bool achieved;
  final TextEditingController controller;
  final TextEditingController percentController;

  String get description => controller.text.trim();

  int get percent {
    final n = int.tryParse(percentController.text.trim());
    if (n == null) return 0;
    if (n < 0) return 0;
    if (n > 100) return 100;
    return n;
  }

  void dispose() {
    controller.dispose();
    percentController.dispose();
  }
}

int asanaMilestonePercentTotal(Iterable<AsanaMilestoneDraft> rows) {
  var total = 0;
  for (final row in rows) {
    total += row.percent;
  }
  return total;
}

int asanaMilestoneLeftoverPercent(Iterable<AsanaMilestoneDraft> rows) {
  return (100 - asanaMilestonePercentTotal(rows)).clamp(0, 100);
}

/// Null when the optional section is off or the visible steps sum to 100%.
String? asanaMilestonePercentError({
  required bool enabled,
  required List<AsanaMilestoneDraft> rows,
}) {
  if (!enabled) return null;
  final filled = rows
      .where((row) => row.description.isNotEmpty || row.percent > 0)
      .toList();
  if (filled.isEmpty) {
    return 'Add at least one milestone, and make the percentages add up to 100%.';
  }
  final total = asanaMilestonePercentTotal(rows);
  if (total != 100) {
    return 'Milestone percentages must add up to 100%. Current total is $total%.';
  }
  if (filled.any((row) => row.description.isEmpty)) {
    return 'Each milestone needs a description.';
  }
  return null;
}

const _kMilestoneAchievedLabel = 'Achieved';
const _kMilestoneNotAchievedLabel = 'Not achieved';
const _kMilestoneAchievedAcronym = 'A';
const _kMilestoneNotAchievedAcronym = 'NA';
const _kMilestoneStatusWidth = 118.0;
const _kMilestonePercentReadOnlyWidthCompact = 72.0;

/// When milestones are on, every filled step must be achieved.
bool asanaMilestonesAllAchieved({
  required bool enabled,
  required List<AsanaMilestoneDraft> rows,
}) {
  if (!enabled) return true;
  final filled = rows
      .where((row) => row.description.isNotEmpty || row.percent > 0)
      .toList();
  if (filled.isEmpty) return false;
  return filled.every((row) => row.achieved);
}

/// A later step can be achieved only when every earlier step is already achieved.
bool asanaMilestoneAchievedTappable(
  List<AsanaMilestoneDraft> rows,
  AsanaMilestoneDraft row,
) {
  final index = rows.indexOf(row);
  if (index < 0) return false;
  if (row.achieved) return true;
  return rows.take(index).every((item) => item.achieved);
}

/// Click achieved → that step and every later step become not achieved.
/// Click not achieved → allowed only when all previous steps are achieved.
List<AsanaMilestoneDraft> asanaToggleMilestoneAchieved(
  List<AsanaMilestoneDraft> rows,
  AsanaMilestoneDraft row,
) {
  final index = rows.indexOf(row);
  if (index < 0) return const [];
  final changed = <AsanaMilestoneDraft>[];
  if (row.achieved) {
    for (var i = index; i < rows.length; i++) {
      if (!rows[i].achieved) continue;
      rows[i].achieved = false;
      changed.add(rows[i]);
    }
    return changed;
  }
  if (!asanaMilestoneAchievedTappable(rows, row)) return const [];
  row.achieved = true;
  return [row];
}

class AsanaProjectMilestoneSection extends StatelessWidget {
  const AsanaProjectMilestoneSection({
    super.key,
    required this.enabled,
    required this.canEdit,
    required this.saving,
    required this.palette,
    required this.rows,
    this.onToggleEnabled,
    this.onAdd,
    this.onAchievedToggled,
    this.onRemove,
    this.onRowSubmitted,
    this.onDraftChanged,
  });

  final bool enabled;
  final bool canEdit;
  final bool saving;
  final AsanaLandingPalette palette;
  final List<AsanaMilestoneDraft> rows;
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onAdd;
  final void Function(AsanaMilestoneDraft row)? onAchievedToggled;
  final void Function(AsanaMilestoneDraft row)? onRemove;
  final void Function(AsanaMilestoneDraft row)? onRowSubmitted;
  final VoidCallback? onDraftChanged;

  @override
  Widget build(BuildContext context) {
    if (!enabled && !canEdit) return const SizedBox.shrink();
    final total = asanaMilestonePercentTotal(rows);
    final showTotalWarning = enabled && total != 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: canEdit && !saving ? onToggleEnabled : null,
              icon: Icon(
                enabled ? Icons.flag : Icons.flag_outlined,
                size: 18,
                color: enabled
                    ? Theme.of(context).colorScheme.primary
                    : kAsanaTextSecondary,
              ),
              label: Text(
                enabled ? 'Milestones' : 'Add milestones',
                style: asanaTextStyle(
                  Theme.of(context).textTheme.bodySmall,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: enabled
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
          if (enabled) ...[
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Each milestone is one project step. Enter the description and how much percent of the project it represents. The percentages must add up to 100%.',
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.bodySmall,
                      fontSize: 12,
                      color: kAsanaTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        canEdit
                            ? 'No milestones yet. Use + to add a step.'
                            : 'No milestones yet',
                        style: asanaDetailValueStyle(
                          context,
                        ).copyWith(color: kAsanaTextSecondary),
                      ),
                    )
                  else
                    for (var i = 0; i < rows.length; i++)
                      _MilestoneRow(
                        row: rows[i],
                        rows: rows,
                        index: i,
                        canEdit: canEdit,
                        saving: saving,
                        onAchievedToggled: onAchievedToggled,
                        onRemove: onRemove,
                        onRowSubmitted: onRowSubmitted,
                        onDraftChanged: onDraftChanged,
                      ),
                  if (canEdit)
                    const SizedBox(height: 10),
                  if (canEdit)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AsanaDetailCircleAddButton(
                        tooltip: 'Add milestone',
                        enabled: !saving && rows.length < 20,
                        onTap: !saving && rows.length < 20
                            ? (_) => onAdd?.call()
                            : null,
                      ),
                    ),
                  if (showTotalWarning) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Milestone percentages must add up to 100%. Current total is $total%.',
                        textAlign: TextAlign.right,
                        style: asanaTextStyle(
                          Theme.of(context).textTheme.bodySmall,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFB00020),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _milestoneOrdinalLabel(int index) {
  final n = index + 1;
  final suffix = switch (n % 100) {
    11 || 12 || 13 => 'th',
    _ => switch (n % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    },
  };
  return '$n$suffix milestone';
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.row,
    required this.rows,
    required this.index,
    required this.canEdit,
    required this.saving,
    this.onAchievedToggled,
    this.onRemove,
    this.onRowSubmitted,
    this.onDraftChanged,
  });

  final AsanaMilestoneDraft row;
  final List<AsanaMilestoneDraft> rows;
  final int index;
  final bool canEdit;
  final bool saving;
  final void Function(AsanaMilestoneDraft row)? onAchievedToggled;
  final void Function(AsanaMilestoneDraft row)? onRemove;
  final void Function(AsanaMilestoneDraft row)? onRowSubmitted;
  final VoidCallback? onDraftChanged;

  @override
  Widget build(BuildContext context) {
    final compact = AsanaTaskDetailActionStyles.isMobile(context);
    final statusLabel = row.achieved
        ? (compact ? _kMilestoneAchievedAcronym : _kMilestoneAchievedLabel)
        : (compact
              ? _kMilestoneNotAchievedAcronym
              : _kMilestoneNotAchievedLabel);
    final canToggleStatus =
        canEdit && !saving && asanaMilestoneAchievedTappable(rows, row);
    final leftWidth = compact
        ? _kMilestonePercentReadOnlyWidthCompact
        : _kMilestoneStatusWidth;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus && canEdit && !saving) {
            onRowSubmitted?.call(row);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _milestoneOrdinalLabel(index),
                style:
                    asanaTextStyle(
                      Theme.of(context).textTheme.bodySmall,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kAsanaTextSecondary,
                    ) ??
                    const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: leftWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MilestoneStatusLabel(
                      label: statusLabel,
                      tooltip: row.achieved
                          ? _kMilestoneAchievedLabel
                          : _kMilestoneNotAchievedLabel,
                      achieved: row.achieved,
                      width: leftWidth,
                      compact: compact,
                      enabled: canToggleStatus,
                      onTap: canToggleStatus
                          ? () => onAchievedToggled?.call(row)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    _percentValueRow(context),
                    if (canEdit) _removeButton(compact: compact),
                  ],
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: AsanaHoverTextField(
                  controller: row.controller,
                  canEdit: canEdit,
                  readOnly: saving,
                  showOutline: true,
                  expands: true,
                  maxLines: 8,
                  minLines: compact ? 3 : 2,
                  hintText: 'Milestone description',
                  style: asanaDetailMultilineValueStyle(context),
                ),
              ),
            ],
          ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _percentValueRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AsanaHoverTextField(
            controller: row.percentController,
            canEdit: canEdit,
            readOnly: saving,
            showOutline: true,
            maxLines: 1,
            hintText: '0',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            style: asanaDetailValueStyle(context),
            onChanged: (_) => onDraftChanged?.call(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text('%', style: asanaDetailValueStyle(context)),
        ),
      ],
    );
  }

  Widget _removeButton({required bool compact}) {
    return IconButton(
      tooltip: 'Remove milestone',
      onPressed: saving ? null : () => onRemove?.call(row),
      icon: const Icon(Icons.delete_outline, size: 16),
      color: const Color(0xFFC62828),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: compact ? 24 : 32,
        minHeight: compact ? 24 : 32,
      ),
    );
  }
}

class _MilestoneStatusLabel extends StatelessWidget {
  const _MilestoneStatusLabel({
    required this.label,
    required this.achieved,
    required this.enabled,
    required this.width,
    this.tooltip,
    this.compact = false,
    this.onTap,
  });

  final String label;
  final String? tooltip;
  final bool achieved;
  final double width;
  final bool compact;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = achieved
        ? AsanaTaskDetailActionStyles.successGreen
        : AsanaTaskDetailActionStyles.pauseAmber;
    Widget child = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 12,
            vertical: 8,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style:
                asanaTextStyle(
                  Theme.of(context).textTheme.labelLarge,
                  fontSize: 12.6,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ) ??
                const TextStyle(
                  fontSize: 12.6,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
          ),
        ),
      ),
    );
    if (compact && tooltip != null) {
      child = Tooltip(message: tooltip!, child: child);
    }
    if (!enabled || onTap == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}

/// Helper to rebuild drafts from saved Active rows without leaking controllers.
List<AsanaMilestoneDraft> asanaMilestoneDraftsFromRows(
  List<ProjectMilestone> rows,
) {
  return [
    for (final row in rows)
      AsanaMilestoneDraft(
        id: row.id,
        description: row.description,
        achieved: row.achieved,
        progressPercent: row.progressPercent,
      ),
  ];
}

void disposeAsanaMilestoneDrafts(List<AsanaMilestoneDraft> rows) {
  for (final row in rows) {
    row.dispose();
  }
}
