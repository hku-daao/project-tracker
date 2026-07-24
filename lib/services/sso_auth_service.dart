import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import 'sso_auth_service_web.dart'
    if (dart.library.io) 'sso_auth_service_stub.dart';

/// HKU OIDC session via backend BFF (`/auth/*`).
class SsoAuthService {
  SsoAuthService._();

  static const Duration _httpTimeout = Duration(seconds: 20);

  static String? _cachedEmail;
  static String? _cachedName;
  static String? _cachedAccessToken;
  static String? _lastError;

  static String? get currentEmail => _cachedEmail;
  static String? get currentName => _cachedName;
  static String? get currentAccessToken => _cachedAccessToken;
  static String? get lastError => _lastError;

  static void clearLastError() {
    _lastError = null;
  }

  static String loginUrl() => '${ApiConfig.baseUrl}/auth/login';
  static String logoutUrl() => '${ApiConfig.baseUrl}/auth/logout';

  /// True when HKU redirected back with `?code=` (finish login before showing UI).
  static bool hasPendingOAuthCallback() {
    final params = readOAuthCallbackParams();
    final code = params.code?.trim();
    final has = code != null && code.isNotEmpty;
    debugPrint('hasPendingOAuthCallback=$has url=${readBrowserUrlForDebug()}');
    return has;
  }

  static String? peekUrlSsoError() {
    final err = readOAuthCallbackParams().ssoError?.trim();
    return (err == null || err.isEmpty) ? null : err;
  }

  static void clearUrlAuthParams() {
    clearOAuthCallbackFromUrl();
  }

  static Future<void> beginLogin() async {
    final url = loginUrl();
    debugPrint('beginLogin -> GET $url');
    _lastError = null;
    await navigateToUrl(url);
  }

  static Future<void> beginLogout() async {
    _clearCache();
    debugPrint('beginLogout -> ${logoutUrl()}');
    await navigateToUrl(logoutUrl());
  }

  static Future<void> navigateHome() async {
    final reloadToken = DateTime.now().millisecondsSinceEpoch;
    await navigateToUrl('/?admin_view_reload=$reloadToken');
  }

  static void _clearCache() {
    _cachedEmail = null;
    _cachedName = null;
    _cachedAccessToken = null;
  }

  /// After HKU redirects to `/?code=...&state=...`, exchange code for session.
  static Future<bool> completeCallbackIfPresent() async {
    final params = readOAuthCallbackParams();
    final code = params.code?.trim();
    if (code == null || code.isEmpty) {
      debugPrint('completeCallback: no code in URL');
      return false;
    }

    final url = '${ApiConfig.baseUrl}/auth/callback';
    debugPrint(
      'completeCallback: POST $url state=${params.state ?? "(none)"} codeLen=${code.length}',
    );

    try {
      final res = await postJsonWithBrowserCredentials(
        Uri.parse(url),
        body: {'code': code, 'state': params.state ?? ''},
        timeout: _httpTimeout,
      );
      debugPrint(
        'completeCallback: HTTP ${res.statusCode} body=${_truncate(res.body)}',
      );
      if (res.statusCode != 200) {
        _lastError = 'callback HTTP ${res.statusCode}: ${_truncate(res.body)}';
        clearOAuthCallbackFromUrl();
        return false;
      }
      final map = jsonDecode(res.body);
      if (map is! Map<String, dynamic>) {
        _lastError = 'callback JSON not a map';
        clearOAuthCallbackFromUrl();
        return false;
      }
      _cachedEmail = map['email']?.toString();
      _cachedName = map['name']?.toString();
      _cachedAccessToken = map['accessToken']?.toString();
      clearOAuthCallbackFromUrl();
      final ok = _cachedAccessToken?.isNotEmpty == true;
      debugPrint(
        'completeCallback: ok=$ok email=${_cachedEmail ?? "(none)"} tokenLen=${_cachedAccessToken?.length ?? 0}',
      );
      if (!ok) {
        _lastError = 'callback ok but missing accessToken';
      }
      return ok;
    } catch (e, st) {
      _lastError = 'callback exception: $e';
      debugPrint('completeCallback error: $e\n$st');
      clearOAuthCallbackFromUrl();
      return false;
    }
  }

  static Future<bool> refreshSession() async {
    final url = '${ApiConfig.baseUrl}/auth/session';
    debugPrint('refreshSession: GET $url');
    try {
      final res = await getWithBrowserCredentials(
        Uri.parse(url),
        timeout: _httpTimeout,
      );
      debugPrint(
        'refreshSession: HTTP ${res.statusCode} body=${_truncate(res.body)}',
      );
      if (res.statusCode != 200) {
        _clearCache();
        _lastError = 'session HTTP ${res.statusCode}';
        return false;
      }
      final map = jsonDecode(res.body);
      if (map is! Map<String, dynamic>) {
        _clearCache();
        _lastError = 'session JSON not a map';
        return false;
      }
      if (map['authenticated'] != true) {
        _clearCache();
        _lastError = 'session not authenticated';
        return false;
      }
      _cachedEmail = map['email']?.toString();
      _cachedName = map['name']?.toString();
      _cachedAccessToken = map['accessToken']?.toString();
      final ok = _cachedAccessToken?.isNotEmpty == true;
      debugPrint(
        'refreshSession: ok=$ok email=${_cachedEmail ?? "(none)"} tokenLen=${_cachedAccessToken?.length ?? 0}',
      );
      return ok;
    } catch (e, st) {
      _lastError = 'session exception: $e';
      debugPrint('refreshSession error: $e\n$st');
      _clearCache();
      return false;
    }
  }

  static String _truncate(String s, {int max = 500}) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}…';
  }
}
