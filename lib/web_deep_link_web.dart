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

/// Stores `subtask` / `task` from the real address bar (path or hash) so deep links survive login redirects.
void captureWebDeepLinkForSession() {
  final ids = _idsFromLocation();
  var sub = ids.$1;
  var task = ids.$2;
  if (sub != null && sub.isNotEmpty) {
    html.window.sessionStorage[_kSubtaskKey] = sub;
  }
  if (task != null && task.isNotEmpty) {
    html.window.sessionStorage[_kTaskKey] = task;
  }
}

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
