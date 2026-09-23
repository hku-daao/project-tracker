import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/local_llm_config.dart';

/// Task AI assistant — HKU IT Vertex AI Qwen (OpenAI-compatible chat completions).
///
/// Configure via [LocalLlmConfig] and `scripts/local_llm.env`.
/// Build with `./scripts/run_offline_dev.sh` or:
/// ```bash
/// --dart-define=LOCAL_LLM_BASE_URL=https://api.hku.hk/vertexai
/// --dart-define=LOCAL_LLM_MODEL=qwen/qwen3-next-80b-a3b-instruct-maas
/// --dart-define=LOCAL_LLM_API_KEY=your-primary-key
/// --dart-define=LOCAL_LLM_AUTH=apim
/// ```
class LlmService {
  LlmService._();

  static bool get isConfigured => LocalLlmConfig.isConfigured;

  static String get _effectiveModel => LocalLlmConfig.model.trim();

  static String get _missingConfigMessage {
    final missing = <String>[];
    if (LocalLlmConfig.authRequiresKey &&
        LocalLlmConfig.apiKey.trim().isEmpty) {
      missing.add('LOCAL_LLM_API_KEY (or secrets/internal_llm_api_key.txt)');
    }
    if (LocalLlmConfig.model.trim().isEmpty) {
      missing.add('LOCAL_LLM_MODEL');
    }
    if (LocalLlmConfig.baseUrl.trim().isEmpty) {
      missing.add('LOCAL_LLM_BASE_URL');
    }
    return 'Missing ${missing.join(', ')}. See scripts/local_llm.env.example '
        'and run ./scripts/run_offline_dev.sh';
  }

