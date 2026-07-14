Future<void> navigateToUrl(String url) async {}

({String? code, String? state, String? ssoError}) readOAuthCallbackParams() =>
    (code: null, state: null, ssoError: null);

void clearOAuthCallbackFromUrl() {}

String readBrowserUrlForDebug() => '';
