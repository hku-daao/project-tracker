import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/sso_auth_service.dart';
import '../../web_startup.dart';
import '../app_bootstrap.dart';
import 'hku_sso_login_screen.dart';

/// HKU SSO login gate; shows [AppBootstrap] when authenticated.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// False until OAuth callback or cookie session check has finished.
  bool _resolved = false;
  bool _authenticated = false;
  bool _bootstrapReady = false;
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _finishAuthCheck({required bool authenticated}) {
    if (!mounted) return;
    if (!authenticated && kIsWeb) {
      dismissHtmlStartupLoader();
    }
    SsoAuthService.clearLastError();
    setState(() {
      _resolved = true;
      _authenticated = authenticated;
      _signingIn = false;
    });
  }

  void _onBootstrapReady() {
    if (!mounted || _bootstrapReady) return;
    if (kIsWeb) {
      dismissHtmlStartupLoader();
    }
    setState(() => _bootstrapReady = true);
  }

  Future<void> _init() async {
    final urlError = SsoAuthService.peekUrlSsoError();
    if (urlError != null) {
      debugPrint('SsoAuthGate: URL sso_error=$urlError');
    }

    final pendingOAuth = SsoAuthService.hasPendingOAuthCallback();
    if (!pendingOAuth && urlError != null) {
      SsoAuthService.clearUrlAuthParams();
    }
    if (pendingOAuth && mounted) {
      setState(() => _signingIn = true);
    }

    try {
      if (pendingOAuth) {
        debugPrint('SsoAuthGate: finishing OAuth callback');
        final ok = await SsoAuthService.completeCallbackIfPresent().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('SsoAuthGate: callback TIMEOUT 15s');
            return false;
          },
        );
        if (!mounted) return;
        debugPrint('SsoAuthGate: callback result authenticated=$ok');
        _finishAuthCheck(authenticated: ok);
        return;
      }

      debugPrint('SsoAuthGate: checking existing session');
      final ok = await SsoAuthService.refreshSession().timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          debugPrint('SsoAuthGate: session TIMEOUT 4s');
          return false;
        },
      );
      if (!mounted) return;
      debugPrint('SsoAuthGate: session result authenticated=$ok');
      _finishAuthCheck(authenticated: ok);
    } catch (e, st) {
      debugPrint('SsoAuthGate init failed: $e\n$st');
      _finishAuthCheck(authenticated: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolved && !_authenticated) {
      return const HkuSsoLoginScreen();
    }

    final showHome = _resolved && _authenticated && _bootstrapReady;

    // OAuth return: animated loader while exchanging the code.
    if (!_resolved && _signingIn) {
      return const Scaffold(
        body: StartupLoadingView(label: 'Signing in'),
      );
    }

    // Session check: plain backdrop only (no progress animation).
    if (!_resolved) {
      return const ColoredBox(
        color: Color(0xFF2A2B2C),
        child: SizedBox.expand(),
      );
    }

    // Authenticated: bootstrap loads once; overlay removed when data is ready.
    return Stack(
      fit: StackFit.expand,
      children: [
        AppBootstrap(
          suppressLoadingUi: true,
          onReady: _onBootstrapReady,
        ),
        if (!showHome)
          const Scaffold(
            body: StartupLoadingView(label: 'Loading'),
          ),
      ],
    );
  }
}