  /// Asks the model for a short title and longer description (JSON).
  static Future<({String title, String description})> suggestTitleDescription({
    required String userPrompt,
    String? extraContext,
  }) async {
    if (!isConfigured) {
      throw StateError(_missingConfigMessage);
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    final ctx = extraContext?.trim();
    final system = StringBuffer()
      ..writeln(
        'You draft items for a workplace project tracker. '
        'Reply with ONLY a single JSON object (no markdown, no code fences): '
        '{"title":"...","description":"..."}. '
        'title: one short line. description: plain text for assignees; may use newlines.',
      );
    if (ctx != null && ctx.isNotEmpty) {
      system.writeln('Context:\n$ctx');
    }

    final body = jsonEncode({
      'model': _effectiveModel,
      'messages': [
        {'role': 'system', 'content': system.toString()},
        {'role': 'user', 'content': trimmed},
      ],
      'temperature': 0.35,
    });

    final map = await _chatCompletionJsonObject(body);
    final parsed = _titleDescriptionFromMap(map);
    if (parsed == null) {
      throw FormatException(
        'Could not parse title/description JSON from model.',
      );
    }
    return parsed;
  }

  static ({String title, String description})? _titleDescriptionFromMap(
    Map<String, dynamic> map,
  ) {
    final t = map['title'];
    final d = map['description'];
    if (t is! String || d is! String) return null;
    return (title: t.trim(), description: d.trim());
  }

  /// Structured task-field suggestions for the Asana create/edit slide.
  static Future<Map<String, dynamic>> suggestAsanaTaskDraft({
    required String userPrompt,
    required String formContext,
  }) async {
    if (!isConfigured) {
      throw StateError(_missingConfigMessage);
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    const system = '''
You help users fill a task form in a workplace project tracker.
Reply with ONLY one JSON object (no markdown, no code fences).

Schema:
{
  "related": true or false,
  "message": "optional short note when nothing can be suggested",
  "overallComment": "when you suggest any field change: 1-3 sentences summarizing what you inferred and what the user can adopt (required if any name/description/comment/project/assignees/pic/priority/commencementStatus/complexity/dates/recurrence/websiteLinks are set)",
  "name": "string or null",
  "description": "string or null",
  "comment": "comment body for the Comments field (posted when the user saves), or null",
  "projectName": "exact name from available projects list, or null",
  "assigneeNames": ["names from available staff list"] or [],
  "picName": "one staff name, or null",
  "priority": "Standard" or "URGENT" or null,
  "commencementStatus": "Commenced" or "To be commenced" or null,
  "complexity": "Low" or "Medium" or "High",
  "startDate": "YYYY-MM-DD" or null,
  "dueDate": "YYYY-MM-DD" or null,
  "reason": "reason for needing a long time to complete the task, or null",
  "websiteLinks": [
    { "url": "https://...", "description": "short label for the link" }
  ] or [],
  "recurrence": null or {
    "enabled": true or false,
    "frequency": "Daily" or "Weekly" or "Monthly" or "Yearly",
    "interval": 1,
    "dailyMode": "everyNDays" or "everyWeekday" or null,
    "weeklyWeekdays": ["Monday", "Tuesday"] or [],
    "monthlyMode": "dayOfMonth" or "nthWeekday" or null,
    "monthDay": 15,
    "weekdayNth": "First" or "Second" or "Third" or "Fourth" or "Last" or null,
    "weekday": "Monday" or null,
    "yearlyMode": "monthDay" or "nthWeekdayOfMonth" or null,
    "yearlyMonth": "January" or 1 or null,
    "workingDays": 4,
    "startAt": "YYYY-MM-DD" or null,
    "endMode": "byDate" or "afterCount" or null,
    "endBy": "YYYY-MM-DD" or null,
    "endAfterCount": 10
  }
}

Rules:
- The user is already working inside a task create/edit slide. Treat every prompt as an attempt to fill or improve this task form. Always set "related": true.
- Always try to suggest at least one useful field. Prefer name and description when the prompt contains task details; if the prompt is vague, make a best-effort improvement based on the prompt plus current form values.
- For optional structured fields (project, assignees, PIC, priority, commencementStatus, dates, reason, websiteLinks, recurrence), suggest them when the prompt mentions or implies them. Use null or omit fields you cannot infer.
- commencementStatus: use "To be commenced" ONLY when the user explicitly says the work has not commenced / has not started yet / should wait before starting, AND they did not give a start date or due date, AND they are not asking for a recurring series. Use "Commenced" when the prompt says work has started, is ongoing, or is already underway.
- If the user specifies a start date and/or due date (including relative dates such as "start tomorrow" or "due next Friday"), NEVER suggest "To be commenced". A scheduled start/due date is not the same as "To be commenced". In that case use "Commenced", or omit commencementStatus if it is already Commenced.
- Recurrence is create-only. If context says recurrence cannot be suggested, omit recurrence.
- Suggest recurrence ONLY when the prompt implies a repeating series (every week, each Monday, daily, monthly, yearly, recurring, repeat until, N occurrences, every 2 weeks, weekdays, first Friday of each month, etc.). For a one-off task, omit recurrence or set enabled false.
- Recurring dates are START dates of each occurrence. Each occurrence due date is computed as that start date plus workingDays inclusive working days (Standard default 4, URGENT default 2). When recurrence.enabled is true, omit startDate and dueDate.
- Recurring cannot be used with "To be commenced". If suggesting recurrence.enabled true, set commencementStatus to "Commenced" (or omit it if already Commenced).
- frequency Daily + dailyMode everyWeekday = Monday–Friday (interval is ignored). Otherwise Daily uses interval as every N days.
- Weekly: set weeklyWeekdays from the prompt. If unspecified, use the weekday of startAt.
- Monthly dayOfMonth: set monthDay (e.g. 15). Monthly nthWeekday: set weekdayNth + weekday (e.g. First Friday).
- Yearly monthDay: set yearlyMonth + monthDay. Yearly nthWeekdayOfMonth: set yearlyMonth + weekdayNth + weekday.
- startAt is the first occurrence start date. Calculate relative dates from "Today (Hong Kong)".
- endMode byDate: endBy is the inclusive last start date. endMode afterCount: endAfterCount is 1–52. "until December" / "through 2026" → byDate. "for 8 weeks" / "10 times" → afterCount.
- workingDays: use an explicit duration from the prompt; otherwise Standard=4, URGENT=2.
- interval: "every 2 weeks" → Weekly + interval 2. "every 3 months" → Monthly + interval 3.
- Compare to current recurrence in context; omit recurrence if the suggested pattern is identical.
- Always suggest complexity as exactly one of Low, Medium, or High. If the user explicitly describes complexity using another word, translate it into one of these three values.
- To judge complexity, reference the task name and description. If a parent project is selected, also reference the project name and project description from the context.
- IT, developer, data, AI, automation, integration, analytics, system design, database, security, or infrastructure work tends to be High unless it is clearly trivial.
- Venue booking, sending/preparing email, organizing a meeting, scheduling, basic coordination, and other routine administrative work tends to be Low.
- Use Medium for work with moderate coordination, analysis, or judgment that is not clearly Low or High.
- Avoid echoing unchanged values: compare each field to "Current form values" in context. If a suggested value would be identical to what is already on the form, improve/expand it when reasonable; otherwise omit that specific field.
- comment: text for the Comments field (a draft posted when the user saves the task). When the user asks to write, add, or improve a comment, set comment to the full suggested text. Compare to "comment (draft)" in context; omit if identical.
- Use assignee and project names only from the provided staff/projects lists.
- Assignees: when the user adds or removes people, set assigneeNames to the full resulting visible assignee list (start from current assignees in context, apply add/remove, then list everyone who should remain). Never include the PIC in assigneeNames.
- If the user mentions exactly one person as assignee / owner / responsible / PIC, set picName to that person and leave assigneeNames empty or omit it. Do not also suggest that person as an assignee.
- If the user mentions two or more people, put the PIC (named PIC, or the first person if they named one owner) in picName only. Put the other people in assigneeNames. Example: "assign A and B, C as PIC" → assigneeNames: A, B and picName: C. Example: "assign Ken" → picName: Ken and assigneeNames: [].
- Dates must be YYYY-MM-DD. If the user gives a range, set startDate and dueDate accordingly.
- Relative dates such as "today", "tomorrow", "next week", "next Monday", or weekdays MUST be calculated from "Today (Hong Kong)" and the relative date reference in the context, not from existing form dates.
- Do not contradict yourself: startDate must be on or before dueDate when both are set.
- reason: only suggest when the current form shows or implies a long duration that needs explanation. It should explain why the task needs that much time, in one concise sentence.
- Website links: when the user mentions one or more URLs (http/https or bare domains), add each as an entry in websiteLinks with a concise description (what the link is for). Use full https URLs when possible. Do not repeat URLs already listed under "Current website link attachments" in context. Omit websiteLinks when no URLs are mentioned.
- overallComment: required whenever you output at least one non-null field suggestion (name, description, comment, projectName, assigneeNames, picName, priority, commencementStatus, complexity, startDate, dueDate, reason, websiteLinks, or recurrence). Summarize the intended updates in plain language; include a brief reason for the complexity recommendation; mention the recurrence pattern when recurrence is set.
- You are suggesting values only; the app will show suggestions and the user adopts them. Do not mention overwriting.
''';

    final user = StringBuffer()
      ..writeln(formContext.trim())
      ..writeln()
      ..writeln('User prompt:')
      ..writeln(trimmed);

    final body = jsonEncode({
      'model': _effectiveModel,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user.toString()},
      ],
      'temperature': 0.25,
    });

    return _chatCompletionJsonObject(body);
  }

