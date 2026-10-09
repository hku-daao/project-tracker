import '../../utils/hk_time.dart';
import 'asana_project_ai_assistant.dart';
import 'asana_task_ai_assistant.dart';

/// Current sub-project form values, parent project context, and staff list.
class AsanaSubprojectAiFormSnapshot {
  const AsanaSubprojectAiFormSnapshot({
    required this.name,
    required this.description,
    required this.commentDraft,
    required this.status,
    required this.startDate,
    required this.dueDate,
    required this.assigneesLabel,
    required this.picLabel,
    required this.staff,
    required this.selectedAssigneeIds,
    required this.selectedPicAssigneeIds,
    required this.parentProjectContext,
    this.websiteAttachments = const [],
    this.statusLocked = false,
  });

  final String name;
  final String description;
  final String commentDraft;
  final String status;
  final DateTime? startDate;
  final DateTime? dueDate;
  final String assigneesLabel;
  final String picLabel;
  final List<({String id, String name})> staff;
  final Set<String> selectedAssigneeIds;
  final Set<String> selectedPicAssigneeIds;
  final List<({String url, String description})> websiteAttachments;
  final String parentProjectContext;

  /// True while the sub-project is paused. Status cannot be adopted until resume.
  final bool statusLocked;

  String buildLlmContext() {
    final buf = StringBuffer()
      ..writeln('Today (Hong Kong): ${_ymd(HkTime.todayDateOnlyHk())}')
      ..writeln(AsanaTaskAiFormSnapshot.relativeDateInstruction())
      ..writeln('Parent project details (read-only context):')
      ..writeln(
        parentProjectContext.trim().isEmpty
            ? '(no details provided)'
            : parentProjectContext.trim(),
      )
      ..writeln('\nCurrent sub-project form values:')
      ..writeln('- name: ${name.isEmpty ? "(empty)" : name}')
      ..writeln(
        '- description: ${description.isEmpty ? "(empty)" : description}',
      )
      ..writeln(
        '- comment (draft, posted on save): ${commentDraft.isEmpty ? "(empty)" : commentDraft}',
      )
      ..writeln(
        statusLocked
            ? '- status: Paused (locked; do not suggest a status change)'
            : '- status: ${status.isEmpty ? "(empty)" : status}',
      )
      ..writeln(
        '- start date: ${startDate == null ? "(empty)" : _ymd(startDate!)}',
      )
      ..writeln('- due date: ${dueDate == null ? "(empty)" : _ymd(dueDate!)}')
      ..writeln(
        '- assignees: ${assigneesLabel.isEmpty ? "(none)" : assigneesLabel}',
      )
      ..writeln('- PIC: ${picLabel.isEmpty ? "(none)" : picLabel}');

    if (websiteAttachments.isNotEmpty) {
      buf.writeln('Current website link attachments:');
      for (final w in websiteAttachments) {
        buf.writeln(
          '- ${w.url} — ${w.description.isEmpty ? "(no description)" : w.description}',
        );
      }
    } else {
      buf.writeln('Current website link attachments: (none)');
    }

    if (staff.isNotEmpty) {
      buf.writeln('Available staff: ${staff.map((s) => s.name).join('; ')}');
    }
    buf.writeln('Status options: Not started, In progress, Completed');
    return buf.toString();
  }

  AsanaProjectAiFormSnapshot asProjectSnapshot() {
    return AsanaProjectAiFormSnapshot(
      name: name,
      description: description,
      commentDraft: commentDraft,
      status: status,
      startDate: startDate,
      dueDate: dueDate,
      assigneesLabel: assigneesLabel,
      picLabel: picLabel,
      staff: staff,
      selectedAssigneeIds: selectedAssigneeIds,
      selectedPicAssigneeIds: selectedPicAssigneeIds,
      websiteAttachments: websiteAttachments,
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Callbacks when the user adopts a sub-project AI suggestion.
class AsanaSubprojectAiApply {
  const AsanaSubprojectAiApply({
    required this.applyName,
    required this.applyDescription,
    required this.applyAssignees,
    required this.applyPic,
    required this.applyStatus,
    required this.applyStartDate,
    required this.applyDueDate,
    required this.applyComment,
    required this.applyWebsiteLink,
  });

  final void Function(String name) applyName;
  final void Function(String description) applyDescription;
  final void Function(Set<String> assigneeIds) applyAssignees;
  final void Function(Set<String> picAssigneeIds) applyPic;
  final void Function(String status) applyStatus;
  final void Function(DateTime start) applyStartDate;
  final void Function(DateTime due) applyDueDate;
  final void Function(String comment) applyComment;
  final void Function(String url, String description) applyWebsiteLink;

  AsanaProjectAiApply asProjectApply() {
    return AsanaProjectAiApply(
      applyName: applyName,
      applyDescription: applyDescription,
      applyAssignees: applyAssignees,
      applyPic: applyPic,
      applyStatus: applyStatus,
      applyStartDate: applyStartDate,
      applyDueDate: applyDueDate,
      applyComment: applyComment,
      applyWebsiteLink: applyWebsiteLink,
      ensureMilestoneSlots: (_) {},
      applyMilestoneDescription: (_, _) {},
      applyMilestonePercent: (_, _) {},
    );
  }
}

/// Validates LLM JSON and builds adoptable lines for sub-project fields.
class AsanaSubprojectAiSuggestionBuilder {
  static List<AsanaTaskAiSuggestionLine> build({
    required Map<String, dynamic> raw,
    required AsanaSubprojectAiFormSnapshot form,
    required AsanaSubprojectAiApply apply,
  }) {
    final lines = AsanaProjectAiSuggestionBuilder.build(
      raw: raw,
      form: form.asProjectSnapshot(),
      apply: apply.asProjectApply(),
      suggestMilestones: false,
      nothingInferredMessage:
          'No sub-project fields could be inferred from this prompt. Try being more specific.',
    );
    if (!form.statusLocked) return lines;
    final filtered = lines
        .where((line) => line.fieldKey != AsanaTaskAiFieldKey.projectStatus)
        .toList();
    if (filtered.isNotEmpty) return filtered;
    return [
      const AsanaTaskAiSuggestionLine.info(
        'No sub-project fields could be inferred from this prompt. Try being more specific.',
      ),
    ];
  }
}
