/// Compile-time deploy target for the Flutter app.
///
/// | `DEPLOY_ENV`   | PostgREST API | Backend API |
/// |----------------|---------------|-------------|
/// | `testing` (default) | local / env override | local / Railway |
/// | `production`   | env override  | Railway |
///
/// Firebase uses the **same** project (`daao-a20c6`) for both; only hosting URL differs.
///
/// ### Optional overrides
/// - `--dart-define=POSTGREST_URL=...` — PostgREST base URL
/// - `--dart-define=POSTGREST_ANON_KEY=...` — anon JWT for PostgREST
/// - `--dart-define=API_BASE_URL=...` — overrides [ApiConfig.baseUrl].
class AppEnvironment {
  AppEnvironment._();

  /// `testing` (default) or `production`.
  static const String deployEnv = String.fromEnvironment(
    'DEPLOY_ENV',
    defaultValue: 'testing',
  );

  static bool get isProduction => deployEnv.toLowerCase() == 'production';

  static bool get isTesting => !isProduction;

  /// Short label for UI / logs.
  static String get label => isProduction ? 'production' : 'testing';
}
