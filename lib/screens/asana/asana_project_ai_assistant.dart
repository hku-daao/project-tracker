import '../../utils/hk_time.dart';
import 'asana_project_milestone_section.dart';
import 'asana_task_ai_assistant.dart';

/// Current project form values + staff list (for LLM context and name resolution).
class AsanaProjectAiFormSnapshot {
  const AsanaProjectAiFormSnapshot({
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
    this.websiteAttachments = const [],
    this.hasMilestone = false,
    this.milestones = const [],
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
  final bool hasMilestone;
  final List<AsanaSuggestedMilestone> milestones;

  String buildLlmContext() {
    final buf = StringBuffer()
      ..writeln('Today (Hong Kong): ${_ymd(HkTime.todayDateOnlyHk())}')
      ..writeln('Current project form values:')
      ..writeln('- name: ${name.isEmpty ? "(empty)" : name}')
      ..writeln(
        '- description: ${description.isEmpty ? "(empty)" : description}',
      )
      ..writeln(
        '- comment (draft, posted on save): ${commentDraft.isEmpty ? "(empty)" : commentDraft}',
      )
      ..writeln('- status: ${status.isEmpty ? "(empty)" : status}')
      ..writeln(
        '- start date: ${startDate == null ? "(empty)" : _ymd(startDate!)}',
      )
      ..writeln('- due date: ${dueDate == null ? "(empty)" : _ymd(dueDate!)}')
      ..writeln(
        '- assignees: ${assigneesLabel.isEmpty ? "(none)" : assigneesLabel}',
      )
      ..writeln('- PIC: ${picLabel.isEmpty ? "(none)" : picLabel}')
      ..writeln(
        '- milestones: ${asanaFormatSuggestedMilestones(milestones, enabled: hasMilestone)}',
      );

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
    buf.writeln(
      'Milestones: optional project steps. Each has a description and an integer percent of the whole project. Percents must add up to 100%. Suggest them when the prompt lists steps, phases, deliverables, or named pieces of work.',
    );
    return buf.toString();
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Callbacks when user adopts a project AI suggestion.
class AsanaProjectAiApply {
  const AsanaProjectAiApply({
    required this.applyName,
    required this.applyDescription,
    required this.applyAssignees,
    required this.applyPic,
    required this.applyStatus,
    required this.applyStartDate,
    required this.applyDueDate,
    required this.applyComment,
    required this.applyWebsiteLink,
    required this.ensureMilestoneSlots,
    required this.applyMilestoneDescription,
    required this.applyMilestonePercent,
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
  final void Function(int count) ensureMilestoneSlots;
  final void Function(int index, String description) applyMilestoneDescription;
  final void Function(int index, int percent) applyMilestonePercent;
}

/// Validates LLM JSON and builds adoptable lines for project fields.
class AsanaProjectAiSuggestionBuilder {
  static List<AsanaTaskAiSuggestionLine> build({
    required Map<String, dynamic> raw,
    required AsanaProjectAiFormSnapshot form,
    required AsanaProjectAiApply apply,
    String userPrompt = '',
  }) {
    final lines = <AsanaTaskAiSuggestionLine>[];

    final name = _str(raw['name']);
    if (name != null &&
        name.isNotEmpty &&
        !_sameNormalizedText(name, form.name)) {
      lines.add(
        AsanaTaskAiSuggestionLine.adopt(
          fieldKey: AsanaTaskAiFieldKey.taskName,
          fieldLabel: 'Name',
          currentValue: AsanaTaskAiSuggestionLine.displayCurrent(form.name),
          suggestedText: name,
          onAdopt: () => apply.applyName(name),
        ),
      );
    }

    final desc = _str(raw['description']);
    if (desc != null &&
        desc.isNotEmpty &&
        !_sameNormalizedText(desc, form.description)) {
      lines.add(
        AsanaTaskAiSuggestionLine.adopt(
          fieldKey: AsanaTaskAiFieldKey.description,
          fieldLabel: 'Description',
          currentValue: AsanaTaskAiSuggestionLine.displayCurrent(
            form.description,
          ),
          suggestedText: desc,
          onAdopt: () => apply.applyDescription(desc),
        ),
      );
    }

    final comment = _str(raw['comment']);
    if (comment != null &&
        comment.isNotEmpty &&
        !_sameNormalizedText(comment, form.commentDraft)) {
      lines.add(
        AsanaTaskAiSuggestionLine.adopt(
          fieldKey: AsanaTaskAiFieldKey.comment,
          fieldLabel: 'Comment',
          currentValue: AsanaTaskAiSuggestionLine.displayCurrent(
            form.commentDraft,
          ),
          suggestedText: comment,
          onAdopt: () => apply.applyComment(comment),
        ),
      );
    }

    final names = _stringList(raw['assigneeNames']);
    final resolvedAssignees = <String>{};
    if (names.isNotEmpty) {
      final missing = <String>[];
      for (final n in names) {
        final ids = _matchStaffIds(n, form.staff);
        if (ids.isEmpty) {
          missing.add(n);
        } else {
          resolvedAssignees.addAll(ids);
        }
      }
      if (missing.isNotEmpty) {
        lines.add(
          AsanaTaskAiSuggestionLine.info(
            'Could not match assignee(s): ${missing.join(', ')}',
            fieldKey: AsanaTaskAiFieldKey.assignees,
          ),
        );
      }
    }

    final links = _websiteLinksList(raw['websiteLinks']);
    var linkIndex = 0;
    for (final link in links) {
      if (_hasWebsiteUrl(form, link.url)) continue;
      final idx = linkIndex++;
      final display = link.description.trim().isEmpty
          ? link.url
          : '${link.url}\n${link.description.trim()}';
      lines.add(
        AsanaTaskAiSuggestionLine.adopt(
          fieldKey: AsanaTaskAiFieldKey.websiteLink,
          linkIndex: idx,
          fieldLabel: 'Website link',
          currentValue: '(none)',
          suggestedText: display,
          onAdopt: () => apply.applyWebsiteLink(link.url, link.description),
        ),
      );
    }

    final picNames = _stringList(raw['picNames']);
    final resolvedPics = <String>{};
    if (picNames.isNotEmpty) {
      final missing = <String>[];
      for (final n in picNames) {
        final ids = _matchStaffIds(n, form.staff);
        if (ids.isEmpty) {
          missing.add(n);
        } else {
          resolvedPics.addAll(ids);
        }
      }
      if (missing.isNotEmpty) {
        lines.add(
          AsanaTaskAiSuggestionLine.info(
            'Could not match PIC(s): ${missing.join(', ')}',
            fieldKey: AsanaTaskAiFieldKey.pic,
          ),
        );
      }
    }

    var visibleAssignees = Set<String>.from(resolvedAssignees);
    var suggestedPics = Set<String>.from(resolvedPics);
    if (AsanaTaskAiSuggestionBuilder.singleNamedAssigneeIsPicOnly(
      resolvedAssignees: resolvedAssignees,
      proposedPicId: suggestedPics.length == 1 ? suggestedPics.single : null,
      assigneeNamesProvided: names.isNotEmpty,
    )) {
      suggestedPics = {resolvedAssignees.single};
      visibleAssignees = <String>{};
    } else {
      visibleAssignees.removeAll(suggestedPics);
    }

    if (names.isNotEmpty &&
        visibleAssignees.isNotEmpty &&
        !_sameIdSet(visibleAssignees, form.selectedAssigneeIds)) {
      final label = _staffNamesForIds(visibleAssignees.toList(), form.staff);
      lines.add(
        AsanaTaskAiSuggestionLine.adopt(
          fieldKey: AsanaTaskAiFieldKey.assignees,
          fieldLabel: 'Assignees',
          currentValue: AsanaTaskAiSuggestionLine.displayCurrent(
            form.assigneesLabel,
          ),
          suggestedText: label,
          onAdopt: () => apply.applyAssignees(visibleAssignees),
        ),
      );
    }

    if (suggestedPics.isNotEmpty &&
        !_sameIdSet(suggestedPics, form.selectedPicAssigneeIds)) {
      final label = _staffNamesForIds(suggestedPics.toList(), form.staff);
      lines.add(
        AsanaTaskAiSuggestionLine.adopt(
          fieldKey: AsanaTaskAiFieldKey.pic,
          fieldLabel: 'PIC',
          currentValue: AsanaTaskAiSuggestionLine.displayCurrent(form.picLabel),
          suggestedText: label,
          onAdopt: () => apply.applyPic(suggestedPics),
        ),
      );
    }

    final status = _str(raw['status']);
    if (status != null && status.isNotEmpty) {
      final normalized = _parseProjectStatus(status);
      if (normalized == null) {
        lines.add(
          AsanaTaskAiSuggestionLine.info(
            'Status "$status" was not recognized (use Not started, In progress, or Completed).',
            fieldKey: AsanaTaskAiFieldKey.projectStatus,
          ),
        );
      } else if (normalized != form.status.trim()) {
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.projectStatus,
            fieldLabel: 'Status',
            currentValue: form.status.isEmpty ? '(empty)' : form.status,
            suggestedText: normalized,
            onAdopt: () => apply.applyStatus(normalized),
          ),
        );
      }
    }

    DateTime? proposedStart;
    DateTime? proposedDue;
    final startRaw = _str(raw['startDate']);
    final dueRaw = _str(raw['dueDate']);
    if (startRaw != null) proposedStart = _parseYmd(startRaw);
    if (dueRaw != null) proposedDue = _parseYmd(dueRaw);

    var datesBlocked = false;
    if (proposedStart != null &&
        proposedDue != null &&
        _dateOnly(proposedStart).isAfter(_dateOnly(proposedDue))) {
      datesBlocked = true;
      lines.add(
        const AsanaTaskAiSuggestionLine.info(
          'Start and due dates were not suggested because start would be after due.',
          fieldKey: AsanaTaskAiFieldKey.startDate,
        ),
      );
    }

    if (!datesBlocked) {
      final start = proposedStart;
      if (start != null && !_sameDateOnly(start, form.startDate)) {
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.startDate,
            fieldLabel: 'Start date',
            currentValue: form.startDate == null
                ? '(empty)'
                : _formatDisplayDate(form.startDate!),
            suggestedText: _formatDisplayDate(start),
            onAdopt: () => apply.applyStartDate(start),
          ),
        );
      }

      final due = proposedDue;
      if (due != null && !_sameDateOnly(due, form.dueDate)) {
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.dueDate,
            fieldLabel: 'Due date',
            currentValue: form.dueDate == null
                ? '(empty)'
                : _formatDisplayDate(form.dueDate!),
            suggestedText: _formatDisplayDate(due),
            onAdopt: () => apply.applyDueDate(due),
          ),
        );
      }
    }

    var suggestedMilestones = asanaParseSuggestedMilestones(
      raw['milestones'] ?? raw['milestone'] ?? raw['steps'],
    );
    if (suggestedMilestones.isEmpty && userPrompt.trim().isNotEmpty) {
      suggestedMilestones = asanaInferMilestonesFromPrompt(userPrompt);
    }
    if (suggestedMilestones.isNotEmpty) {
      apply.ensureMilestoneSlots(suggestedMilestones.length);
      for (var i = 0; i < suggestedMilestones.length; i++) {
        final item = suggestedMilestones[i];
        final current = i < form.milestones.length ? form.milestones[i] : null;
        if (current == null ||
            current.description.trim().toLowerCase() !=
                item.description.trim().toLowerCase()) {
          lines.add(
            AsanaTaskAiSuggestionLine.adopt(
              fieldKey: AsanaTaskAiFieldKey.milestoneDescription,
              linkIndex: i,
              fieldLabel: 'Milestone ${i + 1} description',
              currentValue: AsanaTaskAiSuggestionLine.displayCurrent(
                current?.description ?? '',
              ),
              suggestedText: item.description,
              onAdopt: () =>
                  apply.applyMilestoneDescription(i, item.description),
            ),
          );
        }
        if (current == null || current.progressPercent != item.progressPercent) {
          lines.add(
            AsanaTaskAiSuggestionLine.adopt(
              fieldKey: AsanaTaskAiFieldKey.milestonePercent,
              linkIndex: i,
              fieldLabel: 'Milestone ${i + 1} percentage',
              currentValue: current == null
                  ? '(empty)'
                  : '${current.progressPercent}%',
              suggestedText: '${item.progressPercent}%',
              onAdopt: () =>
                  apply.applyMilestonePercent(i, item.progressPercent),
            ),
          );
        }
      }
    }

    final hasAdopt = lines.any((l) => l.adoptable);
    if (!hasAdopt && lines.isEmpty) {
      return [
        const AsanaTaskAiSuggestionLine.info(
          'No project fields could be inferred from this prompt. Try being more specific.',
        ),
      ];
    }
    if (!hasAdopt && lines.every((l) => !l.adoptable)) {
      lines.add(
        const AsanaTaskAiSuggestionLine.info(
          'Nothing to apply — review the notes above.',
        ),
      );
    }

    return lines;
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    return v.toString().trim();
  }

