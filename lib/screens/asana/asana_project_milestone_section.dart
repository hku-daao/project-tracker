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

/// Share of the project completed from achieved Active milestones.
int asanaMilestoneCompletedPercent(Iterable<AsanaMilestoneDraft> rows) {
  var done = 0;
  for (final row in rows) {
    if (row.achieved) done += row.percent;
  }
  if (done < 0) return 0;
  if (done > 100) return 100;
  return done;
}

/// Short encouragement for the project-name progress line.
String asanaMilestoneProgressEncouragement(int percent) {
  if (percent <= 0) {
    return 'A clear path ahead — ready when you are.';
  }
  if (percent < 25) {
    return 'A solid start. Keep the momentum going.';
  }
  if (percent < 50) {
    return 'Good progress. You\'re well on your way.';
  }
  if (percent < 75) {
    return 'More than halfway. Stay with it.';
  }
  if (percent < 100) {
    return 'The finish is in sight. One more push.';
  }
  return 'Every milestone achieved. Well done.';
}

class AsanaSuggestedMilestone {
  const AsanaSuggestedMilestone({
    required this.description,
    required this.progressPercent,
  });

  final String description;
  final int progressPercent;
}

String asanaFormatSuggestedMilestones(
  List<AsanaSuggestedMilestone> items, {
  required bool enabled,
}) {
  if (!enabled || items.isEmpty) return 'Off';
  final buf = StringBuffer();
  for (var i = 0; i < items.length; i++) {
    if (i > 0) buf.writeln();
    buf.write(
      '${i + 1}. ${items[i].progressPercent}% — ${items[i].description}',
    );
  }
  return buf.toString();
}

List<AsanaSuggestedMilestone> asanaMilestonesFromDrafts(
  Iterable<AsanaMilestoneDraft> rows,
) {
  return [
    for (final row in rows)
      if (row.description.isNotEmpty || row.percent > 0)
        AsanaSuggestedMilestone(
          description: row.description,
          progressPercent: row.percent,
        ),
  ];
}

bool asanaSameSuggestedMilestones(
  List<AsanaSuggestedMilestone> a,
  List<AsanaSuggestedMilestone> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].progressPercent != b[i].progressPercent) return false;
    if (a[i].description.trim().toLowerCase() !=
        b[i].description.trim().toLowerCase()) {
      return false;
    }
  }
  return true;
}

List<AsanaSuggestedMilestone> asanaInferMilestonesFromPrompt(String prompt) {
  final text = prompt.trim();
  if (text.isEmpty) return const [];
  final chunks = <String>[];
  final oneIs = RegExp(
    r'(?:^|[,\.;]\s*)(?:(?:the\s+)?(?:first|second|third|fourth|fifth|last)|one|another)\s+is\s+',
    caseSensitive: false,
  );
  final oneMatches = oneIs.allMatches(text).toList();
  if (oneMatches.length >= 2) {
    for (var i = 0; i < oneMatches.length; i++) {
      final start = oneMatches[i].end;
      final end = i + 1 < oneMatches.length
          ? oneMatches[i + 1].start
          : text.length;
      final chunk = text.substring(start, end).replaceAll(RegExp(r'[,\.;\s]+$'), '').trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
    }
  }
  if (chunks.length < 2) {
    final numbered = RegExp(
      r'(?:^|\n)\s*(?:\d+[\.\)]|\-|\*)\s+(.+)',
      multiLine: true,
    );
    chunks
      ..clear()
      ..addAll(
        numbered
            .allMatches(text)
            .map((m) => m.group(1)?.trim() ?? '')
            .where((s) => s.isNotEmpty),
      );
  }
  if (chunks.length < 2) return const [];
  return asanaParseSuggestedMilestones([
    for (final chunk in chunks.take(20)) {'description': chunk},
  ]);
}

