import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/subproject_record.dart';
import '../asana_landing_screen.dart';
import 'asana_detail_widgets.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

class AsanaProjectSubprojectSection extends StatelessWidget {
  const AsanaProjectSubprojectSection({
    super.key,
    required this.projectId,
    required this.canEdit,
    required this.saving,
    required this.palette,
    this.onCreate,
    this.onOpen,
  });

  final String projectId;
  final bool canEdit;
  final bool saving;
  final AsanaLandingPalette palette;
  final VoidCallback? onCreate;
  final void Function(String subprojectId)? onOpen;

  @override
  Widget build(BuildContext context) {
    final rows = context.watch<AppState>().subprojectsForProject(projectId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AsanaDetailSectionHeader(
          title: 'Sub-projects',
          showAddButton: canEdit,
          addTooltip: 'Create sub-project',
          onAdd: canEdit && !saving && onCreate != null
              ? (_) => onCreate!()
              : null,
          addEnabled: canEdit && !saving && onCreate != null,
        ),
        if (rows.isEmpty)
          const SizedBox.shrink()
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                for (final row in rows)
                  _SubprojectRow(
                    row: row,
                    palette: palette,
                    enabled: !saving,
                    onOpen: onOpen == null ? null : () => onOpen!(row.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SubprojectRow extends StatelessWidget {
  const _SubprojectRow({
    required this.row,
    required this.palette,
    required this.enabled,
    this.onOpen,
  });

  final SubprojectRecord row;
  final AsanaLandingPalette palette;
  final bool enabled;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final completed = row.isCompleted;
    final nameStyle = asanaTableRowNameStyle(context, completed: completed);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: palette.tableColors.subtaskRow,
        child: InkWell(
          onTap: enabled && onOpen != null ? onOpen : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            child: Row(
              children: [
                const AsanaRowTypeLetter(letter: 'SP'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row.name.trim().isEmpty
                        ? '(Unnamed sub-project)'
                        : row.name,
                    style: nameStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                AsanaStatusChip(
                  status: row.isPaused ? 'Paused' : row.status,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
