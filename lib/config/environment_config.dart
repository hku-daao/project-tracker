/// Compile-time deploy target for the Flutter app.
///
/// URLs and ports are **not** stored here. Pass them at build/run time from `.env`:
/// - `--dart-define=API_BASE_URL=...`
/// - `--dart-define=POSTGREST_URL=...`
/// - `--dart-define=POSTGREST_ANON_KEY=...`
/// - `--dart-define=DEPLOY_ENV=testing|production`
///
/// Use `./scripts/build_web_for_hku.sh` (deploy) or
/// `./scripts/run_flutter_web_local.sh` (local).
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
