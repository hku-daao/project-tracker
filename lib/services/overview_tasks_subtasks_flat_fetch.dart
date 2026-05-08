import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// One row from [overview_tasks_subtasks_flat] (task card or sub-task card).
class OverviewFlatViewRow {
  const OverviewFlatViewRow({
    required this.rowKind,
    required this.parentTaskId,
    this.subtaskId,
    required this.rowStatus,
    required this.isOverdueRow,
  });

  final String rowKind;
  final String parentTaskId;
  final String? subtaskId;
  final String rowStatus;
  final String isOverdueRow;

  factory OverviewFlatViewRow.fromMap(Map<String, dynamic> m) {
    final kind = (m['row_kind'] as String?)?.trim().toLowerCase() ?? '';
    final pid = m['parent_task_id']?.toString().trim() ?? '';
    final sid = m['subtask_id']?.toString().trim();
    final rs = ((m['effective_status'] ?? m['row_status']) as String?)
            ?.trim()
            .toLowerCase() ??
        '';
    final od = (m['is_overdue_row'] as String?)?.trim() ?? '';
    return OverviewFlatViewRow(
      rowKind: kind,
      parentTaskId: pid,
      subtaskId: (sid == null || sid.isEmpty) ? null : sid,
      rowStatus: rs,
      isOverdueRow: od,
    );
  }
}

/// Server-side row keys for [overview_tasks_subtasks_flat] (task + sub-task rows).
///
/// Status filters use [effective_status] on each flat row (task row → task.status; sub-task row →
/// subtask.status). Legacy [row_status] is still selected for compatibility.
class OverviewTasksSubtasksFlatFetch {
  OverviewTasksSubtasksFlatFetch._();

  static const _viewName = 'overview_tasks_subtasks_flat';

  /// Mirrors [PostgrestBuilder._cleanFilterArray] (postgrest 2.6) so debug URLs match real requests.
  static String _postgrestCleanFilterArray(List<dynamic> filter) {
    if (filter.every((element) => element is num)) {
      return filter.map((s) => '$s').join(',');
    }
    return filter.map((s) => '"$s"').join(',');
  }

  /// Same order chain as [.order] ×2 + [.range] in [fetchRowKeysForSubmissionKeys] / [fetchFlatRows].
  static const _orderQueryParam =
      'parent_task_id.asc.nullslast,subtask_id.asc.nullsfirst';

  /// Human-readable label for debug URL logs (no single- vs multi-select branch).
  static String _debugSubmissionScenarioLabel(Set<String> normalizedSubmissionKeys) {
    final list = normalizedSubmissionKeys.toList()..sort();
    if (list.isEmpty) return 'All submission (no effective_submission filter)';
    return 'chips=[${list.join(', ')}]';
  }

  /// Reconstructs the GET URL query string the Supabase/PostgREST client generates for our builder chain.
  ///
  /// Auth (`apikey`, `Authorization`) is sent as headers — not included here. Path matches
  /// `{restUrl}/{view}`.
  static String reconstructedRestGetUrl({
    required String restV1BaseUrl,
    required String selectColumns,
    bool overdueOnly = false,
    List<String> rowStatusIn = const [],
    List<String> rowSubmissionInValues = const [],
    required int offset,
    required int limit,
  }) {
    final base = restV1BaseUrl.endsWith('/')
        ? restV1BaseUrl.substring(0, restV1BaseUrl.length - 1)
        : restV1BaseUrl;
    final path = Uri.parse('$base/$_viewName');
    final qp = <String, String>{
      'select': selectColumns,
      if (overdueOnly) 'is_overdue_row': 'eq.Yes',
      if (rowStatusIn.isNotEmpty)
        'effective_status': 'in.(${_postgrestCleanFilterArray(rowStatusIn)})',
      if (rowSubmissionInValues.isNotEmpty)
        'effective_submission':
            'in.(${_postgrestCleanFilterArray(rowSubmissionInValues)})',
      'order': _orderQueryParam,
      'offset': '$offset',
      'limit': '$limit',
    };
    return path.replace(queryParameters: qp).toString();
  }

