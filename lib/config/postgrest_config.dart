import 'package:flutter/foundation.dart';

import 'web_host_env_stub.dart'
    if (dart.library.html) 'web_host_env_web.dart';

/// PostgREST API configuration for the Flutter app.
///
/// Prefer `--dart-define=POSTGREST_URL=...` (from `.env` via build/run scripts).
/// On deployed web hosts, falls back to the page origin.
class PostgrestConfig {
  PostgrestConfig._();

  /// REST root without trailing slash.
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('POSTGREST_URL', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/+$'), '');
    if (kIsWeb && isDeployedWebHost) {
      return webOrigin.replaceAll(RegExp(r'/+$'), '');
    }
    throw StateError(
      'POSTGREST_URL is not set. Use ./scripts/run_flutter_web_local.sh '
      'or pass --dart-define=POSTGREST_URL=... (values live in .env).',
    );
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

  static bool get isConfigured {
    try {
      return baseUrl.isNotEmpty;
    } on StateError {
      return false;
    }
  }
}
