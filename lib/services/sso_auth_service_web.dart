import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

Future<void> navigateToUrl(String url) async {
  html.window.location.href = url;
}

({String? code, String? state, String? ssoError}) readOAuthCallbackParams() {
  final uri = Uri.parse(html.window.location.href);
  return (
    code: uri.queryParameters['code'],
    state: uri.queryParameters['state'],
    ssoError: uri.queryParameters['sso_error'],
  );
}

void clearOAuthCallbackFromUrl() {
  final uri = Uri.parse(html.window.location.href);
  final clean = uri.replace(queryParameters: {});
  html.window.history.replaceState(null, '', clean.toString());
}

String readBrowserUrlForDebug() => html.window.location.href;

Future<http.Response> postJsonWithBrowserCredentials(
  Uri uri, {
  required Map<String, dynamic> body,
  required Duration timeout,
}) async {
  final req = await html.HttpRequest.request(
    uri.toString(),
    method: 'POST',
    requestHeaders: const {'Content-Type': 'application/json'},
    sendData: jsonEncode(body),
    withCredentials: true,
  ).timeout(timeout);
  return http.Response(
    req.responseText ?? '',
    req.status ?? 0,
    headers: req.responseHeaders.map(
      (key, value) => MapEntry(key.toLowerCase(), value),
    ),
  );
}

Future<http.Response> getWithBrowserCredentials(
  Uri uri, {
  required Duration timeout,
}) async {
  final req = await html.HttpRequest.request(
    uri.toString(),
    method: 'GET',
    withCredentials: true,
  ).timeout(timeout);
  return http.Response(
    req.responseText ?? '',
    req.status ?? 0,
    headers: req.responseHeaders.map(
      (key, value) => MapEntry(key.toLowerCase(), value),
    ),
  );
}
