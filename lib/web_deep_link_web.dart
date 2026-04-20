import 'dart:html' as html;

const _kSubtaskKey = 'pt_deeplink_subtask';
const _kTaskKey = 'pt_deeplink_task';

String? _paramFromFragment(String fragment, String key) {
  if (fragment.isEmpty) return null;
  final idx = fragment.indexOf('?');
  if (idx < 0) return null;
  final u = Uri.parse('https://dummy.invalid${fragment.substring(idx)}');
  return u.queryParameters[key]?.trim();
}

/// `window.location.hash` is `#/?subtask=` (email links); [Uri.fragment] omits `#`.
String? _paramFromWindowHash(String key) {
  final raw = html.window.location.hash;
  if (raw.length <= 1) return null;
  final frag = raw.startsWith('#') ? raw.substring(1) : raw;
  if (frag.startsWith('?')) {
    return Uri.parse('https://dummy.invalid$frag').queryParameters[key]?.trim();
  }
  return _paramFromFragment(frag, key);
}

/// Stores `subtask` / `task` from the address bar so deep links survive [usePathUrlStrategy] and login.
///
/// Call once **before** [usePathUrlStrategy] with [clearStaleWhenUrlEmpty] true so a visit to `/`
/// clears leftover session ids. Call again **after** [usePathUrlStrategy] with
/// [clearStaleWhenUrlEmpty] false: if the URL no longer shows `?task=` / hash params but the first
/// call already saved them, we must **not** clear session.
void captureWebDeepLinkForSession({bool clearStaleWhenUrlEmpty = true}) {
  final ids = _idsFromLocation();
  final sub = ids.$1;
  final task = ids.$2;
  final hasSub = sub != null && sub.isNotEmpty;
  final hasTask = task != null && task.isNotEmpty;
  if (hasSub || hasTask) {
    if (hasSub) {
      html.window.sessionStorage[_kSubtaskKey] = sub;
    }
    if (hasTask) {
      html.window.sessionStorage[_kTaskKey] = task;
    }
    return;
  }
  if (clearStaleWhenUrlEmpty) {
    html.window.sessionStorage.remove(_kSubtaskKey);
    html.window.sessionStorage.remove(_kTaskKey);
  }
}

/// Task / subtask ids from the address bar (path, query, hash) — **not** session storage.
/// Used on startup so a full refresh on the landing page does not reopen detail from stale session.
(String?, String?) readDeepLinkIdsFromUrlOrHash() => _idsFromLocation();

(String?, String?) _idsFromLocation() {
  final href = html.window.location.href;
  final uri = Uri.parse(href);
  var sub = uri.queryParameters['subtask']?.trim();
  var task = uri.queryParameters['task']?.trim();
  if (sub == null || sub.isEmpty) {
    sub = _paramFromWindowHash('subtask');
  }
  if (sub == null || sub.isEmpty) {
    sub = _paramFromFragment(uri.fragment, 'subtask');
  }
  if (task == null || task.isEmpty) {
    task = _paramFromWindowHash('task');
  }
  if (task == null || task.isEmpty) {
    task = _paramFromFragment(uri.fragment, 'task');
  }
  return (sub, task);
}

String? readSubtaskIdFromUrlOrSession() {
  final ids = _idsFromLocation();
  if (ids.$1 != null && ids.$1!.isNotEmpty) return ids.$1;
  final s = html.window.sessionStorage[_kSubtaskKey]?.trim();
  if (s != null && s.isNotEmpty) return s;
  return null;
}

String? readTaskIdFromUrlOrSession() {
  final ids = _idsFromLocation();
  if (ids.$2 != null && ids.$2!.isNotEmpty) return ids.$2;
  final s = html.window.sessionStorage[_kTaskKey]?.trim();
  if (s != null && s.isNotEmpty) return s;
  return null;
}

void consumeSubtaskDeepLink() {
  html.window.sessionStorage.remove(_kSubtaskKey);
}

void consumeTaskDeepLink() {
  html.window.sessionStorage.remove(_kTaskKey);
}

/// Removes `?subtask=` / `?task=` from the visible URL after navigation (path strategy).
void clearDeepLinkQueryFromAddressBar() {
  final path = html.window.location.pathname;
  final safePath = (path == null || path.isEmpty) ? '/' : path;
  html.window.history.replaceState(null, '', safePath);
}

/// Keeps `?task=` in the address bar and session so a browser refresh reopens [TaskDetailScreen].
void syncWebLocationForTaskDetail(String taskId) {
  final id = taskId.trim();
  if (id.isEmpty) return;
  html.window.sessionStorage[_kTaskKey] = id;
  html.window.sessionStorage.remove(_kSubtaskKey);
  _replaceQueryParams((q) {
    q['task'] = id;
    q.remove('subtask');
  });
}

/// Clears task id from URL/session (e.g. when leaving task detail for home).
void clearWebTaskDetailFromLocation() {
  html.window.sessionStorage.remove(_kTaskKey);
  _replaceQueryParams((q) => q.remove('task'));
}

/// Keeps `?subtask=` so refresh stays on [SubtaskDetailScreen].
void syncWebLocationForSubtaskDetail(String subtaskId) {
  final id = subtaskId.trim();
  if (id.isEmpty) return;
  html.window.sessionStorage[_kSubtaskKey] = id;
  html.window.sessionStorage.remove(_kTaskKey);
  _replaceQueryParams((q) {
    q['subtask'] = id;
    q.remove('task');
  });
}

/// Clears subtask from URL/session; optionally restores [parentTaskId] for the underlying task screen.
void clearWebSubtaskDetailFromLocation({String? parentTaskId}) {
  html.window.sessionStorage.remove(_kSubtaskKey);
  _replaceQueryParams((q) => q.remove('subtask'));
  final p = parentTaskId?.trim();
  if (p != null && p.isNotEmpty) {
    syncWebLocationForTaskDetail(p);
  }
}

/// Clears task/subtask ids from URL and session so a refresh on the landing page stays on home.
void syncWebLocationForLanding() {
  html.window.sessionStorage.remove(_kTaskKey);
  html.window.sessionStorage.remove(_kSubtaskKey);
  _replaceQueryParams((q) {
    q.remove('task');
    q.remove('subtask');
  });
}

/// Updates either path `?query` or hash `#/path?query` so [readTaskIdFromUrlOrSession] /
/// [readSubtaskIdFromUrlOrSession] still resolve after refresh.
void _replaceQueryParams(void Function(Map<String, String> q) mutate) {
  final href = html.window.location.href;
  final uri = Uri.parse(href);
  final frag = uri.fragment;
  if (frag.contains('?')) {
    final qIdx = frag.indexOf('?');
    final pathPart = frag.substring(0, qIdx);
    final queryPart = frag.substring(qIdx + 1);
    final inner = Uri.parse('https://dummy.invalid?$queryPart');
    final q = Map<String, String>.from(inner.queryParameters);
    mutate(q);
    final newFrag = q.isEmpty
        ? pathPart
        : '$pathPart?${Uri(queryParameters: q).query}';
    final newUri = uri.replace(fragment: newFrag);
    html.window.history.replaceState(null, '', newUri.toString());
    return;
  }
  final q = Map<String, String>.from(uri.queryParameters);
  mutate(q);
  final newUri = uri.replace(
    queryParameters: q.isEmpty ? null : q,
  );
  html.window.history.replaceState(null, '', newUri.toString());
}
