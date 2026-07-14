import 'package:flutter/foundation.dart';

import 'web_host_env_stub.dart'
    if (dart.library.html) 'web_host_env_web.dart';

/// Backend API base URL — never hardcode host ports here.
///
/// Prefer `--dart-define=API_BASE_URL=...` (from `.env` via build/run scripts).
/// On deployed web hosts, falls back to the page origin (same-origin nginx proxy).
class ApiConfig {
  ApiConfig._();

  /// Backend base URL (no trailing slash).
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/+$'), '');
    if (kIsWeb && isDeployedWebHost) {
      return webOrigin.replaceAll(RegExp(r'/+$'), '');
    }
    throw StateError(
      'API_BASE_URL is not set. Use ./scripts/run_flutter_web_local.sh '
      'or pass --dart-define=API_BASE_URL=... (values live in .env).',
    );
  }

  /// Health check path (backend returns JSON with ok: true).
  static const String healthPath = '/';
}