  static void _debugLogFullRestUrl({
    required String source,
    required String scenarioLabel,
    required String url,
  }) {
    debugPrint('');
    debugPrint('══════════════════════════════════════════════════════════════');
    debugPrint('overview_tasks_subtasks_flat — $source');
    debugPrint('Scenario: $scenarioLabel');
    debugPrint('Full reconstructed GET URL (headers apikey/Authorization not shown):');
    debugPrint(url);
    debugPrint('══════════════════════════════════════════════════════════════');
    debugPrint('');
  }

  /// Stable keys for intersection with [_CustomizedFlatEntry] rows.
  static String taskRowKey(String parentTaskId) => 'task:$parentTaskId';

  static String subtaskRowKey(String parentTaskId, String subtaskId) =>
      'sub:$parentTaskId:$subtaskId';

  /// Parent task id from [taskRowKey] / [subtaskRowKey] ([null] if unrecognized).
  static String? parentTaskIdFromRowKey(String key) {
    final k = key.trim();
    if (k.startsWith('task:')) {
      return k.substring('task:'.length).trim();
    }
    if (k.startsWith('sub:')) {
      final parts = k.split(':');
      if (parts.length >= 3) return parts[1].trim();
    }
    return null;
  }

  /// Combine status + submission server allowlists (AND). Either side null means “no filter
  /// from that dimension”.
  static Set<String>? intersectAllowlists(Set<String>? a, Set<String>? b) {
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return a.intersection(b);
  }

  static const _submissionChipKeys = {
    'pending',
    'submitted',
    'accepted',
    'returned',
  };

  /// Coerces UI/persisted submission chip keys to `pending` | `submitted` | `accepted` | `returned`.
  ///
  /// Callers may accidentally pass [Enum]s or objects whose [Object.toString] is not a plain
  /// keyword; PostgREST must receive raw string filters built only from canonical keys.
  static Set<String> normalizeSubmissionFilterKeys(Iterable<dynamic>? raw) {
    if (raw == null) return {};
    final out = <String>{};
    for (final Object? e in raw) {
      if (e == null) continue;
      final String token;
      if (e is String) {
        token = e;
      } else if (e is Enum) {
        token = e.name;
      } else {
        token = e.toString();
      }
      var t = token.trim().toLowerCase();
      if (t.isEmpty) continue;
      final dot = t.lastIndexOf('.');
      if (dot != -1 && dot < t.length - 1) {
        t = t.substring(dot + 1);
      }
      if (_submissionChipKeys.contains(t)) {
        out.add(t);
      }
    }
    return out;
  }

  /// Maps UI submission chip keys (`pending` | `submitted` | …) to exact strings in
  /// [overview_tasks_subtasks_flat.effective_submission].
  static List<String> rowSubmissionInValuesForKeys(Set<String> submissionKeys) {
    final out = <String>{};
    for (final raw in submissionKeys) {
      final k = raw.trim().toLowerCase();
      if (k.isEmpty) continue;
      switch (k) {
        case 'pending':
          out.add('');
          out.add('Pending');
          break;
        case 'submitted':
          out.add('Submitted');
          break;
        case 'accepted':
          out.add('Accepted');
          break;
        case 'returned':
          out.add('Returned');
          break;
        default:
          break;
      }
    }
    final list = out.toList()..sort();
    return list;
  }

  /// PostgREST [`inFilter`] on [`effective_submission`] (per-row task/sub-task submission).
  static dynamic _applySubmissionInListFilter(
    dynamic query,
    List<String> rowSubmissionInValues,
  ) {
    if (rowSubmissionInValues.isEmpty) return query;
    return query.inFilter('effective_submission', rowSubmissionInValues);
  }

  /// Empty submission matches UI “Pending”; deleted rows often have empty submission too — exclude
  /// lifecycle-deleted flat rows unless the user explicitly filters for Deleted status.
  static dynamic _applyExcludeDeletedLifecycleUnlessIncluded(
    dynamic query,
    bool includeDeletedLifecycleRows,
  ) {
    if (includeDeletedLifecycleRows) return query;
    return query.neq('effective_status', 'deleted');
  }

