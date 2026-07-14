/// Only this email may open the System Admin page.
/// Set at build time via `--dart-define=ADMIN_EMAIL=...` (from .env in build script).
class AdminConfig {
  AdminConfig._();

  static const String systemAdminEmail = String.fromEnvironment(
    'ADMIN_EMAIL',
    defaultValue: '',
  );
}