  static List<String> _stringList(dynamic v) {
    if (v is! List) return [];
    return v
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static List<({String url, String description})> _websiteLinksList(dynamic v) {
    if (v is! List) return [];
    final out = <({String url, String description})>[];
    for (final item in v) {
      if (item is! Map) continue;
      final url = _str(item['url']);
      if (url == null || url.isEmpty) continue;
      final desc = _str(item['description']) ?? '';
      out.add((url: _normalizeUrlForDisplay(url), description: desc));
    }
    return out;
  }

  static bool _hasWebsiteUrl(AsanaProjectAiFormSnapshot form, String url) {
    final n = _normalizeUrl(url);
    return form.websiteAttachments.any((w) => _normalizeUrl(w.url) == n);
  }

  static String _normalizeUrl(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return s;
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    if (s.startsWith('http://')) s = s.substring(7);
    if (s.startsWith('https://')) s = s.substring(8);
    return s;
  }

  static String _normalizeUrlForDisplay(String raw) {
    final t = raw.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    return 'https://$t';
  }

  static List<String> _matchStaffIds(
    String name,
    List<({String id, String name})> staff,
  ) {
    final q = name.trim().toLowerCase();
    if (q.isEmpty) return [];

    final exact = <String>[];
    for (final s in staff) {
      if (s.name.trim().toLowerCase() == q) exact.add(s.id);
    }
    if (exact.isNotEmpty) return exact;

    final matches = <String>[];
    for (final s in staff) {
      final n = s.name.trim().toLowerCase();
      final parts = n.split(RegExp(r'\s+'));
      if (parts.any((p) => p == q || p.startsWith(q)) || n.contains(q)) {
        matches.add(s.id);
      }
    }
    return matches;
  }

  static String _staffNamesForIds(
    List<String> ids,
    List<({String id, String name})> staff,
  ) {
    return ids
        .map((id) {
          for (final s in staff) {
            if (s.id == id) return s.name.trim();
          }
          return id;
        })
        .join(', ');
  }

  static String? _parseProjectStatus(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.contains('complete')) return 'Completed';
    if (s.contains('progress')) return 'In progress';
    if (s.contains('not') && s.contains('start')) return 'Not started';
    return null;
  }

  static DateTime? _parseYmd(String raw) {
    final t = raw.trim();
    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (m != null) {
      final year = int.parse(m.group(1)!);
      final month = int.parse(m.group(2)!);
      final day = int.parse(m.group(3)!);
      final parsed = DateTime(year, month, day);
      if (parsed.year != year || parsed.month != month || parsed.day != day) {
        return null;
      }
      return parsed;
    }
    try {
      final d = DateTime.parse(t);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _sameNormalizedText(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  static bool _sameDateOnly(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return _dateOnly(a) == _dateOnly(b);
  }

  static bool _sameIdSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.every(b.contains);

  static String _formatDisplayDate(DateTime d) =>
      HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
}