  /// Returns row keys allowed by [submissionKeys] (`pending` | `submitted` | …).
  ///
  /// Uses only [`inFilter`] on [`effective_submission`] with [List<String>] (never `.eq`).
  ///
  /// When [includeDeletedLifecycleRows] is false (default), excludes rows with
  /// [effective_status] `deleted` so e.g. “Pending” does not match deleted tasks with blank
  /// submission. Set true when the Status filter includes deleted.
  static Future<Set<String>?> fetchRowKeysForSubmissionKeys(
    Iterable<dynamic> submissionKeysRaw, {
    bool includeDeletedLifecycleRows = false,
  }) async {
    if (!SupabaseConfig.isConfigured) return null;

    final submissionKeys = normalizeSubmissionFilterKeys(submissionKeysRaw);
    if (submissionKeys.isEmpty) return null;

    final list = List<String>.from(rowSubmissionInValuesForKeys(submissionKeys));
    // ignore: avoid_print
    print('Filter List: $list');

    try {
      final client = Supabase.instance.client;
      final out = <String>{};
      const pageSize = 1000;
      var offset = 0;
      var totalRows = 0;
      while (true) {
        if (offset == 0) {
          _debugLogFullRestUrl(
            source: 'fetchRowKeysForSubmissionKeys',
            scenarioLabel: _debugSubmissionScenarioLabel(submissionKeys),
            url: reconstructedRestGetUrl(
              restV1BaseUrl: client.rest.url,
              selectColumns:
                  'row_kind,parent_task_id,subtask_id,effective_status,effective_submission',
              rowSubmissionInValues: list,
              offset: offset,
              limit: pageSize,
            ),
          );
        }
        dynamic query = client
            .from(_viewName)
            .select(
              'row_kind,parent_task_id,subtask_id,effective_status,effective_submission',
            );
        query = _applySubmissionInListFilter(query, list);
        query = _applyExcludeDeletedLifecycleUnlessIncluded(
          query,
          includeDeletedLifecycleRows,
        );
        query = query
            .order('parent_task_id', ascending: true)
            .order('subtask_id', ascending: true, nullsFirst: true);
        final res =
            await query.range(offset, offset + pageSize - 1) as List;
        totalRows += res.length;
        if (res.isEmpty) break;
        for (final raw in res) {
          final m = Map<String, dynamic>.from(raw as Map);
          final kind = (m['row_kind'] as String?)?.trim().toLowerCase() ?? '';
          final pid = m['parent_task_id']?.toString().trim() ?? '';
          if (pid.isEmpty) continue;
          if (kind == 'task') {
            out.add(taskRowKey(pid));
            continue;
          }
          if (kind == 'subtask') {
            final sid = m['subtask_id']?.toString().trim() ?? '';
            if (sid.isEmpty) continue;
            out.add(subtaskRowKey(pid, sid));
          }
        }
        if (res.length < pageSize) break;
        offset += pageSize;
      }
      debugPrint('Query Result Count: $totalRows');
      return out;
    } catch (e, st) {
      debugPrint('fetchRowKeysForSubmissionKeys error: $e\n$st');
      return null;
    }
  }

  /// Returns row keys allowed by the current status selection.
  ///
  /// When [statuses] is **empty** (“All” in the UI), returns **null** — callers must **not**
  /// filter on [effective_status] and should skip client-side allowlisting.
  ///
  /// When [statuses] has values, applies `.inFilter('effective_status', …)` (per-row lifecycle).
  static Future<Set<String>?> fetchRowKeysForStatuses(Set<String> statuses) async {
    if (!SupabaseConfig.isConfigured) return null;
    if (statuses.isEmpty) return null;

    final sorted = statuses.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet().toList()
      ..sort();

    debugPrint('Selected Statuses: $sorted');

    try {
      final client = Supabase.instance.client;
      final out = <String>{};
      // PostgREST caps unbounded selects (~1000 rows). Page so the allowlist matches every row.
      const pageSize = 1000;
      var offset = 0;
      var totalRows = 0;
      while (true) {
        dynamic query = client
            .from(_viewName)
            .select('row_kind,parent_task_id,subtask_id,effective_status');
        query = query.inFilter('effective_status', sorted);
        query = query
            .order('parent_task_id', ascending: true)
            .order('subtask_id', ascending: true, nullsFirst: true);
        final res =
            await query.range(offset, offset + pageSize - 1) as List;
        totalRows += res.length;
        if (res.isEmpty) break;
        for (final raw in res) {
          final m = Map<String, dynamic>.from(raw as Map);
          final kind = (m['row_kind'] as String?)?.trim().toLowerCase() ?? '';
          final pid = m['parent_task_id']?.toString().trim() ?? '';
          if (pid.isEmpty) continue;
          if (kind == 'task') {
            out.add(taskRowKey(pid));
            continue;
          }
          if (kind == 'subtask') {
            final sid = m['subtask_id']?.toString().trim() ?? '';
            if (sid.isEmpty) continue;
            out.add(subtaskRowKey(pid, sid));
          }
        }
        if (res.length < pageSize) break;
        offset += pageSize;
      }
      debugPrint('Query Result Count: $totalRows');
      return out;
    } catch (e, st) {
      debugPrint('fetchRowKeysForStatuses error: $e\n$st');
      return null;
    }
  }