  /// Structured project-field suggestions for the Asana project slide.
  static Future<Map<String, dynamic>> suggestAsanaProjectDraft({
    required String userPrompt,
    required String formContext,
  }) async {
    if (!isConfigured) {
      throw StateError(_missingConfigMessage);
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    const system = '''
You help users fill a project form in a workplace project tracker.
Reply with ONLY one JSON object (no markdown, no code fences).

Schema:
{
  "related": true or false,
  "message": "optional short note when nothing can be suggested",
  "overallComment": "when you suggest any field change: 1-3 sentences summarizing what you inferred (required if any name/description/comment/status/assigneeNames/picNames/startDate/dueDate/websiteLinks/milestones are set)",
  "name": "string or null",
  "description": "string or null",
  "comment": "comment body for the Comments field (posted when the user saves), or null",
  "status": "Not started" or "In progress" or "Completed" or null,
  "assigneeNames": ["names from available staff list"] or [],
  "picNames": ["names from available staff list"] or [],
  "startDate": "YYYY-MM-DD" or null,
  "dueDate": "YYYY-MM-DD" or null,
  "websiteLinks": [
    { "url": "https://...", "description": "short label for the link" }
  ] or [],
  "hasMilestone": true or false or null,
  "milestones": [
    { "description": "one project step as a sentence", "progressPercent": 40 }
  ] or []
}

Rules:
- The user is already working inside a project create/edit slide. Treat every prompt as an attempt to fill or improve this project form. Always set "related": true.
- Always try to suggest at least one useful field. Prefer name and description when the prompt contains project details; if the prompt is vague, make a best-effort improvement based on the prompt plus current form values.
- For optional structured fields (status, assigneeNames, picNames, startDate, dueDate, comment, websiteLinks, hasMilestone, milestones), suggest them when the prompt mentions or implies them. Use null or omit fields you cannot infer.
- REQUIRED — Milestones: if the prompt says milestone/milestones/phase/step/deliverable, OR lists 2+ pieces of work ("one is …, one is …", "first… second…", numbered steps), you MUST set "hasMilestone": true AND fill "milestones" with those steps. Do not stop at name and description in that case. Name/description AND milestones should all be set.
- When suggesting milestones, fill 1–20 items. Each item needs a clear description (keep the user's wording as a sentence) and progressPercent as an integer 0–100.
- Milestone percentages MUST add up to 100. If the user does not give weights, split by implied effort; if effort is similar, use an even split and put any remainder on the last item (for example 3 similar steps → 34, 33, 33).
- Keep milestone order the same as the user's steps. Do not mark achieved; the user does that later.
- Compare to "milestones" in current form values. If the suggested list is the same descriptions and percents in the same order, omit hasMilestone and milestones.
- If the user explicitly says the project has no milestones, set hasMilestone false and milestones [].
- Avoid echoing unchanged values: compare each field to "Current project form values" in context. If a suggested value would be identical to what is already on the form, improve/expand it when reasonable; otherwise omit that specific field.
- Use assignee and PIC names only from the provided staff list.
- assigneeNames: full resulting visible assignee list when the user changes assignees. Never include PIC names in assigneeNames.
- If the user mentions exactly one person as assignee / owner / responsible / PIC, set picNames to that person only and leave assigneeNames empty or omit it. Do not also suggest that person as an assignee.
- If the user mentions two or more people, put PIC(s) in picNames only and the other people in assigneeNames.
- Dates must be YYYY-MM-DD. startDate must be on or before dueDate when both are set.
- status must be exactly one of: Not started, In progress, Completed.
- comment: text for the Comments field. When the user asks to write, add, or improve a comment, set comment to the full suggested text. Compare to "comment (draft)" in context; omit if identical.
- Website links: when the user mentions one or more URLs (http/https or bare domains), add each as an entry in websiteLinks with a concise description. Use full https URLs when possible. Do not repeat URLs already listed under "Current website link attachments" in context. Omit websiteLinks when no URLs are mentioned.
- overallComment: required whenever you output at least one non-null field suggestion. Mention the milestone steps briefly when milestones are set.
- You are suggesting values only; the user adopts them. Do not mention overwriting.
''';

    final user = StringBuffer()
      ..writeln(formContext.trim())
      ..writeln()
      ..writeln('User prompt:')
      ..writeln(trimmed)
      ..writeln()
      ..writeln(
        'If this prompt lists project steps or says milestone, your JSON must include hasMilestone=true and a milestones array. Name and description alone are not enough.',
      );

    final body = jsonEncode({
      'model': _effectiveModel,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user.toString()},
      ],
      'temperature': 0.2,
    });

