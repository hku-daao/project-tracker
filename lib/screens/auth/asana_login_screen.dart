import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/copyable_snackbar.dart';
import '../asana/asana_theme.dart';
import '../asana_landing_screen.dart';

class AsanaLoginScreen extends StatefulWidget {
  const AsanaLoginScreen({super.key});

  @override
  State<AsanaLoginScreen> createState() => _AsanaLoginScreenState();
}

class _AsanaLoginScreenState extends State<AsanaLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode(debugLabel: 'asanaLoginEmail');
  final _passwordFocus = FocusNode(debugLabel: 'asanaLoginPassword');
  final _passwordVisibilityFocus = FocusNode(
    debugLabel: 'asanaLoginPasswordVisibility',
    skipTraversal: true,
  );
  bool _isSignUp = false;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _passwordVisibilityFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (_isSignUp) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      showCopyableSnackBar(
        context,
        _authMessage(e),
        backgroundColor: Colors.red.shade700,
      );
    } catch (e) {
      if (!mounted) return;
      showCopyableSnackBar(
        context,
        'Error: $e',
        backgroundColor: Colors.red.shade700,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found for this email';
      case 'wrong-password':
        return 'Wrong password';
      case 'invalid-email':
        return 'Invalid email address';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'email-already-in-use':
        return 'An account already exists for this email';
      case 'weak-password':
        return 'Password is too weak (use at least 6 characters)';
      case 'invalid-credential':
        return 'Invalid email or password';
      default:
        return e.message ?? 'Sign in failed';
    }
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                    child: Form(
                      key: _formKey,
                      child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Center(child: _AsanaLoginBrand()),
                            const SizedBox(height: 24),
                            Text(
                              _isSignUp ? 'Create an account' : 'Sign in',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: kAsanaTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Use your project tracker account',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: kAsanaTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _emailField(),
                            const SizedBox(height: 14),
                            _passwordField(),
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: _loading ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: palette.accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 160,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(999),
                                        ),
                                        child: LinearProgressIndicator(
                                          minHeight: 5,
                                          backgroundColor: Color(0x66FFFFFF),
                                          color: Colors.white,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      _isSignUp ? 'Create account' : 'Sign in',
                                    ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () =>
                                        setState(() => _isSignUp = !_isSignUp),
                              child: Text(
                                _isSignUp
                                    ? 'Already have an account? Sign in'
                                    : 'No account? Create one',
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Data entered or collected through this service will only be used to organize, assign, update, and monitor departmental projects and tasks.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: kAsanaTextSecondary,
                                fontSize: 10,
                                height: 1.35,
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
          ),
        ),
      ),
    );
  }

  Widget _emailField() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: TextFormField(
        controller: _emailController,
        focusNode: _emailFocus,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        decoration: _inputDecoration(
          label: 'Email',
          hint: 'you@example.com',
          icon: Icons.email_outlined,
        ),
        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
        validator: (v) {
          final value = v?.trim() ?? '';
          if (value.isEmpty) return 'Enter your email';
          if (!value.contains('@') || !value.contains('.')) {
            return 'Enter a valid email';
          }
          return null;
        },
      ),
    );
  }

  Widget _passwordField() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: TextFormField(
        controller: _passwordController,
        focusNode: _passwordFocus,
        obscureText: _obscurePassword,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        decoration:
            _inputDecoration(
              label: _isSignUp ? 'Password (min 6 characters)' : 'Password',
              hint: 'Enter password',
              icon: Icons.lock_outline,
            ).copyWith(
              suffixIcon: IconButton(
                focusNode: _passwordVisibilityFocus,
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
        onFieldSubmitted: (_) {
          if (!_loading) _submit();
        },
        validator: (v) {
          final value = v ?? '';
          if (value.isEmpty) return 'Enter your password';
          if (_isSignUp && value.length < 6) {
            return 'Use at least 6 characters';
          }
          return null;
        },
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF6F7F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AsanaLandingPalette.asana.accent),
      ),
    );
  }
}

class _AsanaLoginBrand extends StatelessWidget {
  const _AsanaLoginBrand();

  @override
  Widget build(BuildContext context) {
    const logoHeight = 56.0;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheH = (logoHeight * dpr).round().clamp(1, 4096);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/logo.png',
          height: logoHeight,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheHeight: cacheH,
          semanticLabel: 'Project Tracker logo',
        ),
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