  /// Paginated rows from the flat overview view.
  ///
  /// When [overdueOnly] is true, applies `.eq('is_overdue_row', 'Yes')` on the server.
  ///
  /// When [rowStatuses] is empty, no filter on [effective_status] is applied (same semantics as
  /// [fetchRowKeysForStatuses] when statuses is empty).
  ///
  /// [submissionKeys]: when non-empty, restricts [effective_submission] via [List<String>] + [.inFilter] only.
  ///
  /// When [includeDeletedLifecycleRows] is false and a submission filter is applied, excludes
  /// [effective_status] `deleted` (see [fetchRowKeysForSubmissionKeys]).
  static Future<List<OverviewFlatViewRow>> fetchFlatRows({
    bool overdueOnly = false,
    Set<String> rowStatuses = const {},
    Iterable<dynamic> submissionKeys = const <String>{},
    bool includeDeletedLifecycleRows = false,
  }) async {
    if (!SupabaseConfig.isConfigured) return const [];

    final sorted = rowStatuses
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final normSub = normalizeSubmissionFilterKeys(submissionKeys);
    final list = List<String>.from(rowSubmissionInValuesForKeys(normSub));
    // ignore: avoid_print
    print('Filter List: $list');

    try {
      final client = Supabase.instance.client;
      final out = <OverviewFlatViewRow>[];
      const pageSize = 1000;
      var offset = 0;
      var totalRows = 0;
      while (true) {
        if (offset == 0) {
          _debugLogFullRestUrl(
            source: 'fetchFlatRows',
            scenarioLabel: _debugSubmissionScenarioLabel(normSub),
            url: reconstructedRestGetUrl(
              restV1BaseUrl: client.rest.url,
              selectColumns:
                  'row_kind,parent_task_id,subtask_id,effective_status,is_overdue_row',
              overdueOnly: overdueOnly,
              rowStatusIn: sorted,
              rowSubmissionInValues: list,
              offset: offset,
              limit: pageSize,
            ),
          );
        }
        dynamic query = client.from(_viewName).select(
              'row_kind,parent_task_id,subtask_id,effective_status,is_overdue_row',
            );
        if (overdueOnly) {
          query = query.eq('is_overdue_row', 'Yes');
        }
        if (sorted.isNotEmpty) {
          query = query.inFilter('effective_status', sorted);
        }
        query = _applySubmissionInListFilter(query, list);
        if (list.isNotEmpty) {
          query = _applyExcludeDeletedLifecycleUnlessIncluded(
            query,
            includeDeletedLifecycleRows,
          );
        }
        query = query
            .order('parent_task_id', ascending: true)
            .order('subtask_id', ascending: true, nullsFirst: true);
        final res =
            await query.range(offset, offset + pageSize - 1) as List;
        totalRows += res.length;
        if (res.isEmpty) break;
        for (final raw in res) {
          final m = Map<String, dynamic>.from(raw as Map);
          final row = OverviewFlatViewRow.fromMap(m);
          if (row.parentTaskId.isEmpty) continue;
          if (row.rowKind == 'task') {
            out.add(row);
            continue;
          }
          if (row.rowKind == 'subtask') {
            if (row.subtaskId == null || row.subtaskId!.isEmpty) continue;
            out.add(row);
          }
        }
        if (res.length < pageSize) break;
        offset += pageSize;
      }
      debugPrint('Query Result Count: $totalRows');
      return out;
    } catch (e, st) {
      debugPrint('fetchFlatRows error: $e\n$st');
      return const [];
    }
  }
}
