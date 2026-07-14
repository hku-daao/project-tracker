import 'package:flutter/material.dart';

import '../../services/sso_auth_service.dart';
import '../../widgets/project_tracker_logo.dart';
import '../asana/asana_theme.dart';
import '../asana_landing_screen.dart';

/// HKU Portal SSO sign-in (redirects to `/auth/login` on the backend).
class HkuSsoLoginScreen extends StatefulWidget {
  const HkuSsoLoginScreen({super.key});

  @override
  State<HkuSsoLoginScreen> createState() => _HkuSsoLoginScreenState();
}

class _HkuSsoLoginScreenState extends State<HkuSsoLoginScreen> {
  bool _loading = false;

  Future<void> _signInWithHku() async {
    setState(() => _loading = true);
    debugPrint('loginScreen: Sign in with HKU clicked');
    try {
      await SsoAuthService.beginLogin();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start HKU sign-in: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      setState(() => _loading = false);
    }
    // beginLogin navigates away; reset spinner if navigation did not happen.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    const palette = AsanaLandingPalette.asana;
    final theme = buildAsanaTheme(Theme.of(context), seedColor: palette.accent);

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: palette.banner,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: palette.listSurface,
                elevation: 18,
                shadowColor: Colors.black45,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _HkuLoginBrand(),
                      const SizedBox(height: 24),
                      Text(
                        'Sign in with your HKU account',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: kAsanaTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _signInWithHku,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF005EB8),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Sign in with HKU'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HkuLoginBrand extends StatelessWidget {
  const _HkuLoginBrand();

  @override
  Widget build(BuildContext context) {
    const logoHeight = 56.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ProjectTrackerLogo(height: logoHeight),
        const SizedBox(width: 12),
        Text(
          'Project\nTracker',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: kAsanaTextPrimary,
            height: 1.05,
          ),
        ),
      ],
    );
  }
}
