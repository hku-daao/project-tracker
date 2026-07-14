import 'package:flutter/foundation.dart';

import 'environment_config.dart';
import 'web_host_env_stub.dart'
    if (dart.library.html) 'web_host_env_web.dart';

/// PostgREST API configuration for the Flutter app.
///
/// **Deployed web:** same origin as the app (`POSTGREST_URL` at build time).
/// **Local:** `http://127.0.0.1:3001` + anon JWT from build defines.
class PostgrestConfig {
  PostgrestConfig._();

  static const String _localBaseUrl = 'http://127.0.0.1:3001';

  /// REST root without trailing slash, e.g. `http://127.0.0.1:3001`.
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('POSTGREST_URL', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/+$'), '');
    if (kIsWeb && isDeployedWebHost) {
      return webOrigin.replaceAll(RegExp(r'/+$'), '');
    }
    return _localBaseUrl;
  }

  /// PostgREST path prefix used by the app client.
  static String get restBaseUrl => '$baseUrl/rest/v1';

  static String get anonKey {
    const fromEnv = String.fromEnvironment(
      'POSTGREST_ANON_KEY',
      defaultValue: '',
    );
    return fromEnv.trim();
  }

  /// When false, PostgREST accepts REST without JWT (see docker-compose PGRST_JWT_SECRET).
  static bool get jwtAuthEnabled => anonKey.isNotEmpty;

  static bool get isConfigured => baseUrl.isNotEmpty;
}
