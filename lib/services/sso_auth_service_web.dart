import 'dart:html' as html;

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