List<AsanaSuggestedMilestone> asanaParseSuggestedMilestones(Object? raw) {
  if (raw is String && raw.trim().isNotEmpty) {
    return asanaInferMilestonesFromPrompt(raw);
  }
  if (raw is! List) return const [];
  final parsed = <({String description, int? percent})>[];
  for (final item in raw) {
    if (item is String) {
      final description = item.trim();
      if (description.isNotEmpty) {
        parsed.add((description: description, percent: null));
      }
      continue;
    }
    if (item is! Map) continue;
    final description =
        (item['description'] ?? item['name'] ?? item['text'])
            ?.toString()
            .trim() ??
        '';
    if (description.isEmpty) continue;
    final rawPercent = item['progressPercent'] ?? item['percent'];
    int? percent;
    if (rawPercent is int) {
      percent = rawPercent;
    } else if (rawPercent is num) {
      percent = rawPercent.round();
    } else if (rawPercent is String) {
      percent = int.tryParse(rawPercent.trim());
    }
    parsed.add((description: description, percent: percent));
  }
  if (parsed.isEmpty) return const [];
  if (parsed.length > 20) {
    parsed.removeRange(20, parsed.length);
  }

  final items = <AsanaSuggestedMilestone>[];
  final missingCount = parsed.where((row) => row.percent == null).length;
  if (missingCount == 0) {
    final percents = [
      for (final row in parsed) row.percent!.clamp(0, 100),
    ];
    final sum = percents.fold<int>(0, (total, value) => total + value);
    if (sum != 100 && percents.isNotEmpty) {
      percents[percents.length - 1] = (percents.last + (100 - sum)).clamp(
        0,
        100,
      );
    }
    for (var i = 0; i < parsed.length; i++) {
      items.add(
        AsanaSuggestedMilestone(
          description: parsed[i].description,
          progressPercent: percents[i],
        ),
      );
    }
    return items;
  }

  var leftover = 100;
  for (final row in parsed) {
    if (row.percent != null) leftover -= row.percent!.clamp(0, 100);
  }
  leftover = leftover.clamp(0, 100);
  var remainingMissing = missingCount;
  for (final row in parsed) {
    if (row.percent != null) {
      items.add(
        AsanaSuggestedMilestone(
          description: row.description,
          progressPercent: row.percent!.clamp(0, 100),
        ),
      );
      continue;
    }
    remainingMissing--;
    final share = remainingMissing == 0
        ? leftover
        : (leftover / (remainingMissing + 1)).floor();
    leftover -= share;
    items.add(
      AsanaSuggestedMilestone(
        description: row.description,
        progressPercent: share,
      ),
    );
  }
  return items;
}

/// Updates [drafts] to match [items]. Returns leftover rows that were removed.
List<AsanaMilestoneDraft> asanaReplaceMilestoneDrafts({
  required List<AsanaMilestoneDraft> drafts,
  required List<AsanaSuggestedMilestone> items,
}) {
  final leftover = <AsanaMilestoneDraft>[];
  while (drafts.length > items.length) {
    leftover.add(drafts.removeLast());
  }
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (i < drafts.length) {
      final row = drafts[i];
      final sameDescription =
          row.description.toLowerCase() == item.description.toLowerCase();
      row.controller.text = item.description;
      row.percentController.text = '${item.progressPercent}';
      if (!sameDescription) row.achieved = false;
    } else {
      drafts.add(
        AsanaMilestoneDraft(
          description: item.description,
          progressPercent: item.progressPercent,
        ),
      );
    }
  }
  return leftover;
}

/// Progress line shown under the project name when milestones are on.
class AsanaProjectMilestoneProgressLine extends StatelessWidget {
  const AsanaProjectMilestoneProgressLine({
    super.key,
    required this.enabled,
    required this.rows,
  });

  final bool enabled;
  final List<AsanaMilestoneDraft> rows;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final percent = asanaMilestoneCompletedPercent(rows);
    final complete = percent >= 100;
    final percentColor = complete
        ? const Color(0xFF1B7A4E)
        : percent <= 0
        ? kAsanaTextSecondary
        : Theme.of(context).colorScheme.primary;
    const fontSize = 13 * 1.3;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$percent% complete',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodySmall,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: percentColor,
                  ),
                ),
                TextSpan(
                  text: '  ·  ${asanaMilestoneProgressEncouragement(percent)}',
                  style: asanaTextStyle(
                    Theme.of(context).textTheme.bodySmall,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                    color: kAsanaTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFFE6E7E8)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      widthFactor: percent / 100,
                      heightFactor: 1,
                      child: ColoredBox(color: percentColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    this.descriptionSuggestion,
    this.percentSuggestion,
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
  final Widget Function(int index)? descriptionSuggestion;
  final Widget Function(int index)? percentSuggestion;

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
                        descriptionSuggestion: descriptionSuggestion,
                        percentSuggestion: percentSuggestion,
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
    this.descriptionSuggestion,
    this.percentSuggestion,
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
  final Widget Function(int index)? descriptionSuggestion;
  final Widget Function(int index)? percentSuggestion;

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
                    if (percentSuggestion != null) percentSuggestion!(index),
                    if (canEdit) _removeButton(compact: compact),
                  ],
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    if (descriptionSuggestion != null)
                      descriptionSuggestion!(index),
                  ],
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