    return _chatCompletionJsonObject(body);
  }

  /// Comment-only suggestions for assignees (does not touch task metadata).
  static Future<Map<String, dynamic>> suggestCommentDraft({
    required String userPrompt,
    required String formContext,
  }) async {
    if (!isConfigured) {
      throw StateError(_missingConfigMessage);
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    const system = '''
You help users write a comment on an existing task in a workplace project tracker.
Reply with ONLY one JSON object (no markdown, no code fences).

Schema:
{
  "related": true or false,
  "message": "optional short note when no comment can be suggested",
  "overallComment": "when comment is set: 1-2 sentences on how you improved the draft (required if comment is non-null)",
  "comment": "improved comment text or null",
  "websiteLinks": [
    { "url": "https://...", "description": "short label for the link" }
  ] or []
}

Rules:
- Set "related": false only if the prompt is clearly unrelated to drafting a task comment.
- You may ONLY suggest the comment body or website links. Never suggest task name, description, dates, assignees, PIC, priority, or project.
- Improve clarity and tone; keep the user's intent. Use the task name and current draft for context.
- Website links: when the user mentions one or more URLs, add each as an entry in websiteLinks with a concise description. Do not repeat URLs already listed under "Current website link attachments".
- overallComment: required when comment or websiteLinks is non-null/non-empty; briefly explain what you changed or added.
- You are suggesting text/links only; the user adopts it into the comment/attachments field. Do not mention other fields.
''';

    final user = StringBuffer()
      ..writeln(formContext.trim())
      ..writeln()
      ..writeln('User prompt:')
      ..writeln(trimmed);

    final body = jsonEncode({
      'model': _effectiveModel,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user.toString()},
      ],
      'temperature': 0.25,
    });

    return _chatCompletionJsonObject(body);
  }

  /// Structured subtask-field suggestions for the Asana subtask slide.
  static Future<Map<String, dynamic>> suggestAsanaSubtaskDraft({
    required String userPrompt,
    required String formContext,
  }) async {
    if (!isConfigured) {
      throw StateError(_missingConfigMessage);
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    const system = '''
You help users fill a sub-task form in a workplace project tracker.
Reply with ONLY one JSON object (no markdown, no code fences).

Schema:
{
  "related": true or false,
  "message": "optional short note when nothing can be suggested",
  "overallComment": "when you suggest any field change: 1-3 sentences summarizing what you inferred and what the user can adopt",
  "name": "string or null",
  "description": "sub-task description/details, or null",
  "assigneeNames": ["names from available sub-task assignees list"] or [],
  "picName": "one staff name, or null",
  "priority": "Standard" or "URGENT" or null,
  "commencementStatus": "Commenced" or "To be commenced" or null,
  "complexity": "Low" or "Medium" or "High",
  "startDate": "YYYY-MM-DD" or null,
  "dueDate": "YYYY-MM-DD" or null,
  "reason": "reason for needing a long time to complete the sub-task, or null",
  "comment": "comment body for the Comments field (posted when the user saves), or null",
  "websiteLinks": [
    { "url": "https://...", "description": "short label for the link" }
  ] or [],
  "recurrence": null or {
    "enabled": true or false,
    "frequency": "Daily" or "Weekly" or "Monthly" or "Yearly",
    "interval": 1,
    "dailyMode": "everyNDays" or "everyWeekday" or null,
    "weeklyWeekdays": ["Monday", "Tuesday"] or [],
    "monthlyMode": "dayOfMonth" or "nthWeekday" or null,
    "monthDay": 15,
    "weekdayNth": "First" or "Second" or "Third" or "Fourth" or "Last" or null,
    "weekday": "Monday" or null,
    "yearlyMode": "monthDay" or "nthWeekdayOfMonth" or null,
    "yearlyMonth": "January" or 1 or null,
    "workingDays": 4,
    "startAt": "YYYY-MM-DD" or null,
    "endMode": "byDate" or "afterCount" or null,
    "endBy": "YYYY-MM-DD" or null,
    "endAfterCount": 10
  }
}

Rules:
- The user is already working inside a sub-task create/edit slide. Treat every prompt as an attempt to fill or improve this sub-task form. Always set "related": true.
- Always try to suggest at least one useful field. Prioritize suggesting BOTH name and description when the prompt provides enough sub-task detail; if the prompt is vague, make a best-effort improvement based on the prompt plus current form values.
- For optional structured fields (assigneeNames, picName, priority, commencementStatus, dates, reason, comment, websiteLinks, recurrence), suggest them when the prompt mentions or implies them. Use null or omit fields you cannot infer.
- commencementStatus: use "To be commenced" ONLY when the user explicitly says the work has not commenced / has not started yet / should wait before starting, AND they did not give a start date or due date, AND they are not asking for a recurring series. Use "Commenced" when the prompt says work has started, is ongoing, or is already underway.
- If the user specifies a start date and/or due date (including relative dates such as "start tomorrow" or "due next Friday"), NEVER suggest "To be commenced". A scheduled start/due date is not the same as "To be commenced". In that case use "Commenced", or omit commencementStatus if it is already Commenced.
- Recurrence is create-only. If context says recurrence cannot be suggested, omit recurrence.
- Suggest recurrence ONLY when the prompt implies a repeating series (every week, each Monday, daily, monthly, yearly, recurring, repeat until, N occurrences, every 2 weeks, weekdays, first Friday of each month, etc.). For a one-off sub-task, omit recurrence or set enabled false.
- Recurring dates are START dates of each occurrence. Each occurrence due date is computed as that start date plus workingDays inclusive working days (Standard default 4, URGENT default 2). When recurrence.enabled is true, omit startDate and dueDate.
- Recurring cannot be used with "To be commenced". If suggesting recurrence.enabled true, set commencementStatus to "Commenced" (or omit it if already Commenced).
- frequency Daily + dailyMode everyWeekday = Monday–Friday (interval is ignored). Otherwise Daily uses interval as every N days.
- Weekly: set weeklyWeekdays from the prompt. If unspecified, use the weekday of startAt.
- Monthly dayOfMonth: set monthDay. Monthly nthWeekday: set weekdayNth + weekday.
- Yearly monthDay: set yearlyMonth + monthDay. Yearly nthWeekdayOfMonth: set yearlyMonth + weekdayNth + weekday.
- startAt is the first occurrence start date. Calculate relative dates from "Today (Hong Kong)".
- endMode byDate: endBy is the inclusive last start date. endMode afterCount: endAfterCount is 1–52. "until December" / "through 2026" → byDate. "for 8 weeks" / "10 times" → afterCount.
- workingDays: use an explicit duration from the prompt; otherwise Standard=4, URGENT=2.
- interval: "every 2 weeks" → Weekly + interval 2.
- Compare to current recurrence in context; omit recurrence if the suggested pattern is identical.
- Always suggest complexity as exactly one of Low, Medium, or High. If the user explicitly describes complexity using another word, translate it into one of these three values.
- To judge complexity, reference the sub-task name and description, then combine that with the parent task name and description. If a parent project exists, also reference the project name and project description from the context.
- IT, developer, data, AI, automation, integration, analytics, system design, database, security, or infrastructure work tends to be High unless it is clearly trivial.
- Venue booking, sending/preparing email, organizing a meeting, scheduling, basic coordination, and other routine administrative work tends to be Low.
- Use Medium for work with moderate coordination, analysis, or judgment that is not clearly Low or High.
- Avoid echoing unchanged values: compare each field to "Current form values" in context. If a suggested value would be identical, improve/expand it when reasonable; otherwise omit that specific field.
- The description should be useful execution detail, not just a repeat of the name.
- Use assignee and PIC names only from the available staff list in context. Sub-task assignees may be anyone on that staff list, not only parent-task assignees.
- Assignees: when the user adds or removes people, set assigneeNames to the full resulting visible assignee list (start from current assignees in context, apply add/remove, then list everyone who should remain). Never include the PIC in assigneeNames.
- If the user mentions exactly one person as assignee / owner / responsible / PIC, set picName to that person and leave assigneeNames empty or omit it. Do not also suggest that person as an assignee.
- If the user mentions two or more people, put the PIC in picName only and the other people in assigneeNames.
- Dates must be YYYY-MM-DD. If the user gives a range, set startDate and dueDate accordingly.
- Relative dates such as "today", "tomorrow", "next week", "next Monday", or weekdays MUST be calculated from "Today (Hong Kong)" and the relative date reference in the context, not from the current form's existing start/due dates.
- Do not contradict yourself: startDate must be on or before dueDate when both are set.
- comment: text for the Comments field. Compare to "comment (draft)" in context; omit if identical.
- reason: only suggest when the context says reason is editable and the long duration needs explanation. It should explain why the sub-task needs that much time, in one concise sentence.
- Website links: when the user mentions one or more URLs, add each as an entry in websiteLinks with a concise description. Do not repeat URLs already listed under "Current website link attachments".
- The user may or may not be the creator. If the user is NOT the creator, they cannot modify the name. The context will tell you if the name field is modifiable. If not modifiable, DO NOT suggest a name.
- Use the parent task context provided to understand the context of the sub-task.
- If assignees are discussed, treat the "Available staff for sub-task assignees and PIC" list in context as the valid people. Never suggest assigning someone outside that list.
- Attachments are represented as websiteLinks. Include URLs in websiteLinks, not in the comment text, unless the user explicitly asks to write them into the comment.
- overallComment: required whenever you output at least one non-null field suggestion. Summarize the intended updates in plain language; include a brief reason for the complexity recommendation; mention the recurrence pattern when recurrence is set.
- You are suggesting values only; the app will show suggestions and the user adopts them. Do not mention overwriting.
''';

    final user = StringBuffer()
      ..writeln(formContext.trim())
      ..writeln()
      ..writeln('User prompt:')
      ..writeln(trimmed);

    final body = jsonEncode({
      'model': _effectiveModel,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user.toString()},
      ],
      'temperature': 0.35,
    });

    return _chatCompletionJsonObject(body);
  }

  /// Structured discussion-forum draft suggestions.
  static Future<Map<String, dynamic>> suggestDiscussionThreadDraft({
    required String userPrompt,
    required String formContext,
  }) async {
    if (!isConfigured) {
      throw StateError(_missingConfigMessage);
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    const system = '''
You help users draft Project Tracker discussion forum posts.
Reply with ONLY one JSON object (no markdown, no code fences).

Schema:
{
  "title": "clear forum post title, or null",
  "content": "well-structured forum post content, or null",
  "category": "Announcement" or "Suggestion" or "Feature idea" or "Bug report" or "General",
  "status": "Open" or "Resolved" or "Closed",
  "overallComment": "1-2 sentences explaining the suggested forum draft"
}

Rules:
- The forum is only for Project Tracker discussion: admin announcements, user suggestions, brainstorming new features, and bug/issue reporting.
- Choose category from exactly: Announcement, Suggestion, Feature idea, Bug report, General.
- Choose status from exactly: Open, Resolved, Closed. Use Open for new suggestions/issues unless the user clearly says it is already resolved or closed.
- Use Announcement for admin/system updates, Suggestion for improvement suggestions, Feature idea for new feature brainstorming, Bug report for bugs/issues/errors, General otherwise.
- Make the title concise and professional.
- Make the content easy for Project Tracker maintainers to understand. For bug reports, include expected behavior, actual behavior, and reproduction steps when inferable.
- Respect existing title/content/category/status in the context and improve them when useful.
''';

    final body = jsonEncode({
      'model': _effectiveModel,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': '$formContext\n\nUser prompt:\n$trimmed'},
      ],
      'temperature': 0.25,
    });

    return _chatCompletionJsonObject(body);
  }

  static Future<String> suggestDiscussionReplyDraft({
    required String userPrompt,
    required String parentContext,
  }) async {
    if (!isConfigured) {
      throw StateError(_missingConfigMessage);
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    const system = '''
You help users draft replies in the Project Tracker discussion forum.
Reply with ONLY one JSON object (no markdown, no code fences).

Schema:
{
  "reply": "the suggested reply text"
}

Rules:
- Draft a concise, professional reply.
- Consider the provided parent post and parent replies as context.
- Do not invent facts not supported by the context or user prompt.
- Keep the reply suitable for a workplace discussion forum.
''';

    final body = jsonEncode({
      'model': _effectiveModel,
      'messages': [
        {'role': 'system', 'content': system},
        {
          'role': 'user',
          'content':
              'Parent discussion context:\n$parentContext\n\nUser prompt:\n$trimmed',
        },
      ],
      'temperature': 0.25,
    });

    final map = await _chatCompletionJsonObject(body);
    final reply = map['reply']?.toString().trim();
    if (reply == null || reply.isEmpty) {
      throw const FormatException('Could not parse reply from model.');
    }
    return reply;
  }

  static Future<Map<String, dynamic>> _chatCompletionJsonObject(
    String body,
  ) async {
    final content = await _chatCompletionContent(body);
    final map = parseJsonObjectFromModel(content);
    if (map != null) return map;

    final repaired = await _repairJsonObjectResponse(
      originalBody: body,
      invalidContent: content,
    );
    if (repaired != null) return repaired;

    throw FormatException(
      'Could not parse JSON from model after automatic retry. '
      'Original raw (truncated): ${_truncate(content)}',
    );
  }

  static Future<Map<String, dynamic>?> _repairJsonObjectResponse({
    required String originalBody,
    required String invalidContent,
  }) async {
    try {
      final decoded = jsonDecode(originalBody);
      if (decoded is! Map<String, dynamic>) return null;
      final originalMessages = decoded['messages'];
      if (originalMessages is! List) return null;
      final messages = [
        for (final m in originalMessages) m,
        {'role': 'assistant', 'content': invalidContent},
        {
          'role': 'user',
          'content':
              'The previous response was not valid JSON and could not be parsed. '
              'Return ONLY one complete valid JSON object matching the same schema. '
              'Preserve the same intended values. Escape quotes and newlines correctly. '
              'Do not include markdown, code fences, comments, or text outside the JSON object.',
        },
      ];
      final repairBody = jsonEncode({
        ...decoded,
        'messages': messages,
        'temperature': 0,
      });
      final repairedContent = await _chatCompletionContent(repairBody);
      return parseJsonObjectFromModel(repairedContent);
    } catch (_) {
      return null;
    }
  }

  static String _truncate(String value, [int maxLength = 400]) {
    return value.length > maxLength ? value.substring(0, maxLength) : value;
  }

  static Future<String> _chatCompletionContent(String body) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...LocalLlmConfig.authorizationHeaders(),
    };

    final res = await http
        .post(
          Uri.parse(LocalLlmConfig.chatCompletionsUrl),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 120));

    if (res.statusCode != 200) {
      String detail = res.body;
      try {
        final m = jsonDecode(res.body);
        if (m is Map && m['error'] is Map) {
          final err = m['error'] as Map;
          detail = '${err['type'] ?? 'error'}: ${err['message'] ?? res.body}';
        }
      } catch (_) {}
      throw LlmHttpException(
        'LLM HTTP ${res.statusCode}',
        detail.isNotEmpty ? detail : null,
      );
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected API response shape');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('No choices in API response');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const FormatException('Invalid choice object');
    }
    final message = first['message'];
    if (message is! Map<String, dynamic>) {
      throw const FormatException('Invalid message object');
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Empty model content');
    }
    return content;
  }

  static Map<String, dynamic>? parseJsonObjectFromModel(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      final lines = s.split('\n');
      if (lines.length > 2) {
        s = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    final i = s.indexOf('{');
    final j = s.lastIndexOf('}');
    if (i >= 0 && j > i) {
      try {
        final decoded = jsonDecode(s.substring(i, j + 1));
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }
}

class LlmHttpException implements Exception {
  LlmHttpException(this.message, [this.detail]);

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message\n$detail';
}
