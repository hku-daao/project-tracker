import '../services/sso_auth_service.dart';

/// Active user from HKU SSO session (web).
String? activeUserEmail() {
  final email = SsoAuthService.currentEmail?.trim();
  return (email == null || email.isEmpty) ? null : email;
}

String? activeUserStorageKey() => activeUserEmail();

Future<String?> activeUserIdToken() async {
  var token = SsoAuthService.currentAccessToken;
  if (token == null || token.isEmpty) {
    await SsoAuthService.refreshSession();
    token = SsoAuthService.currentAccessToken;
  }
  return token;
}

Future<void> signOutActiveUser() async {
  await SsoAuthService.beginLogout();
}
