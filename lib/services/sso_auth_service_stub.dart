import 'package:http/http.dart' as http;

Future<void> navigateToUrl(String url) async {}

({String? code, String? state, String? ssoError}) readOAuthCallbackParams() =>
    (code: null, state: null, ssoError: null);

void clearOAuthCallbackFromUrl() {}

String readBrowserUrlForDebug() => '';

Future<http.Response> postJsonWithBrowserCredentials(
  Uri uri, {
  required Map<String, dynamic> body,
  required Duration timeout,
}) {
  return http
      .post(uri, headers: const {'Content-Type': 'application/json'}, body: '')
      .timeout(timeout);
}

Future<http.Response> getWithBrowserCredentials(
  Uri uri, {
  required Duration timeout,
}) {
  return http.get(uri).timeout(timeout);
}
